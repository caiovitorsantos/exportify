# frozen_string_literal: true

require 'fileutils'
require 'optparse'
require_relative 'auth'
require_relative 'config'
require_relative 'spotify'
require_relative 'youtube'
require_relative 'downloader'
require_relative 'tagger'
require_relative 'playlist_meta'
require_relative 'analyzer'

module Exportify
  module CLI
    DEFAULT_OUTPUT_DIR = 'musics'

    module_function

    def run(argv)
      return run_init(argv[1]) if argv[0] == 'init'
      return run_web(argv[1..]) if argv[0] == 'web'

      retag   = false
      sync    = false
      browser = nil
      analyze = true

      parser = OptionParser.new do |opts|
        opts.banner = "Usage:\n  " \
                      "exportify init\n  " \
                      "exportify web [--port PORTA]\n  " \
                      "exportify <playlist_or_video_url> [--retag] [--sync] [--browser=NOME]\n  " \
                      'exportify "<nome_da_playlist>" [--retag] [--sync]   (usa a URL salva no download)'
        opts.on('--retag', 'Regravar tags ID3 nos arquivos existentes') { retag = true }
        opts.on('--sync',  'Remover arquivos locais que não estão mais na playlist') { sync = true }
        opts.on('--browser=NOME', 'Navegador para extrair cookies (playlists privadas do YouTube)') do |b|
          browser = b
        end
        opts.on('--no-analyze', 'Não detectar BPM/key após o download') { analyze = false }
      end

      parser.parse!(argv)
      target = argv[0]

      abort parser.banner unless target

      url, source = resolve_target(target)
      abort "Invalid playlist URL: #{target}. Informe a URL ou o nome de uma playlist já baixada." unless source

      puts 'Fetching playlist...'
      chaptered = false

      name, tracks =
        case source
        when :spotify
          fetch_spotify_playlist(url)
        when :youtube
          data = YouTube.fetch_playlist(url, browser: browser)
          [data[:name], data[:tracks]]
        when :youtube_video
          data = YouTube.fetch_video(url, browser: browser)
          chaptered = data[:chaptered]
          [data[:name], data[:tracks]]
        end

      output_dir = File.expand_path(File.join(Config.output_dir, Downloader.sanitize(name)))

      FileUtils.mkdir_p(output_dir)
      PlaylistMeta.write(output_dir, url: canonical_url(url, source), source: source, name: name)

      puts "#{tracks.size} tracks found"
      puts "Output: #{output_dir}\n\n"

      if chaptered
        result = download_chaptered_video({ name: name, tracks: tracks }, output_dir,
                                          retag: retag, browser: browser, analyze: analyze)
        ok     = result[:ok]
        skip   = result[:skip]
        failed = result[:failed]
      else
        ok = skip = failed = 0

        tracks.each_with_index do |track, i|
          artist   = Downloader.sanitize(track[:artist])
          name     = Downloader.sanitize(track[:name])
          filename = "#{artist} - #{name}.mp3"
          filepath = File.join(output_dir, filename)

          print "[#{i + 1}/#{tracks.size}] #{filename} "

          if retag
            if File.exist?(filepath)
              Tagger.tag(filepath, track)
              puts '(retagged)'
              ok += 1
            else
              puts '(not found, skipping)'
              skip += 1
            end
            next
          end

          if File.exist?(filepath)
            puts '(already exists, skipping)'
            skip += 1
            next
          end

          puts '(downloading...)'
          success = Downloader.download(track, output_dir, browser: browser)

          if success && File.exist?(filepath)
            Tagger.tag(filepath, track)
            analyze_file(filepath) if analyze
            ok += 1
          else
            failed += 1
          end
        end
      end

      removed = 0

      if sync
        expected = tracks.to_set do |track|
          "#{Downloader.sanitize(track[:artist])} - #{Downloader.sanitize(track[:name])}.mp3"
        end

        Dir.glob(File.join(output_dir, '*.mp3')).each do |file|
          next if expected.include?(File.basename(file))

          puts "Removing #{File.basename(file)}"
          File.delete(file)
          removed += 1
        end
      end

      if retag
        puts "\nDone: #{ok} retagged, #{skip} not found."
      else
        removed_msg = sync ? ", #{removed} removed" : ''
        puts "\nDone: #{ok} downloaded, #{skip} skipped, #{failed} failed#{removed_msg}."
      end
    end

    def fetch_spotify_playlist(url)
      playlist_url = canonical_url(url, :spotify)
      playlist_id  = playlist_url.match(%r{playlist/([A-Za-z0-9]+)})&.captures&.first
      abort 'Invalid playlist URL' unless playlist_id

      abort 'Credenciais não configuradas. Execute: exportify init' unless Auth.client_id && Auth.client_secret

      puts 'Authenticating with Spotify...'
      token = Auth.access_token

      name   = Spotify.playlist_name(playlist_id, token)
      tracks = Spotify.playlist_tracks(playlist_id, token)
      tracks = Spotify.enrich_with_genres(tracks, token)
      [name, tracks]
    end

    def download_chaptered_video(data, output_dir, retag: false, browser: nil, analyze: true)
      tracks = data[:tracks]
      expected_files = tracks.map do |track|
        "#{Downloader.sanitize(track[:artist])} - #{Downloader.sanitize(track[:name])}.mp3"
      end

      if retag
        ok = skip = 0

        tracks.each_with_index do |track, i|
          filepath = File.join(output_dir, expected_files[i])

          if File.exist?(filepath)
            Tagger.tag(filepath, track)
            ok += 1
          else
            skip += 1
          end
        end

        return { ok: ok, skip: skip, failed: 0 }
      end

      if expected_files.all? { |f| File.exist?(File.join(output_dir, f)) }
        return { ok: 0, skip: tracks.size, failed: 0 }
      end

      abort 'Nome de navegador inválido.' if browser&.start_with?('-')

      video_id  = tracks.first[:video_id]
      video_url = "https://www.youtube.com/watch?v=#{video_id}"

      cmd = [
        'yt-dlp', video_url,
        '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
        '--split-chapters',
        '--paths', output_dir,
        '--output', 'chapter:%(section_number)s - %(section_title)s.%(ext)s',
        '--output', '%(title)s.%(ext)s',
        '--no-warnings', '--quiet'
      ]
      cmd += ['--cookies-from-browser', browser] if browser

      success = system(*cmd)

      return { ok: 0, skip: 0, failed: tracks.size } unless success

      ok = 0

      tracks.each_with_index do |track, i|
        source_name = Dir.glob("#{i + 1} - *.mp3", base: output_dir).first
        next unless source_name

        source_file = File.join(output_dir, source_name)
        target_file = File.join(output_dir, expected_files[i])
        File.rename(source_file, target_file)
        Tagger.tag(target_file, track)
        analyze_file(target_file) if analyze
        ok += 1
      end

      Dir.glob('*.mp3', base: output_dir).each do |name|
        File.delete(File.join(output_dir, name)) unless expected_files.include?(name)
      end

      { ok: ok, skip: 0, failed: tracks.size - ok }
    end

    def run_init(dir = nil)
      require 'io/console'

      cfg = Config.load
      tty = open_tty

      puts '=== Exportify Setup ==='
      puts

      default_dir = dir || cfg.fetch('output_dir', DEFAULT_OUTPUT_DIR)
      print "Diretório principal [#{default_dir}]: "
      dir_input = tty.gets.chomp
      new_dir   = dir_input.empty? ? default_dir : dir_input

      current_id = cfg['spotify_client_id'] || ''
      id_hint    = current_id.empty? ? '' : " [#{current_id[0..7]}...]"
      print "Spotify Client ID#{id_hint}: "
      id_input = tty.gets.chomp
      new_id   = id_input.empty? ? current_id : id_input

      secret_hint = cfg['spotify_client_secret'] ? ' [configurado]' : ''
      print "Spotify Client Secret#{secret_hint}: "
      new_secret = read_secret(tty)
      puts
      new_secret = cfg['spotify_client_secret'] if new_secret.empty?

      abort 'Client ID não pode ser vazio.' if new_id.empty?
      abort 'Client Secret não pode ser vazio.' if new_secret.to_s.empty?

      Config.save(
        'output_dir' => File.expand_path(new_dir),
        'spotify_client_id' => new_id,
        'spotify_client_secret' => new_secret
      )

      puts "\nConfiguração salva em #{Config::CONFIG_PATH}"
    ensure
      tty&.close
    end

    def run_web(argv)
      port = 4567

      OptionParser.new do |opts|
        opts.banner = 'Usage: exportify web [--port PORTA]'
        opts.on('--port PORTA', Integer, 'Porta do servidor (padrão: 4567)') { |value| port = value }
      end.parse!(argv)

      require_relative 'web_server'
      WebServer.start(port: port)
    end

    def open_tty
      IO.console || $stdin
    end

    def read_secret(tty)
      if tty.respond_to?(:noecho)
        tty.noecho(&:gets).chomp
      else
        tty.gets.chomp
      end
    end

    def canonical_url(url, source)
      source == :spotify ? url.split('?', 2).first : url
    end

    def resolve_target(target)
      source = source_for(target)
      return [target, source] if source

      meta = PlaylistMeta.read(target)
      url  = meta && meta[:url]
      saved_source = url && source_for(url)
      return [url, saved_source] if saved_source

      nil
    end

    def source_for(url)
      return :spotify if url.include?('open.spotify.com')
      return :youtube if url.match?(%r{(music\.)?youtube\.com/playlist})
      return :youtube_video if url.match?(%r{(music\.)?youtube\.com/watch}) && url.match?(/[?&]v=/)

      nil
    end

    def analyze_file(filepath)
      result = Analyzer.analyze(filepath)
      Tagger.tag_analysis(filepath, **result) if result
    end
  end
end

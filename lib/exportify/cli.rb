# frozen_string_literal: true

require 'fileutils'
require 'optparse'
require_relative 'auth'
require_relative 'config'
require_relative 'spotify'
require_relative 'youtube'
require_relative 'downloader'
require_relative 'tagger'

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

      parser = OptionParser.new do |opts|
        opts.banner = "Usage:\n  " \
                      "exportify init\n  " \
                      "exportify web [--port PORTA]\n  " \
                      'exportify <playlist_url> [--retag] [--sync] [--browser=NOME]'
        opts.on('--retag', 'Regravar tags ID3 nos arquivos existentes') { retag = true }
        opts.on('--sync',  'Remover arquivos locais que não estão mais na playlist') { sync = true }
        opts.on('--browser=NOME', 'Navegador para extrair cookies (playlists privadas do YouTube)') do |b|
          browser = b
        end
      end

      parser.parse!(argv)
      url = argv[0]

      abort parser.banner unless url

      source = source_for(url)
      abort 'Invalid playlist URL' unless source

      puts 'Fetching playlist...'
      name, tracks =
        case source
        when :spotify
          fetch_spotify_playlist(url)
        when :youtube
          data = YouTube.fetch_playlist(url, browser: browser)
          [data[:name], data[:tracks]]
        end

      output_dir = File.expand_path(File.join(Config.output_dir, Downloader.sanitize(name)))

      FileUtils.mkdir_p(output_dir)

      puts "#{tracks.size} tracks found"
      puts "Output: #{output_dir}\n\n"

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
        success = Downloader.download(track, output_dir)

        if success && File.exist?(filepath)
          Tagger.tag(filepath, track)
          ok += 1
        else
          failed += 1
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
      playlist_url = url.split('?', 2).first
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

    def source_for(url)
      return :spotify if url.include?('open.spotify.com')
      return :youtube if url.match?(%r{(music\.)?youtube\.com/playlist})

      nil
    end
  end
end

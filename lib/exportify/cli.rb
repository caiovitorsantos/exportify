# frozen_string_literal: true

require 'fileutils'
require 'optparse'
require_relative 'auth'
require_relative 'config'
require_relative 'spotify'
require_relative 'downloader'
require_relative 'tagger'

module Exportify
  module CLI
    DEFAULT_OUTPUT_DIR = 'musics'

    module_function

    def run(argv)
      return run_init(argv[1]) if argv[0] == 'init'

      retag = false
      sync  = false

      parser = OptionParser.new do |opts|
        opts.banner = "Usage:\n  " \
                      "exportify init [<diretório>]\n  " \
                      'exportify <spotify_playlist_url> [--retag] [--sync]'
        opts.on('--retag', 'Regravar tags ID3 nos arquivos existentes') { retag = true }
        opts.on('--sync',  'Remover arquivos locais que não estão mais na playlist') { sync = true }
      end

      parser.parse!(argv)
      playlist_url = argv[0]

      abort parser.banner unless playlist_url

      unless ENV['SPOTIFY_CLIENT_ID'] && ENV['SPOTIFY_CLIENT_SECRET']
        abort 'Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET environment variables'
      end

      playlist_id = playlist_url.match(%r{playlist/([A-Za-z0-9]+)})&.captures&.first
      abort 'Invalid playlist URL' unless playlist_id

      puts 'Authenticating with Spotify...'
      token = Auth.access_token

      puts 'Fetching playlist...'
      name       = Spotify.playlist_name(playlist_id, token)
      tracks     = Spotify.playlist_tracks(playlist_id, token)
      tracks     = Spotify.enrich_with_genres(tracks, token)
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

    def run_init(dir)
      path = File.expand_path(dir || DEFAULT_OUTPUT_DIR)
      Config.save('output_dir' => path)
      puts "Diretório principal definido: #{path}"
      puts "Salvo em #{Config::CONFIG_PATH}"
    end
  end
end

# frozen_string_literal: true

require 'fileutils'
require_relative 'auth'
require_relative 'spotify'
require_relative 'downloader'
require_relative 'tagger'

module Exportify
  module CLI
    OUTPUT_DIR = File.expand_path('~/projects/exportify/musics')

    module_function

    def run(argv)
      retag = argv.delete('--retag')
      playlist_url = argv[0]

      unless playlist_url
        abort 'Usage: exportify <spotify_playlist_url> [--retag]'
      end

      unless ENV['SPOTIFY_CLIENT_ID'] && ENV['SPOTIFY_CLIENT_SECRET']
        abort 'Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET environment variables'
      end

      playlist_id = playlist_url.match(/playlist\/([A-Za-z0-9]+)/)&.captures&.first
      abort 'Invalid playlist URL' unless playlist_id

      FileUtils.mkdir_p(OUTPUT_DIR)

      puts 'Authenticating with Spotify...'
      token = Auth.access_token

      puts 'Fetching playlist...'
      tracks = Spotify.playlist_tracks(playlist_id, token)
      puts "#{tracks.size} tracks found\n\n"

      ok = skip = failed = 0

      tracks.each_with_index do |track, i|
        artist   = Downloader.sanitize(track[:artist])
        name     = Downloader.sanitize(track[:name])
        filename = "#{artist} - #{name}.mp3"
        filepath = File.join(OUTPUT_DIR, filename)

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
        success = Downloader.download(track, OUTPUT_DIR)

        if success && File.exist?(filepath)
          Tagger.tag(filepath, track)
          ok += 1
        else
          failed += 1
        end
      end

      if retag
        puts "\nDone: #{ok} retagged, #{skip} not found."
      else
        puts "\nDone: #{ok} downloaded, #{skip} skipped, #{failed} failed."
      end
    end
  end
end

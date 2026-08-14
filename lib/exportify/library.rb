# frozen_string_literal: true

require 'open3'
require 'json'
require_relative 'config'

module Exportify
  module Library
    module_function

    def playlists
      root = File.expand_path(Config.output_dir)
      return [] unless Dir.exist?(root)

      Dir.children(root)
         .select { |entry| File.directory?(File.join(root, entry)) }
         .sort
         .map { |name| { name: name, track_count: Dir.glob(File.join(root, name, '*.mp3')).size } }
    end

    def read_tags(filepath)
      script = <<~PY
        from mutagen.mp3 import MP3
        import json

        audio = MP3(#{filepath.inspect})
        tags = audio.tags or {}

        print(json.dumps({
          'title': str(tags.get('TIT2', '')),
          'all_artists': str(tags.get('TPE1', '')),
          'artist': str(tags.get('TPE2', '')),
          'album': str(tags.get('TALB', '')),
          'year': str(tags.get('TDRC', '')),
          'track_number': str(tags.get('TRCK', '')),
          'genre': str(tags.get('TCON', '')),
          'bpm': str(tags.get('TBPM', '')),
          'key': str(tags.get('TKEY', '')),
          'duration_seconds': audio.info.length,
        }))
      PY

      stdout, _stderr, status = Open3.capture3('python3', '-c', script)
      return nil unless status.success?

      JSON.parse(stdout, symbolize_names: true)
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def playlist_dir(playlist_name)
      root = File.expand_path(Config.output_dir)
      return nil unless Dir.exist?(root)
      return nil unless Dir.children(root).include?(playlist_name)

      dir = File.join(root, playlist_name)
      return nil unless File.directory?(dir)

      dir
    end

    def fallback_from_filename(filename)
      base = File.basename(filename, '.mp3')
      artist, title = base.split(' - ', 2)
      { artist: artist || base, title: title || base }
    end

    def tracks(playlist_name)
      dir = playlist_dir(playlist_name)
      return nil unless dir

      Dir.glob(File.join(dir, '*.mp3'))
         .map { |filepath| track_summary(filepath) }
         .sort_by { |summary| [summary[:sort_key], summary[:filename]] }
         .each { |summary| summary.delete(:sort_key) }
    end

    def genres(playlist_name)
      dir = playlist_dir(playlist_name)
      return [] unless dir

      Dir.glob(File.join(dir, '*.mp3')).filter_map do |filepath|
        tags = read_tags(filepath)
        presence(tags && tags[:genre])
      end.uniq.sort
    end

    def track_summary(filepath)
      filename = File.basename(filepath)
      tags     = read_tags(filepath)
      fallback = fallback_from_filename(filename)

      title  = tags && !tags[:title].to_s.strip.empty? ? tags[:title] : fallback[:title]
      artist = tags && !tags[:artist].to_s.strip.empty? ? tags[:artist] : fallback[:artist]
      number = tags && tags[:track_number].to_s[/\d+/]&.to_i
      genre  = presence(tags && tags[:genre])

      { filename: filename, title: title, artist: artist, genre: genre, sort_key: number || Float::INFINITY }
    end

    def track(playlist_name, filename)
      dir = playlist_dir(playlist_name)
      return nil unless dir
      return nil unless Dir.children(dir).include?(filename)

      filepath = File.join(dir, filename)
      tags     = read_tags(filepath)
      fallback = fallback_from_filename(filename)

      {
        title: presence(tags && tags[:title]) || fallback[:title],
        artist: presence(tags && tags[:artist]) || fallback[:artist],
        all_artists: presence(tags && tags[:all_artists]) || fallback[:artist],
        album: presence(tags && tags[:album]),
        year: presence(tags && tags[:year]),
        track_number: presence(tags && tags[:track_number]),
        genre: presence(tags && tags[:genre]),
        duration_seconds: tags && tags[:duration_seconds],
        file_size_bytes: File.size(filepath)
      }
    end

    def presence(value)
      value.to_s.strip.empty? ? nil : value
    end
  end
end

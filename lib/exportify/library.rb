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
          'duration_seconds': audio.info.length,
        }))
      PY

      stdout, _stderr, status = Open3.capture3('python3', '-c', script)
      return nil unless status.success?

      JSON.parse(stdout, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end
  end
end

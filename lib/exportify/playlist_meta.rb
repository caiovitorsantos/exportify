# frozen_string_literal: true

require 'json'
require_relative 'library'

module Exportify
  module PlaylistMeta
    FILENAME = '.exportify.json'

    module_function

    def write(dir, url:, source:, name:)
      meta = {
        'url' => url,
        'source' => source.to_s,
        'name' => name,
        'synced_at' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      }

      File.write(File.join(dir, FILENAME), JSON.pretty_generate(meta))
    end

    def read(playlist_name)
      dir = Library.playlist_dir(playlist_name)
      return nil unless dir

      path = File.join(dir, FILENAME)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path), symbolize_names: true)
    rescue JSON::ParserError
      nil
    end
  end
end

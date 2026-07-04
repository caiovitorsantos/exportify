# frozen_string_literal: true

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
  end
end

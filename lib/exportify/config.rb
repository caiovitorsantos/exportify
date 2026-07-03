# frozen_string_literal: true

require 'json'

module Exportify
  module Config
    CONFIG_PATH = File.expand_path('~/.exportify')

    module_function

    def load
      return {} unless File.exist?(CONFIG_PATH)
      JSON.parse(File.read(CONFIG_PATH))
    rescue JSON::ParserError
      {}
    end

    def save(data)
      File.write(CONFIG_PATH, JSON.pretty_generate(load.merge(data)))
    end

    def output_dir
      load['output_dir'] || CLI::DEFAULT_OUTPUT_DIR
    end
  end
end

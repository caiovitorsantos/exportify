# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class ConfigTest < Minitest::Test
  def setup
    @tmp_config = File.join(Dir.mktmpdir, '.exportify')
  end

  def with_tmp_config(&block)
    Exportify::Config.stub(:load, -> { File.exist?(@tmp_config) ? JSON.parse(File.read(@tmp_config)) : {} }) do
      Exportify::Config.stub(:save, ->(data) { File.write(@tmp_config, JSON.pretty_generate(data)) }, &block)
    end
  end

  def test_load_returns_empty_hash_when_no_config_file
    with_tmp_config do
      assert_equal({}, Exportify::Config.load)
    end
  end

  def test_save_and_load_roundtrip
    with_tmp_config do
      Exportify::Config.save('output_dir' => '/tmp/musics')

      assert_equal '/tmp/musics', Exportify::Config.load['output_dir']
    end
  end

  def test_output_dir_defaults_to_musics_when_no_config
    with_tmp_config do
      assert_equal Exportify::CLI::DEFAULT_OUTPUT_DIR, Exportify::Config.output_dir
    end
  end

  def test_output_dir_returns_configured_value
    with_tmp_config do
      Exportify::Config.save('output_dir' => '/home/user/music')

      assert_equal '/home/user/music', Exportify::Config.output_dir
    end
  end
end

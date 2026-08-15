# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

class PlaylistMetaTest < Minitest::Test
  def test_write_saves_url_source_and_name
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Deep House')
      FileUtils.mkdir_p(playlist_dir)

      Exportify::PlaylistMeta.write(
        playlist_dir,
        url: 'https://open.spotify.com/playlist/abc123',
        source: :spotify,
        name: 'Deep House'
      )

      saved = JSON.parse(File.read(File.join(playlist_dir, '.exportify.json')))

      assert_equal 'https://open.spotify.com/playlist/abc123', saved['url']
      assert_equal 'spotify', saved['source']
      assert_equal 'Deep House', saved['name']
      assert_match(/\A\d{4}-\d{2}-\d{2}T/, saved['synced_at'])
    end
  end

  def test_read_returns_saved_metadata
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Deep House')
      FileUtils.mkdir_p(playlist_dir)

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::PlaylistMeta.write(
          playlist_dir,
          url: 'https://open.spotify.com/playlist/abc123',
          source: :spotify,
          name: 'Deep House'
        )

        meta = Exportify::PlaylistMeta.read('Deep House')

        assert_equal 'https://open.spotify.com/playlist/abc123', meta[:url]
        assert_equal 'spotify', meta[:source]
      end
    end
  end

  def test_read_returns_nil_when_file_missing
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Deep House'))

      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::PlaylistMeta.read('Deep House')
      end
    end
  end

  def test_read_returns_nil_for_corrupted_json
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Deep House')
      FileUtils.mkdir_p(playlist_dir)
      File.write(File.join(playlist_dir, '.exportify.json'), '{ not json')

      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::PlaylistMeta.read('Deep House')
      end
    end
  end

  def test_read_returns_nil_for_unknown_playlist
    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::PlaylistMeta.read('Nao Existe')
      end
    end
  end
end

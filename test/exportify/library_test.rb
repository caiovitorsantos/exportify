# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

class LibraryTest < Minitest::Test
  def test_playlists_returns_name_and_track_count_sorted
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Trap Brasil'))
      FileUtils.mkdir_p(File.join(dir, 'Rock dos Anos 80'))
      FileUtils.touch(File.join(dir, 'Rock dos Anos 80', 'Queen - Bohemian Rhapsody.mp3'))
      FileUtils.touch(File.join(dir, 'Rock dos Anos 80', 'David Bowie - Heroes.mp3'))
      FileUtils.touch(File.join(dir, 'Trap Brasil', 'Matuê - Kenny G.mp3'))

      Exportify::Config.stub(:output_dir, dir) do
        result = Exportify::Library.playlists

        assert_equal(
          [
            { name: 'Rock dos Anos 80', track_count: 2 },
            { name: 'Trap Brasil', track_count: 1 }
          ],
          result
        )
      end
    end
  end

  def test_playlists_ignores_non_mp3_files
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Playlist'))
      FileUtils.touch(File.join(dir, 'Playlist', 'cover.jpg'))

      Exportify::Config.stub(:output_dir, dir) do
        assert_equal [{ name: 'Playlist', track_count: 0 }], Exportify::Library.playlists
      end
    end
  end

  def test_playlists_returns_empty_array_when_output_dir_missing
    Exportify::Config.stub(:output_dir, '/tmp/exportify-test-does-not-exist') do
      assert_equal [], Exportify::Library.playlists
    end
  end
end

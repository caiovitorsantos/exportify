# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'ostruct'

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

  def test_read_tags_returns_parsed_json_on_success
    json = '{"title":"Bohemian Rhapsody","all_artists":"Queen","artist":"Queen",' \
           '"album":"A Night at the Opera","year":"1975","track_number":"1",' \
           '"genre":"Rock","duration_seconds":354.5}'
    status = OpenStruct.new(success?: true)

    Open3.stub(:capture3, [json, '', status]) do
      tags = Exportify::Library.read_tags('/tmp/song.mp3')

      assert_equal 'Bohemian Rhapsody', tags[:title]
      assert_in_delta 354.5, tags[:duration_seconds]
    end
  end

  def test_read_tags_returns_nil_when_python_fails
    status = OpenStruct.new(success?: false)

    Open3.stub(:capture3, ['', 'error', status]) do
      assert_nil Exportify::Library.read_tags('/tmp/song.mp3')
    end
  end

  def test_read_tags_returns_nil_on_invalid_json
    status = OpenStruct.new(success?: true)

    Open3.stub(:capture3, ['not json', '', status]) do
      assert_nil Exportify::Library.read_tags('/tmp/song.mp3')
    end
  end

  def test_read_tags_script_includes_filepath
    script = nil
    status = OpenStruct.new(success?: true)

    Open3.stub(:capture3, lambda { |_cmd, _flag, s|
      script = s
      ['{}', '', status]
    }) do
      Exportify::Library.read_tags('/tmp/my song.mp3')
    end

    assert_includes script, '/tmp/my song.mp3'
  end
end

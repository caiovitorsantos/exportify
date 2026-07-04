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

  def test_tracks_returns_nil_for_unknown_playlist
    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.tracks('Does Not Exist')
      end
    end
  end

  def test_tracks_lists_files_with_metadata
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'Queen - Bohemian Rhapsody.mp3'))

      tags = { title: 'Bohemian Rhapsody', artist: 'Queen', track_number: '1' }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, tags) do
          result = Exportify::Library.tracks('Rock')

          assert_equal(
            [{ filename: 'Queen - Bohemian Rhapsody.mp3', title: 'Bohemian Rhapsody', artist: 'Queen' }],
            result
          )
        end
      end
    end
  end

  def test_tracks_falls_back_to_filename_when_tags_missing
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'David Bowie - Heroes.mp3'))

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, nil) do
          result = Exportify::Library.tracks('Rock')

          assert_equal(
            [{ filename: 'David Bowie - Heroes.mp3', title: 'Heroes', artist: 'David Bowie' }],
            result
          )
        end
      end
    end
  end

  def test_tracks_sorted_by_track_number_with_missing_last
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'B - Second.mp3'))
      FileUtils.touch(File.join(playlist_dir, 'A - First.mp3'))
      FileUtils.touch(File.join(playlist_dir, 'Z - NoNumber.mp3'))

      by_filename = {
        'B - Second.mp3' => { track_number: '2' },
        'A - First.mp3' => { track_number: '1' },
        'Z - NoNumber.mp3' => {}
      }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, ->(filepath) { by_filename[File.basename(filepath)] }) do
          result = Exportify::Library.tracks('Rock')

          assert_equal(
            ['A - First.mp3', 'B - Second.mp3', 'Z - NoNumber.mp3'],
            result.map { |t| t[:filename] }
          )
        end
      end
    end
  end

  def test_track_returns_nil_for_unknown_playlist
    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.track('Unknown', 'song.mp3')
      end
    end
  end

  def test_track_returns_nil_for_unknown_file
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Rock'))

      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.track('Rock', 'missing.mp3')
      end
    end
  end

  def test_track_returns_full_metadata
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      filepath = File.join(playlist_dir, 'Queen - Bohemian Rhapsody.mp3')
      File.write(filepath, 'x' * 2048)

      tags = {
        title: 'Bohemian Rhapsody', artist: 'Queen', all_artists: 'Queen',
        album: 'A Night at the Opera', year: '1975', track_number: '1',
        genre: 'Rock', duration_seconds: 354.5
      }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, tags) do
          result = Exportify::Library.track('Rock', 'Queen - Bohemian Rhapsody.mp3')

          assert_equal 'Bohemian Rhapsody', result[:title]
          assert_equal 'A Night at the Opera', result[:album]
          assert_in_delta 354.5, result[:duration_seconds]
          assert_equal 2048, result[:file_size_bytes]
        end
      end
    end
  end

  def test_track_falls_back_when_tags_unavailable
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      filepath = File.join(playlist_dir, 'David Bowie - Heroes.mp3')
      FileUtils.touch(filepath)

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, nil) do
          result = Exportify::Library.track('Rock', 'David Bowie - Heroes.mp3')

          assert_equal 'Heroes', result[:title]
          assert_equal 'David Bowie', result[:artist]
          assert_nil result[:album]
          assert_nil result[:duration_seconds]
          assert_equal 0, result[:file_size_bytes]
        end
      end
    end
  end
end

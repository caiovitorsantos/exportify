# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'ostruct'
require 'open3'

class YouTubeTest < Minitest::Test
  def test_split_title_separates_artist_and_name
    artist, name = Exportify::YouTube.split_title('Rick Astley - Never Gonna Give You Up', 'Rick Astley Channel')

    assert_equal 'Rick Astley', artist
    assert_equal 'Never Gonna Give You Up', name
  end

  def test_split_title_falls_back_to_uploader_without_dash_pattern
    artist, name = Exportify::YouTube.split_title('Official Music Video', 'Some Channel')

    assert_equal 'Some Channel', artist
    assert_equal 'Official Music Video', name
  end

  def test_split_title_strips_whitespace_around_dash
    artist, name = Exportify::YouTube.split_title('Artist   -   Song Name', 'Fallback')

    assert_equal 'Artist', artist
    assert_equal 'Song Name', name
  end

  def stub_yt_dlp(stdout:, stderr: '', success: true, &)
    status = OpenStruct.new(success?: success)
    Open3.stub(:capture3, [stdout, stderr, status], &)
  end

  def test_fetch_playlist_returns_name_and_tracks
    body = {
      'title' => 'Minha Playlist',
      'entries' => [
        { 'id' => 'vid1', 'title' => 'Rick Astley - Never Gonna Give You Up', 'uploader' => 'Rick Astley' },
        { 'id' => 'vid2', 'title' => 'Video Sem Padrão', 'uploader' => 'Canal Qualquer' }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      result = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')

      assert_equal 'Minha Playlist', result[:name]
      assert_equal 2, result[:tracks].size
    end
  end

  def test_fetch_playlist_normalizes_first_track_fields
    body = {
      'title' => 'Minha Playlist',
      'entries' => [
        { 'id' => 'vid1', 'title' => 'Rick Astley - Never Gonna Give You Up', 'uploader' => 'Rick Astley' }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      track = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')[:tracks].first

      expected = {
        artist: 'Rick Astley',
        all_artists: 'Rick Astley',
        name: 'Never Gonna Give You Up',
        raw_name: 'Rick Astley - Never Gonna Give You Up',
        album: 'Minha Playlist',
        year: '',
        track_number: 1,
        genre: '',
        video_id: 'vid1'
      }

      assert_equal expected, track
    end
  end

  def test_fetch_playlist_assigns_sequential_track_numbers
    body = {
      'title' => 'Minha Playlist',
      'entries' => [
        { 'id' => 'vid1', 'title' => 'A - B', 'uploader' => 'X' },
        { 'id' => 'vid2', 'title' => 'C - D', 'uploader' => 'Y' }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      tracks = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')[:tracks]

      assert_equal 1, tracks[0][:track_number]
      assert_equal 2, tracks[1][:track_number]
    end
  end

  def test_fetch_playlist_leaves_year_and_genre_blank
    body = {
      'title' => 'Minha Playlist',
      'entries' => [{ 'id' => 'vid1', 'title' => 'A - B', 'uploader' => 'X' }]
    }.to_json

    stub_yt_dlp(stdout: body) do
      track = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')[:tracks].first

      assert_equal '', track[:year]
      assert_equal '', track[:genre]
    end
  end

  def test_fetch_playlist_aborts_when_yt_dlp_fails
    stub_yt_dlp(stdout: '', stderr: 'ERROR: Private video', success: false) do
      assert_output(nil, /Private video/) do
        assert_raises(SystemExit) { Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123') }
      end
    end
  end

  def test_fetch_playlist_aborts_when_playlist_is_empty
    body = { 'title' => 'Vazia', 'entries' => [] }.to_json

    stub_yt_dlp(stdout: body) do
      assert_output(nil, /vazia ou inacessível/) do
        assert_raises(SystemExit) { Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123') }
      end
    end
  end
end

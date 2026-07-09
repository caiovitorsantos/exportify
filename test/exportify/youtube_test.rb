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

  def test_fetch_playlist_skips_nil_entries
    body = {
      'title' => 'Minha Playlist',
      'entries' => [
        { 'id' => 'vid1', 'title' => 'Rick Astley - Never Gonna Give You Up', 'uploader' => 'Rick Astley' },
        nil,
        { 'id' => 'vid2', 'title' => 'Video Sem Padrão', 'uploader' => 'Canal Qualquer' }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      result = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')

      assert_equal 2, result[:tracks].size
      assert_equal 'vid1', result[:tracks][0][:video_id]
      assert_equal 'vid2', result[:tracks][1][:video_id]
    end
  end

  def test_fetch_playlist_uses_structured_metadata_when_present
    body = {
      'title' => 'Minha Playlist',
      'entries' => [
        {
          'id' => 'vid1',
          'title' => 'Just Dance',
          'uploader' => 'Lady Gaga',
          'artist' => "Lady Gaga, Colby O'Donis",
          'track' => 'Just Dance',
          'album' => 'The Fame',
          'release_year' => 2008,
          'playlist_index' => 1
        }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      track = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')[:tracks].first

      expected = {
        artist: 'Lady Gaga',
        all_artists: "Lady Gaga, Colby O'Donis",
        name: 'Just Dance',
        raw_name: 'Just Dance',
        album: 'The Fame',
        year: '2008',
        track_number: 1,
        genre: '',
        video_id: 'vid1'
      }

      assert_equal expected, track
    end
  end

  def test_fetch_playlist_does_not_use_flat_playlist_flag
    body = {
      'title' => 'Minha Playlist',
      'entries' => [{ 'id' => 'vid1', 'title' => 'A - B', 'uploader' => 'X' }]
    }.to_json
    received_args = nil

    Open3.stub(
      :capture3,
      lambda { |*args|
        received_args = args
        [body, '', OpenStruct.new(success?: true)]
      }
    ) do
      Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')
    end

    refute_includes received_args, '--flat-playlist'
  end

  def test_fetch_playlist_uses_cookies_from_browser_when_given
    body = {
      'title' => 'Minha Playlist',
      'entries' => [{ 'id' => 'vid1', 'title' => 'Rick Astley - Never Gonna Give You Up', 'uploader' => 'Rick Astley' }]
    }.to_json
    status = OpenStruct.new(success?: true)
    received_args = nil

    Open3.stub(
      :capture3,
      lambda { |*args|
        received_args = args
        [body, '', status]
      }
    ) do
      Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123', browser: 'chrome')
    end

    assert_includes received_args, '--cookies-from-browser'
    assert_includes received_args, 'chrome'
  end

  def test_fetch_video_returns_chaptered_tracks_when_chapters_present
    body = {
      'id' => 'vid1',
      'title' => 'Slow Touch Mix',
      'uploader' => 'ChartHistories',
      'chapters' => [
        { 'title' => 'Aftersoft', 'start_time' => 0.0, 'end_time' => 171.0 },
        { 'title' => 'Cloud Nine Room', 'start_time' => 171.0, 'end_time' => 372.0 }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      result = Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1')

      assert_equal 'Slow Touch Mix', result[:name]
      assert result[:chaptered]
      assert_equal 2, result[:tracks].size
    end
  end

  def test_fetch_video_builds_chapter_track_fields
    body = {
      'id' => 'vid1',
      'title' => 'Slow Touch Mix',
      'uploader' => 'ChartHistories',
      'chapters' => [
        { 'title' => 'Aftersoft', 'start_time' => 0.0, 'end_time' => 171.0 }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      track = Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1')[:tracks].first

      expected = {
        artist: 'Unknown Artist',
        all_artists: 'Unknown Artist',
        name: 'Aftersoft',
        raw_name: 'Aftersoft',
        album: 'Slow Touch Mix',
        year: '',
        track_number: 1,
        genre: '',
        video_id: 'vid1',
        chapter_start: 0.0,
        chapter_end: 171.0
      }

      assert_equal expected, track
    end
  end

  def test_fetch_video_chapter_track_does_not_use_channel_as_artist_fallback
    body = {
      'id' => 'vid1',
      'title' => 'Neo-Soul Mix',
      'uploader' => 'Nia',
      'channel' => 'Nia',
      'chapters' => [
        { 'title' => "Didn't Cha Know", 'start_time' => 0.0, 'end_time' => 195.0 }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      track = Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1')[:tracks].first

      refute_equal 'Nia', track[:artist]
      assert_equal 'Unknown Artist', track[:artist]
    end
  end

  def test_fetch_video_returns_single_track_without_chapters
    body = {
      'id' => 'vid1',
      'title' => 'Rick Astley - Never Gonna Give You Up',
      'uploader' => 'Rick Astley',
      'chapters' => nil
    }.to_json

    stub_yt_dlp(stdout: body) do
      result = Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1')

      refute result[:chaptered]
      assert_equal 1, result[:tracks].size
      assert_equal 'Rick Astley', result[:tracks].first[:artist]
      assert_equal 'Never Gonna Give You Up', result[:tracks].first[:name]
    end
  end

  def test_fetch_video_aborts_when_yt_dlp_fails
    stub_yt_dlp(stdout: '', stderr: 'ERROR: Video unavailable', success: false) do
      assert_output(nil, /Video unavailable/) do
        assert_raises(SystemExit) { Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1') }
      end
    end
  end

  def test_fetch_playlist_rejects_url_without_http_scheme
    assert_raises(SystemExit) { Exportify::YouTube.fetch_playlist('--exec=touch /tmp/pwned') }
  end

  def test_fetch_playlist_rejects_browser_starting_with_dash
    assert_raises(SystemExit) do
      Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123', browser: '--exec=evil')
    end
  end

  def test_fetch_playlist_inserts_separator_before_url
    body = { 'title' => 'P', 'entries' => [] }.to_json
    received_args = nil

    Open3.stub(
      :capture3,
      lambda { |*args|
        received_args = args
        [body, '', OpenStruct.new(success?: true)]
      }
    ) do
      Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')
    rescue SystemExit
      nil
    end

    dash_dash_index = received_args.index('--')
    url_index = received_args.index('https://www.youtube.com/playlist?list=PL123')

    assert dash_dash_index, 'esperava um separador -- no comando'
    assert url_index, 'esperava a URL no comando'
    assert_operator dash_dash_index, :<, url_index, '-- deve vir antes da URL'
  end

  def test_fetch_video_rejects_url_without_http_scheme
    assert_raises(SystemExit) { Exportify::YouTube.fetch_video('--exec=touch /tmp/pwned') }
  end

  def test_fetch_video_rejects_browser_starting_with_dash
    assert_raises(SystemExit) do
      Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1', browser: '--exec=evil')
    end
  end
end

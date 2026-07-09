# frozen_string_literal: true

require 'test_helper'
require 'exportify/web_server'
require 'net/http'
require 'tmpdir'
require 'fileutils'
require 'json'

class WebServerTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def with_server
    Exportify::Config.stub(:output_dir, @dir) do
      server = Exportify::WebServer.build_server(0)
      thread = Thread.new { server.start }

      yield server.config[:Port]
    ensure
      server.shutdown
      thread&.join
    end
  end

  def test_get_root_lists_playlists
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_equal '200', response.code
      assert_includes response.body, 'Rock'
    end
  end

  def test_get_root_renders_sidebar_and_topbar
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_includes response.body, 'class="sidebar"'
      assert_includes response.body, 'id="search-input"'
    end
  end

  def test_get_root_renders_generated_cover_and_search_text
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_includes response.body, 'class="cover cover--card"'
      assert_includes response.body, 'data-search-text="Rock"'
    end
  end

  def test_get_root_shows_empty_state_when_no_playlists
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_equal '200', response.code
      assert_includes response.body, 'exportify'
    end
  end

  def test_get_unknown_path_returns404
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/does-not-exist"))

      assert_equal '404', response.code
    end
  end

  def test_get_playlist_lists_tracks
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock"))

      assert_equal '200', response.code
      assert_includes response.body, 'Bohemian Rhapsody'
    end
  end

  def test_get_playlist_renders_chart_list_with_numbered_index
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock"))

      assert_includes response.body, 'class="chart-list"'
      assert_includes response.body, 'chart-list__index'
    end
  end

  def test_get_unknown_playlist_returns404
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Unknown"))

      assert_equal '404', response.code
    end
  end

  def test_format_duration_formats_minutes_and_seconds
    assert_equal '5:54', Exportify::WebServer.format_duration(354.4)
  end

  def test_format_duration_returns_dash_for_nil
    assert_equal '—', Exportify::WebServer.format_duration(nil)
  end

  def test_format_file_size_formats_kilobytes
    assert_equal '2.0 KB', Exportify::WebServer.format_file_size(2048)
  end

  def test_format_file_size_formats_megabytes
    assert_equal '2.0 MB', Exportify::WebServer.format_file_size(2 * 1_048_576)
  end

  def test_format_file_size_returns_dash_for_nil
    assert_equal '—', Exportify::WebServer.format_file_size(nil)
  end

  def test_get_track_shows_details_and_player
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      url = URI("http://127.0.0.1:#{port}/playlists/Rock/faixas/Queen%20-%20Bohemian%20Rhapsody.mp3")
      response = Net::HTTP.get_response(url)

      assert_equal '200', response.code
      assert_includes response.body, 'Bohemian Rhapsody'
      assert_includes response.body, '<audio'
    end
  end

  def test_get_track_renders_large_cover
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      url = URI("http://127.0.0.1:#{port}/playlists/Rock/faixas/Queen%20-%20Bohemian%20Rhapsody.mp3")
      response = Net::HTTP.get_response(url)

      assert_includes response.body, 'cover--lg'
    end
  end

  def test_get_unknown_track_returns_404 # rubocop:disable Naming/VariableNumber
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock/faixas/missing.mp3"))

      assert_equal '404', response.code
    end
  end

  def test_get_style_css_is_served
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/assets/style.css"))

      assert_equal '200', response.code
    end
  end

  def test_get_app_js_is_served
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/assets/app.js"))

      assert_equal '200', response.code
    end
  end

  def test_post_playlists_creates_job_for_valid_url
    with_server do |port|
      Exportify::Jobs.stub(:start, ->(_cmd) { 'job123' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists")
        response = Net::HTTP.post_form(uri, 'url' => 'https://open.spotify.com/playlist/abc123')

        assert_equal '202', response.code
        assert_equal({ 'job_id' => 'job123' }, JSON.parse(response.body))
      end
    end
  end

  def test_post_playlists_rejects_invalid_url
    with_server do |port|
      uri = URI("http://127.0.0.1:#{port}/playlists")
      response = Net::HTTP.post_form(uri, 'url' => 'https://example.com/whatever')

      assert_equal '400', response.code
      assert JSON.parse(response.body)['error']
    end
  end

  def test_post_playlists_rejects_url_starting_with_dash
    with_server do |port|
      Exportify::Jobs.stub(:start, ->(_cmd) { flunk 'Jobs.start should not have been called' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists")
        response = Net::HTTP.post_form(uri, 'url' => '-fopen.spotify.com/playlist/xyz')

        assert_equal '400', response.code
        assert JSON.parse(response.body)['error']
      end
    end
  end

  def test_post_playlists_threads_url_and_browser_into_command
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, lambda { |cmd|
        received_cmd = cmd
        'job123'
      }) do
        uri = URI("http://127.0.0.1:#{port}/playlists")
        Net::HTTP.post_form(uri, 'url' => 'https://open.spotify.com/playlist/abc123', 'browser' => 'chrome')
      end
    end

    assert_includes received_cmd, 'https://open.spotify.com/playlist/abc123'
    assert_includes received_cmd, '--browser=chrome'
  end

  def test_post_playlists_omits_browser_flag_when_blank
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, lambda { |cmd|
        received_cmd = cmd
        'job123'
      }) do
        uri = URI("http://127.0.0.1:#{port}/playlists")
        Net::HTTP.post_form(uri, 'url' => 'https://open.spotify.com/playlist/abc123')
      end
    end

    refute(received_cmd.any? { |arg| arg.start_with?('--browser') })
  end

  def test_get_job_status_returns_json
    with_server do |port|
      Exportify::Jobs.stub(:status, ->(id) { { status: 'done', log: ['ok'] } if id == 'job123' }) do
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/jobs/job123"))

        assert_equal '200', response.code
        assert_equal({ 'status' => 'done', 'log' => ['ok'] }, JSON.parse(response.body))
      end
    end
  end

  def test_get_unknown_job_returns_404 # rubocop:disable Naming/VariableNumber
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/jobs/does-not-exist"))

      assert_equal '404', response.code
    end
  end

  def test_post_retag_uses_stored_source_url_and_browser
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    File.write(
      File.join(@dir, 'Rock', '.exportify.json'),
      '{"url":"https://open.spotify.com/playlist/abc123","browser":"chrome"}'
    )
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, lambda { |cmd|
        received_cmd = cmd
        'job123'
      }) do
        uri = URI("http://127.0.0.1:#{port}/playlists/Rock/retag")
        response = Net::HTTP.post_form(uri, {})

        assert_equal '202', response.code
      end
    end

    assert_includes received_cmd, 'https://open.spotify.com/playlist/abc123'
    assert_includes received_cmd, '--retag'
    assert_includes received_cmd, '--browser=chrome'
  end

  def test_post_sync_uses_stored_source_url
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    File.write(File.join(@dir, 'Rock', '.exportify.json'), '{"url":"https://open.spotify.com/playlist/abc123"}')
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, lambda { |cmd|
        received_cmd = cmd
        'job123'
      }) do
        uri = URI("http://127.0.0.1:#{port}/playlists/Rock/sync")
        Net::HTTP.post_form(uri, {})
      end
    end

    assert_includes received_cmd, '--sync'
    refute_includes received_cmd, '--retag'
  end

  def test_post_retag_without_stored_source_accepts_url_param
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, lambda { |cmd|
        received_cmd = cmd
        'job123'
      }) do
        uri = URI("http://127.0.0.1:#{port}/playlists/Rock/retag")
        response = Net::HTTP.post_form(uri, 'url' => 'https://open.spotify.com/playlist/xyz')

        assert_equal '202', response.code
      end
    end

    assert_includes received_cmd, 'https://open.spotify.com/playlist/xyz'
  end

  def test_post_retag_without_stored_source_rejects_url_starting_with_dash
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))

    with_server do |port|
      Exportify::Jobs.stub(:start, ->(_cmd) { flunk 'Jobs.start should not have been called' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists/Rock/retag")
        response = Net::HTTP.post_form(uri, 'url' => '-x')

        assert_equal '400', response.code
        assert JSON.parse(response.body)['error']
      end
    end
  end

  def test_post_retag_without_stored_source_or_url_param_returns422
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))

    with_server do |port|
      uri = URI("http://127.0.0.1:#{port}/playlists/Rock/retag")
      response = Net::HTTP.post_form(uri, {})

      assert_equal '422', response.code
    end
  end

  def test_post_retag_unknown_playlist_returns_404 # rubocop:disable Naming/VariableNumber
    with_server do |port|
      uri = URI("http://127.0.0.1:#{port}/playlists/Unknown/retag")
      response = Net::HTTP.post_form(uri, {})

      assert_equal '404', response.code
    end
  end

  def test_get_playlist_exposes_source_presence_for_view
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    File.write(File.join(@dir, 'Rock', '.exportify.json'), '{"url":"https://open.spotify.com/playlist/abc123"}')

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock"))

      assert_includes response.body, 'data-has-source="1"'
    end
  end
end

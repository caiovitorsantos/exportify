# frozen_string_literal: true

require 'test_helper'
require 'exportify/web_server'
require 'net/http'
require 'tmpdir'
require 'fileutils'

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
end

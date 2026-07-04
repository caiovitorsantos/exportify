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
end

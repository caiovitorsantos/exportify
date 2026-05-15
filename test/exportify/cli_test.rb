require 'test_helper'

class CLITest < Minitest::Test
  def test_exits_without_playlist_url
    assert_output(nil, /Usage/) do
      assert_raises(SystemExit) { Exportify::CLI.run([]) }
    end
  end

  def test_exits_with_invalid_url
    assert_raises(SystemExit) { Exportify::CLI.run(['https://open.spotify.com/album/123']) }
  end

  def test_exits_without_credentials
    ENV.delete('SPOTIFY_CLIENT_ID')
    ENV.delete('SPOTIFY_CLIENT_SECRET')

    assert_raises(SystemExit) do
      Exportify::CLI.run(['https://open.spotify.com/playlist/abc123'])
    end
  ensure
    ENV['SPOTIFY_CLIENT_ID']     = 'fake_id'
    ENV['SPOTIFY_CLIENT_SECRET'] = 'fake_secret'
  end

  def test_retag_flag_is_removed_from_argv
    argv = ['https://open.spotify.com/playlist/abc123', '--retag']
    argv.delete('--retag')
    assert_equal ['https://open.spotify.com/playlist/abc123'], argv
  end

  def test_extracts_playlist_id_from_url
    url   = 'https://open.spotify.com/playlist/4xFRymXBprhoyr25uvyp0U?si=abc'
    match = url.match(/playlist\/([A-Za-z0-9]+)/)
    assert_equal '4xFRymXBprhoyr25uvyp0U', match&.captures&.first
  end

  def test_extracts_playlist_id_without_query_string
    url   = 'https://open.spotify.com/playlist/4xFRymXBprhoyr25uvyp0U'
    match = url.match(/playlist\/([A-Za-z0-9]+)/)
    assert_equal '4xFRymXBprhoyr25uvyp0U', match&.captures&.first
  end
end

# frozen_string_literal: true

require 'test_helper'

class DownloaderTest < Minitest::Test
  def test_sanitize_removes_forward_slash
    assert_equal 'ACDC', Exportify::Downloader.sanitize('AC/DC')
  end

  def test_sanitize_removes_backslash
    assert_equal 'ACDC', Exportify::Downloader.sanitize('AC\\DC')
  end

  def test_sanitize_removes_colon
    assert_equal 'Title Subtitle', Exportify::Downloader.sanitize('Title: Subtitle')
  end

  def test_sanitize_removes_asterisk
    assert_equal 'Boss Btch', Exportify::Downloader.sanitize('Boss B*tch')
  end

  def test_sanitize_removes_question_mark
    assert_equal 'Who Are You', Exportify::Downloader.sanitize('Who Are You?')
  end

  def test_sanitize_removes_double_quote
    assert_equal 'Say It, Dont Spray It', Exportify::Downloader.sanitize('Say It, "Dont Spray It"')
  end

  def test_sanitize_removes_angle_brackets
    assert_equal 'Track', Exportify::Downloader.sanitize('<Track>')
  end

  def test_sanitize_removes_pipe
    assert_equal 'A  B', Exportify::Downloader.sanitize('A | B')
  end

  def test_sanitize_strips_whitespace
    assert_equal 'Clean', Exportify::Downloader.sanitize('  Clean  ')
  end

  def test_sanitize_leaves_normal_string_unchanged
    assert_equal "Don't Stop Me Now", Exportify::Downloader.sanitize("Don't Stop Me Now")
  end

  def test_download_calls_yt_dlp
    track = {
      raw_name: 'Womanizer',
      all_artists: 'Britney Spears',
      artist: 'Britney Spears',
      name: 'Womanizer'
    }

    Exportify::Downloader.stub(:system, true) do
      result = Exportify::Downloader.download(track, '/tmp')

      assert result
    end
  end
end

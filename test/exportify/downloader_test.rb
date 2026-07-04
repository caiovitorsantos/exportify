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

  def test_download_with_video_id_uses_direct_url
    track = {
      video_id: 'dQw4w9WgXcQ',
      artist: 'Rick Astley',
      all_artists: 'Rick Astley',
      name: 'Never Gonna Give You Up',
      raw_name: 'Never Gonna Give You Up'
    }
    received_args = nil

    Exportify::Downloader.stub(
      :system,
      lambda { |*args|
        received_args = args
        true
      }
    ) do
      Exportify::Downloader.download(track, '/tmp')
    end

    assert_includes received_args, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
    refute(received_args.any? { |a| a.to_s.start_with?('ytsearch1:') })
  end

  def test_download_without_video_id_uses_search
    track = {
      artist: 'Britney Spears',
      all_artists: 'Britney Spears',
      name: 'Womanizer',
      raw_name: 'Womanizer'
    }
    received_args = nil

    Exportify::Downloader.stub(
      :system,
      lambda { |*args|
        received_args = args
        true
      }
    ) do
      Exportify::Downloader.download(track, '/tmp')
    end

    assert(received_args.any? { |a| a.to_s.start_with?('ytsearch1:') })
  end
end

# frozen_string_literal: true

require 'test_helper'

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
end

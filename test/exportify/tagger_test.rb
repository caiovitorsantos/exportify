# frozen_string_literal: true

require 'test_helper'

class TaggerTest < Minitest::Test
  TRACK = {
    raw_name: 'WAP (feat. Megan Thee Stallion)',
    all_artists: 'Cardi B, Megan Thee Stallion',
    artist: 'Cardi B',
    album: 'WAP',
    year: '2020',
    track_number: 1,
    genre: 'hip hop'
  }.freeze

  def test_tag_calls_python3
    called_with = nil
    Exportify::Tagger.stub(:system, lambda { |cmd, *_args|
      called_with = cmd
      true
    }) do
      Exportify::Tagger.tag('/tmp/test.mp3', TRACK)
    end

    assert_equal 'python3', called_with
  end

  def test_tag_python_script_includes_title
    script = nil
    Exportify::Tagger.stub(:system, lambda { |_cmd, _flag, s, **|
      script = s
      true
    }) do
      Exportify::Tagger.tag('/tmp/test.mp3', TRACK)
    end

    assert_includes script, 'WAP (feat. Megan Thee Stallion)'
  end

  def test_tag_python_script_includes_artist
    script = nil
    Exportify::Tagger.stub(:system, lambda { |_cmd, _flag, s, **|
      script = s
      true
    }) do
      Exportify::Tagger.tag('/tmp/test.mp3', TRACK)
    end

    assert_includes script, 'Cardi B, Megan Thee Stallion'
  end

  def test_tag_python_script_includes_album
    script = nil
    Exportify::Tagger.stub(:system, lambda { |_cmd, _flag, s, **|
      script = s
      true
    }) do
      Exportify::Tagger.tag('/tmp/test.mp3', TRACK)
    end

    assert_includes script, 'WAP'
  end

  def test_tag_python_script_includes_year
    script = nil
    Exportify::Tagger.stub(:system, lambda { |_cmd, _flag, s, **|
      script = s
      true
    }) do
      Exportify::Tagger.tag('/tmp/test.mp3', TRACK)
    end

    assert_includes script, '2020'
  end

  def test_tag_python_script_includes_filepath
    script = nil
    Exportify::Tagger.stub(:system, lambda { |_cmd, _flag, s, **|
      script = s
      true
    }) do
      Exportify::Tagger.tag('/tmp/test.mp3', TRACK)
    end

    assert_includes script, '/tmp/test.mp3'
  end

  def test_tag_python_script_includes_genre
    script = nil
    Exportify::Tagger.stub(:system, lambda { |_cmd, _flag, s, **|
      script = s
      true
    }) do
      Exportify::Tagger.tag('/tmp/test.mp3', TRACK)
    end

    assert_includes script, 'hip hop'
  end
end

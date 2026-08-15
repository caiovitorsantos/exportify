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

  def test_tag_analysis_writes_bpm_and_key
    script = nil
    Exportify::Tagger.stub(:system, lambda { |_cmd, _flag, s, **|
      script = s
      true
    }) do
      Exportify::Tagger.tag_analysis('/tmp/test.mp3', bpm: 128, key: 'Am')
    end

    assert_includes script, 'TBPM'
    assert_includes script, '128'
    assert_includes script, 'TKEY'
    assert_includes script, 'Am'
  end

  def test_tag_analysis_writes_only_bpm_when_key_missing
    script = nil
    Exportify::Tagger.stub(:system, lambda { |_cmd, _flag, s, **|
      script = s
      true
    }) do
      Exportify::Tagger.tag_analysis('/tmp/test.mp3', bpm: 128, key: nil)
    end

    assert_includes script, 'TBPM'
    refute_includes script, 'TKEY'
  end

  def test_tag_analysis_is_noop_when_both_nil
    called = false
    Exportify::Tagger.stub(:system, ->(*_args) { called = true }) do
      result = Exportify::Tagger.tag_analysis('/tmp/test.mp3', bpm: nil, key: nil)

      assert_nil result
    end

    refute called
  end
end

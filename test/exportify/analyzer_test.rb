# frozen_string_literal: true

require 'test_helper'
require 'open3'

class AnalyzerTest < Minitest::Test
  def ok_status
    status = Object.new
    status.define_singleton_method(:success?) { true }
    status
  end

  def fail_status
    status = Object.new
    status.define_singleton_method(:success?) { false }
    status
  end

  def test_detect_bpm_from_beat_timestamps
    # beats a cada 0.5s -> 120 BPM
    Open3.stub(:capture3, ["0.0\n0.5\n1.0\n1.5\n2.0\n", '', ok_status]) do
      assert_equal 120, Exportify::Analyzer.detect_bpm('/tmp/x.mp3')
    end
  end

  def test_detect_bpm_rounds_to_two_decimal_places
    # beats a cada 0.47s -> 60/0.47 = 127.659574... -> 127.66 BPM
    Open3.stub(:capture3, ["0.00\n0.47\n0.94\n1.41\n1.88\n", '', ok_status]) do
      assert_in_delta 127.66, Exportify::Analyzer.detect_bpm('/tmp/x.mp3')
    end
  end

  def test_detect_bpm_returns_nil_with_too_few_beats
    Open3.stub(:capture3, ["0.5\n", '', ok_status]) do
      assert_nil Exportify::Analyzer.detect_bpm('/tmp/x.mp3')
    end
  end

  def test_detect_bpm_returns_nil_on_failure
    Open3.stub(:capture3, ['', 'boom', fail_status]) do
      assert_nil Exportify::Analyzer.detect_bpm('/tmp/x.mp3')
    end
  end

  def test_detect_bpm_returns_nil_when_binary_missing
    Open3.stub(:capture3, ->(*_args) { raise Errno::ENOENT }) do
      assert_nil Exportify::Analyzer.detect_bpm('/tmp/x.mp3')
    end
  end

  def test_detect_key_returns_nil_when_binary_missing
    Open3.stub(:capture3, ->(*_args) { raise Errno::ENOENT }) do
      assert_nil Exportify::Analyzer.detect_key('/tmp/x.mp3')
    end
  end

  def test_detect_key_returns_trimmed_key
    Open3.stub(:capture3, ["Am\n", '', ok_status]) do
      assert_equal 'Am', Exportify::Analyzer.detect_key('/tmp/x.mp3')
    end
  end

  def test_detect_key_returns_nil_on_failure
    Open3.stub(:capture3, ['', 'boom', fail_status]) do
      assert_nil Exportify::Analyzer.detect_key('/tmp/x.mp3')
    end
  end

  def test_detect_key_returns_nil_when_empty
    Open3.stub(:capture3, ["\n", '', ok_status]) do
      assert_nil Exportify::Analyzer.detect_key('/tmp/x.mp3')
    end
  end

  def test_analyze_combines_bpm_and_key
    Exportify::Analyzer.stub(:detect_bpm, 128) do
      Exportify::Analyzer.stub(:detect_key, 'Am') do
        assert_equal({ bpm: 128, key: 'Am' }, Exportify::Analyzer.analyze('/tmp/x.mp3'))
      end
    end
  end

  def test_analyze_returns_nil_when_both_fail
    Exportify::Analyzer.stub(:detect_bpm, nil) do
      Exportify::Analyzer.stub(:detect_key, nil) do
        assert_nil Exportify::Analyzer.analyze('/tmp/x.mp3')
      end
    end
  end

  def test_analyze_keeps_partial_result
    Exportify::Analyzer.stub(:detect_bpm, 100) do
      Exportify::Analyzer.stub(:detect_key, nil) do
        assert_equal({ bpm: 100, key: nil }, Exportify::Analyzer.analyze('/tmp/x.mp3'))
      end
    end
  end

  # Roda de Camelot: uma amostra representativa dos dois lados + apelidos
  CAMELOT_CASES = {
    'B' => '1B', 'Gb' => '2B', 'F#' => '2B', 'C' => '8B', 'A' => '11B',
    'Abm' => '1A', 'G#m' => '1A', 'Am' => '8A', 'F#m' => '11A', 'Dbm' => '12A'
  }.freeze

  def test_camelot_maps_known_keys
    CAMELOT_CASES.each do |key, code|
      assert_equal code, Exportify::Analyzer.camelot(key), "#{key} deveria virar #{code}"
    end
  end

  def test_camelot_covers_all_24_wheel_positions
    codes = Exportify::Analyzer::CAMELOT.values.uniq.sort

    assert_equal 24, codes.size
  end

  def test_camelot_returns_nil_for_unknown_key
    assert_nil Exportify::Analyzer.camelot('H')
    assert_nil Exportify::Analyzer.camelot(nil)
  end
end

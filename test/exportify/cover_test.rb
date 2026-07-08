# frozen_string_literal: true

require 'test_helper'
require 'exportify/cover'

class CoverTest < Minitest::Test
  def test_for_is_deterministic_for_same_input
    first = Exportify::Cover.for('Rock dos Anos 80')
    second = Exportify::Cover.for('Rock dos Anos 80')

    assert_equal first, second
  end

  def test_for_returns_different_colors_for_different_input
    rock = Exportify::Cover.for('Rock dos Anos 80')
    trap = Exportify::Cover.for('Trap Brasil')

    refute_equal rock[:from], trap[:from]
  end

  def test_for_uses_first_letter_as_initial_uppercased
    cover = Exportify::Cover.for('rock dos anos 80')

    assert_equal 'R', cover[:initial]
  end

  def test_for_falls_back_to_note_symbol_for_empty_string
    cover = Exportify::Cover.for('')

    assert_equal '♪', cover[:initial]
  end

  def test_for_returns_hex_colors_from_palette
    cover = Exportify::Cover.for('Qualquer Nome')

    assert_match(/\A#[0-9A-F]{6}\z/i, cover[:from])
    assert_match(/\A#[0-9A-F]{6}\z/i, cover[:to])
  end
end

# frozen_string_literal: true

require 'open3'

module Exportify
  module Analyzer
    module_function

    # Analisa um MP3 e retorna { bpm:, key: } (qualquer um pode ser nil),
    # ou nil se as duas detecções falharem.
    def analyze(filepath)
      bpm = detect_bpm(filepath)
      key = detect_key(filepath)
      return nil unless bpm || key

      { bpm: bpm, key: key }
    end

    # BPM via `aubio tempo`, que imprime o timestamp (em segundos) de cada
    # batida detectada. Calculamos o BPM pelo intervalo mediano entre batidas.
    # Errno::ENOENT = binário não instalado → degrada para nil (sem quebrar).
    def detect_bpm(filepath)
      stdout, _stderr, status = Open3.capture3('aubio', 'tempo', filepath.to_s)
      return nil unless status.success?

      beats = stdout.scan(/\d+\.\d+/).map(&:to_f)
      return nil if beats.size < 2

      intervals = beats.each_cons(2).map { |a, b| b - a }.select(&:positive?)
      return nil if intervals.empty?

      median = intervals.sort[intervals.size / 2]
      (60.0 / median).round(2)
    rescue Errno::ENOENT
      nil
    end

    # Tonalidade via `keyfinder-cli`, que imprime a key musical (ex.: "Am").
    # Errno::ENOENT = binário não instalado → degrada para nil.
    def detect_key(filepath)
      stdout, _stderr, status = Open3.capture3('keyfinder-cli', filepath.to_s)
      return nil unless status.success?

      key = stdout.strip
      key.empty? ? nil : key
    rescue Errno::ENOENT
      nil
    end

    # Converte a key musical no código Camelot usado para mixagem harmônica.
    def camelot(key)
      CAMELOT[key.to_s]
    end

    # Roda de Camelot: lado B = maiores, lado A = menores. Inclui as duas
    # grafias enarmônicas (bemol e sustenido) para cobrir qualquer saída.
    CAMELOT = {
      # Maiores (lado B)
      'B' => '1B',
      'F#' => '2B',  'Gb' => '2B',
      'Db' => '3B',  'C#' => '3B',
      'Ab' => '4B',  'G#' => '4B',
      'Eb' => '5B',  'D#' => '5B',
      'Bb' => '6B',  'A#' => '6B',
      'F' => '7B',
      'C' => '8B',
      'G' => '9B',
      'D' => '10B',
      'A' => '11B',
      'E' => '12B',
      # Menores (lado A)
      'Abm' => '1A',  'G#m' => '1A',
      'Ebm' => '2A',  'D#m' => '2A',
      'Bbm' => '3A',  'A#m' => '3A',
      'Fm' => '4A',
      'Cm' => '5A',
      'Gm' => '6A',
      'Dm' => '7A',
      'Am' => '8A',
      'Em' => '9A',
      'Bm' => '10A',
      'F#m' => '11A', 'Gbm' => '11A',
      'C#m' => '12A', 'Dbm' => '12A'
    }.freeze
  end
end

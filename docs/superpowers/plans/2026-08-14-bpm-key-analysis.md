# Análise de BPM + Key — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detectar BPM e tonalidade (key) de cada MP3, gravar nas tags ID3 (`TBPM`/`TKEY`) e exibir no app web — a fundação para as futuras features de DJ.

**Architecture:** Um novo módulo `Exportify::Analyzer` roda `aubio tempo` (BPM) e `keyfinder-cli` (key) via `Open3`, e converte a key musical em código Camelot com uma tabela em Ruby puro. `Exportify::Tagger` ganha um método `tag_analysis` que grava só os frames `TBPM`/`TKEY` sem tocar nos demais. A análise roda automaticamente após cada download (desligável com `--no-analyze`) e em lote pelo novo subcomando `analyze`. O app web (`Library` + views) passa a ler e exibir BPM e Camelot.

**Tech Stack:** Ruby 3.3, Minitest, `Open3`, mutagen (Python/ID3), `keyfinder-cli`, `aubio`.

## Global Constraints

- Ruby 3.3+ (`.ruby-version`).
- Comentários e textos de UI/CLI em **pt-BR** com acentuação correta.
- Comandos externos sempre via array de args (nunca string de shell) — mesmo padrão de `Downloader`/`Library`.
- Testes não podem depender dos binários reais (`aubio`/`keyfinder-cli`) nem de rede: sempre mockar `Open3.capture3` / `system` / métodos do módulo.
- Nas tags gravamos só `TBPM` (BPM inteiro) e `TKEY` (key musical, ex.: `Am`). O código Camelot é **derivado**, nunca armazenado.
- Todo código novo passa em `bundle exec rake test` e `bundle exec rubocop`.

---

### Task 1: Módulo `Analyzer` (detecção + tabela Camelot)

**Files:**
- Create: `lib/exportify/analyzer.rb`
- Modify: `lib/exportify.rb` (adicionar `require_relative 'exportify/analyzer'`)
- Test: `test/exportify/analyzer_test.rb`

**Interfaces:**
- Produces:
  - `Exportify::Analyzer.analyze(filepath) -> { bpm: Integer|nil, key: String|nil }` ou `nil` se ambos falharem.
  - `Exportify::Analyzer.detect_bpm(filepath) -> Integer|nil`
  - `Exportify::Analyzer.detect_key(filepath) -> String|nil`
  - `Exportify::Analyzer.camelot(key) -> String|nil` (ex.: `"Am" -> "8A"`)
  - `Exportify::Analyzer::CAMELOT` (Hash congelado, 24 keys + apelidos enarmônicos)

- [ ] **Step 1: Escrever os testes que falham**

Criar `test/exportify/analyzer_test.rb`:

```ruby
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
```

- [ ] **Step 2: Rodar os testes e ver falhar**

Run: `bundle exec rake test TEST=test/exportify/analyzer_test.rb`
Expected: FAIL — `uninitialized constant Exportify::Analyzer`.

- [ ] **Step 3: Implementar o módulo**

Criar `lib/exportify/analyzer.rb`:

```ruby
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

      intervals = beats.each_cons(2).map { |a, b| b - a }.select { |d| d.positive? }
      return nil if intervals.empty?

      median = intervals.sort[intervals.size / 2]
      (60.0 / median).round
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
```

Adicionar em `lib/exportify.rb`, após a linha `require_relative 'exportify/tagger'`:

```ruby
require_relative 'exportify/analyzer'
```

- [ ] **Step 4: Rodar os testes e ver passar**

Run: `bundle exec rake test TEST=test/exportify/analyzer_test.rb`
Expected: PASS (todos os testes verdes).

- [ ] **Step 5: Lint + commit**

```bash
bundle exec rubocop lib/exportify/analyzer.rb test/exportify/analyzer_test.rb
git add lib/exportify/analyzer.rb lib/exportify.rb test/exportify/analyzer_test.rb
git commit -m "Adicionar Analyzer com detecção de BPM/key e tabela Camelot"
```

---

### Task 2: `Tagger.tag_analysis` (gravar só TBPM/TKEY)

**Files:**
- Modify: `lib/exportify/tagger.rb`
- Test: `test/exportify/tagger_test.rb`

**Interfaces:**
- Consumes: nada (resultado de `Analyzer.analyze` é passado pelo chamador).
- Produces: `Exportify::Tagger.tag_analysis(filepath, bpm: nil, key: nil) -> Boolean|nil` — grava só os frames presentes; no-op (`nil`) se ambos forem `nil`.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar a `test/exportify/tagger_test.rb` (dentro da classe `TaggerTest`):

```ruby
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
```

- [ ] **Step 2: Rodar os testes e ver falhar**

Run: `bundle exec rake test TEST=test/exportify/tagger_test.rb`
Expected: FAIL — `undefined method 'tag_analysis'`.

- [ ] **Step 3: Implementar `tag_analysis`**

Adicionar a `lib/exportify/tagger.rb` (dentro de `module Tagger`, após o método `tag`):

```ruby
    def tag_analysis(filepath, bpm: nil, key: nil)
      return if bpm.nil? && key.nil?

      sets = []
      sets << "tags['TBPM'] = TBPM(encoding=3, text=#{bpm.to_s.inspect})" if bpm
      sets << "tags['TKEY'] = TKEY(encoding=3, text=#{key.to_s.inspect})" if key

      python = <<~PY
        from mutagen.id3 import ID3, TBPM, TKEY, error
        try:
          tags = ID3(#{filepath.inspect})
        except error:
          tags = ID3()
        #{sets.join("\n")}
        tags.save(#{filepath.inspect})
      PY
      system('python3', '-c', python)
    end
```

- [ ] **Step 4: Rodar os testes e ver passar**

Run: `bundle exec rake test TEST=test/exportify/tagger_test.rb`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
bundle exec rubocop lib/exportify/tagger.rb test/exportify/tagger_test.rb
git add lib/exportify/tagger.rb test/exportify/tagger_test.rb
git commit -m "Adicionar Tagger.tag_analysis para gravar frames TBPM/TKEY"
```

---

### Task 3: Análise automática no download + flag `--no-analyze`

**Files:**
- Modify: `lib/exportify/cli.rb` (require, `run`, `download_chaptered_video`)
- Test: `test/exportify/cli_test.rb`

**Interfaces:**
- Consumes: `Analyzer.analyze`, `Tagger.tag_analysis` (Tasks 1–2).
- Produces: `download_chaptered_video(data, output_dir, retag:, browser:, analyze:)` — novo kwarg `analyze:` (default `true`).

- [ ] **Step 1: Escrever os testes que falham**

Adicionar a `test/exportify/cli_test.rb` (dentro de `CLITest`):

```ruby
  def test_download_runs_analysis_by_default
    require 'tmpdir'
    analyzed = []

    fake_data = {
      name: 'P',
      tracks: [
        { artist: 'A', name: 'Song', video_id: 'vid1', all_artists: 'A',
          raw_name: 'Song', album: 'P', year: '', track_number: 1, genre: '' }
      ]
    }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        Exportify::YouTube.stub(:fetch_playlist, fake_data) do
          # cria o arquivo para File.exist? passar
          Exportify::Downloader.stub(:download, lambda do |_t, out, **|
            FileUtils.touch(File.join(out, 'A - Song.mp3'))
            true
          end) do
            Exportify::Tagger.stub(:tag, true) do
              Exportify::Analyzer.stub(:analyze, { bpm: 128, key: 'Am' }) do
                Exportify::Tagger.stub(:tag_analysis, ->(path, **kw) { analyzed << [path, kw] }) do
                  Exportify::CLI.run(['https://www.youtube.com/playlist?list=PL123'])
                end
              end
            end
          end
        end
      end
    end

    assert_equal 1, analyzed.size
    assert_equal({ bpm: 128, key: 'Am' }, analyzed.first[1])
  end

  def test_no_analyze_flag_skips_analysis
    require 'tmpdir'

    fake_data = {
      name: 'P',
      tracks: [
        { artist: 'A', name: 'Song', video_id: 'vid1', all_artists: 'A',
          raw_name: 'Song', album: 'P', year: '', track_number: 1, genre: '' }
      ]
    }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        Exportify::YouTube.stub(:fetch_playlist, fake_data) do
          Exportify::Downloader.stub(:download, lambda do |_t, out, **|
            FileUtils.touch(File.join(out, 'A - Song.mp3'))
            true
          end) do
            Exportify::Tagger.stub(:tag, true) do
              # se a análise rodar, o raise falha o teste
              Exportify::Analyzer.stub(:analyze, ->(*_a) { raise 'não deveria analisar' }) do
                Exportify::CLI.run(['https://www.youtube.com/playlist?list=PL123', '--no-analyze'])
              end
            end
          end
        end
      end
    end
  end
```

- [ ] **Step 2: Rodar os testes e ver falhar**

Run: `bundle exec rake test TEST=test/exportify/cli_test.rb`
Expected: FAIL — a análise não é chamada (primeiro teste falha em `assert_equal 1`); `--no-analyze` é opção desconhecida do OptionParser.

- [ ] **Step 3: Implementar**

Em `lib/exportify/cli.rb`, adicionar no topo (junto aos outros `require_relative`):

```ruby
require_relative 'analyzer'
```

Em `run`, adicionar a variável e a flag. Trocar:

```ruby
      retag   = false
      sync    = false
      browser = nil
```

por:

```ruby
      retag   = false
      sync    = false
      browser = nil
      analyze = true
```

E adicionar dentro do bloco `OptionParser.new`, após a opção `--browser`:

```ruby
        opts.on('--no-analyze', 'Não detectar BPM/key após o download') { analyze = false }
```

No loop padrão de download, trocar:

```ruby
          if success && File.exist?(filepath)
            Tagger.tag(filepath, track)
            ok += 1
          else
            failed += 1
          end
```

por:

```ruby
          if success && File.exist?(filepath)
            Tagger.tag(filepath, track)
            analyze_file(filepath) if analyze
            ok += 1
          else
            failed += 1
          end
```

Na chamada do fluxo com capítulos, trocar:

```ruby
        result = download_chaptered_video({ name: name, tracks: tracks }, output_dir, retag: retag, browser: browser)
```

por:

```ruby
        result = download_chaptered_video({ name: name, tracks: tracks }, output_dir,
                                          retag: retag, browser: browser, analyze: analyze)
```

Na assinatura de `download_chaptered_video`, trocar:

```ruby
    def download_chaptered_video(data, output_dir, retag: false, browser: nil)
```

por:

```ruby
    def download_chaptered_video(data, output_dir, retag: false, browser: nil, analyze: true)
```

E dentro dela, no laço que renomeia/taggeia, trocar:

```ruby
        File.rename(source_file, target_file)
        Tagger.tag(target_file, track)
        ok += 1
```

por:

```ruby
        File.rename(source_file, target_file)
        Tagger.tag(target_file, track)
        analyze_file(target_file) if analyze
        ok += 1
```

Adicionar o helper privado (junto aos outros métodos de `module CLI`):

```ruby
    def analyze_file(filepath)
      result = Analyzer.analyze(filepath)
      Tagger.tag_analysis(filepath, **result) if result
    end
```

- [ ] **Step 4: Rodar os testes e ver passar**

Run: `bundle exec rake test TEST=test/exportify/cli_test.rb`
Expected: PASS (incluindo os testes já existentes de download/chaptered).

- [ ] **Step 5: Lint + commit**

```bash
bundle exec rubocop lib/exportify/cli.rb test/exportify/cli_test.rb
git add lib/exportify/cli.rb test/exportify/cli_test.rb
git commit -m "Rodar análise de BPM/key após o download (--no-analyze desliga)"
```

---

### Task 4: Subcomando `analyze` + leitura de BPM/key nas tags

**Files:**
- Modify: `lib/exportify/library.rb` (`read_tags` passa a expor `bpm`/`key`)
- Modify: `lib/exportify/cli.rb` (`run` roteia `analyze`; novos `run_analyze`/`analyze_playlist`)
- Test: `test/exportify/library_test.rb`, `test/exportify/cli_test.rb`

**Interfaces:**
- Consumes: `Analyzer.analyze`, `Tagger.tag_analysis`, `Library.playlists`, `Library.playlist_dir`, `Library.read_tags`.
- Produces:
  - `Library.read_tags(filepath)` passa a incluir as chaves `:bpm` e `:key`.
  - `CLI.analyze_playlist(playlist_name, reanalyze: false)` — analisa os `*.mp3` de uma playlist, pulando os já analisados.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar a `test/exportify/library_test.rb`:

```ruby
  def test_read_tags_includes_bpm_and_key
    stdout = '{"title":"","all_artists":"","artist":"","album":"","year":"",' \
             '"track_number":"","genre":"","bpm":"128","key":"Am","duration_seconds":10.0}'
    status = Object.new
    status.define_singleton_method(:success?) { true }

    Open3.stub(:capture3, [stdout, '', status]) do
      tags = Exportify::Library.read_tags('/tmp/x.mp3')
      assert_equal '128', tags[:bpm]
      assert_equal 'Am', tags[:key]
    end
  end
```

> Se `library_test.rb` ainda não faz `require 'open3'`, adicionar no topo.

Adicionar a `test/exportify/cli_test.rb`:

```ruby
  def test_analyze_playlist_skips_already_analyzed
    require 'tmpdir'

    Dir.mktmpdir do |root|
      dir = File.join(root, 'MinhaPlaylist')
      FileUtils.mkdir_p(dir)
      FileUtils.touch(File.join(dir, 'A - Song.mp3'))

      Exportify::Config.stub(:output_dir, root) do
        Exportify::Library.stub(:read_tags, { bpm: '128', key: 'Am' }) do
          Exportify::Analyzer.stub(:analyze, ->(*_a) { raise 'não deveria analisar' }) do
            assert_output(/1 skipped/) do
              Exportify::CLI.analyze_playlist('MinhaPlaylist')
            end
          end
        end
      end
    end
  end

  def test_analyze_playlist_analyzes_missing_and_tags
    require 'tmpdir'
    tagged = []

    Dir.mktmpdir do |root|
      dir = File.join(root, 'MinhaPlaylist')
      FileUtils.mkdir_p(dir)
      FileUtils.touch(File.join(dir, 'A - Song.mp3'))

      Exportify::Config.stub(:output_dir, root) do
        Exportify::Library.stub(:read_tags, { bpm: '', key: '' }) do
          Exportify::Analyzer.stub(:analyze, { bpm: 128, key: 'Am' }) do
            Exportify::Tagger.stub(:tag_analysis, ->(path, **kw) { tagged << [path, kw] }) do
              assert_output(/1 analyzed/) do
                Exportify::CLI.analyze_playlist('MinhaPlaylist')
              end
            end
          end
        end
      end
    end

    assert_equal 1, tagged.size
    assert_equal({ bpm: 128, key: 'Am' }, tagged.first[1])
  end

  def test_analyze_playlist_reanalyze_ignores_existing_tags
    require 'tmpdir'
    tagged = []

    Dir.mktmpdir do |root|
      dir = File.join(root, 'MinhaPlaylist')
      FileUtils.mkdir_p(dir)
      FileUtils.touch(File.join(dir, 'A - Song.mp3'))

      Exportify::Config.stub(:output_dir, root) do
        # já tem tags, mas --reanalyze força; read_tags nem deveria decidir skip
        Exportify::Analyzer.stub(:analyze, { bpm: 130, key: 'Em' }) do
          Exportify::Tagger.stub(:tag_analysis, ->(path, **kw) { tagged << [path, kw] }) do
            assert_output(/1 analyzed/) do
              Exportify::CLI.analyze_playlist('MinhaPlaylist', reanalyze: true)
            end
          end
        end
      end
    end

    assert_equal 1, tagged.size
  end
```

- [ ] **Step 2: Rodar os testes e ver falhar**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Then: `bundle exec rake test TEST=test/exportify/cli_test.rb`
Expected: FAIL — `read_tags` não traz `:bpm`; `analyze_playlist` indefinido.

- [ ] **Step 3: Implementar leitura de tags**

Em `lib/exportify/library.rb`, dentro do script Python de `read_tags`, adicionar as duas linhas antes de `'duration_seconds'`:

```python
          'bpm': str(tags.get('TBPM', '')),
          'key': str(tags.get('TKEY', '')),
```

- [ ] **Step 4: Implementar o subcomando `analyze`**

Em `lib/exportify/cli.rb`, adicionar o require (se ainda não estiver presente da Task 3):

```ruby
require_relative 'library'
```

Adicionar o roteamento no início de `run`, junto às outras subcomandos:

```ruby
      return run_analyze(argv[1..]) if argv[0] == 'analyze'
```

Adicionar os métodos (em `module CLI`):

```ruby
    def run_analyze(argv)
      reanalyze = false
      all       = false

      parser = OptionParser.new do |opts|
        opts.banner = "Usage:\n  " \
                      "exportify analyze \"<playlist>\" [--reanalyze]\n  " \
                      'exportify analyze --all [--reanalyze]'
        opts.on('--reanalyze', 'Recalcular BPM/key mesmo em faixas já analisadas') { reanalyze = true }
        opts.on('--all', 'Analisar todas as playlists baixadas') { all = true }
      end
      parser.parse!(argv)

      targets =
        if all
          Library.playlists.map { |playlist| playlist[:name] }
        elsif argv[0]
          [argv[0]]
        else
          abort parser.banner
        end

      targets.each { |name| analyze_playlist(name, reanalyze: reanalyze) }
    end

    def analyze_playlist(playlist_name, reanalyze: false)
      dir = Library.playlist_dir(playlist_name)
      unless dir
        puts "Playlist não encontrada: #{playlist_name}"
        return
      end

      files = Dir.glob(File.join(dir, '*.mp3')).sort
      puts "#{playlist_name}: #{files.size} faixas"

      analyzed = skipped = failed = 0

      files.each do |filepath|
        print "  #{File.basename(filepath)} "

        if !reanalyze && already_analyzed?(filepath)
          puts '(já analisada, pulando)'
          skipped += 1
          next
        end

        result = Analyzer.analyze(filepath)
        if result
          Tagger.tag_analysis(filepath, **result)
          puts "(#{result[:bpm]} BPM, #{result[:key]})"
          analyzed += 1
        else
          puts '(falha na análise)'
          failed += 1
        end
      end

      puts "\n#{playlist_name}: #{analyzed} analyzed, #{skipped} skipped, #{failed} failed."
    end

    def already_analyzed?(filepath)
      tags = Library.read_tags(filepath)
      return false unless tags

      !tags[:bpm].to_s.strip.empty? && !tags[:key].to_s.strip.empty?
    end
```

- [ ] **Step 5: Rodar os testes e ver passar**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Then: `bundle exec rake test TEST=test/exportify/cli_test.rb`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

```bash
bundle exec rubocop lib/exportify/library.rb lib/exportify/cli.rb test/exportify/library_test.rb test/exportify/cli_test.rb
git add lib/exportify/library.rb lib/exportify/cli.rb test/exportify/library_test.rb test/exportify/cli_test.rb
git commit -m "Adicionar subcomando analyze e leitura de BPM/key nas tags"
```

---

### Task 5: Exibir BPM + Camelot no app web

**Files:**
- Modify: `lib/exportify/library.rb` (`track_summary`, `track` expõem `bpm`/`key`/`camelot`)
- Modify: `views/playlist.html.erb` (badge na lista)
- Modify: `views/track.html.erb` (linhas de BPM e Key)
- Modify: `public/style.css` (estilo do badge)
- Test: `test/exportify/library_test.rb`

**Interfaces:**
- Consumes: `Analyzer.camelot`, `Library.read_tags` (com `:bpm`/`:key`).
- Produces: `track_summary`/`track` passam a incluir `:bpm`, `:key`, `:camelot`.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar a `test/exportify/library_test.rb`:

```ruby
  def test_track_summary_includes_bpm_and_camelot
    tags = { title: 'T', artist: 'A', track_number: '1', genre: 'x', bpm: '128', key: 'Am' }
    Exportify::Library.stub(:read_tags, tags) do
      summary = Exportify::Library.track_summary('/x/A - T.mp3')
      assert_equal '128', summary[:bpm]
      assert_equal '8A', summary[:camelot]
    end
  end

  def test_track_summary_camelot_nil_without_key
    tags = { title: 'T', artist: 'A', track_number: '1', genre: 'x', bpm: '', key: '' }
    Exportify::Library.stub(:read_tags, tags) do
      summary = Exportify::Library.track_summary('/x/A - T.mp3')
      assert_nil summary[:bpm]
      assert_nil summary[:camelot]
    end
  end
```

- [ ] **Step 2: Rodar os testes e ver falhar**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Expected: FAIL — `summary[:bpm]` é `nil`/inexistente.

- [ ] **Step 3: Expor bpm/key/camelot na `Library`**

Em `lib/exportify/library.rb`, no `require`, adicionar (topo do arquivo):

```ruby
require_relative 'analyzer'
```

No método `track_summary`, trocar o hash de retorno:

```ruby
      { filename: filename, title: title, artist: artist, genre: genre, sort_key: number || Float::INFINITY }
```

por:

```ruby
      bpm     = presence(tags && tags[:bpm])
      key     = presence(tags && tags[:key])
      camelot = key && Analyzer.camelot(key)

      { filename: filename, title: title, artist: artist, genre: genre,
        bpm: bpm, key: key, camelot: camelot, sort_key: number || Float::INFINITY }
```

No método `track`, adicionar ao hash de retorno (antes de `duration_seconds:`):

```ruby
        bpm: presence(tags && tags[:bpm]),
        key: presence(tags && tags[:key]),
        camelot: (k = presence(tags && tags[:key])) && Analyzer.camelot(k),
```

- [ ] **Step 4: Rodar os testes e ver passar**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Expected: PASS.

- [ ] **Step 5: Exibir na lista de faixas**

Em `views/playlist.html.erb`, dentro do `<span class="chart-list__info">`, após a linha do artista (`chart-list__artist`), adicionar:

```erb
            <% if track[:bpm] || track[:camelot] %>
              <span class="chart-list__badge">
                <%= ERB::Util.html_escape([track[:bpm], track[:camelot]].compact.join(' · ')) %>
              </span>
            <% end %>
```

- [ ] **Step 6: Exibir no detalhe da faixa**

Em `views/track.html.erb`, dentro do `<ul class="track-meta">`, após a linha de Gênero (antes de Duração), adicionar:

```erb
  <li class="track-meta__row">
    <span class="track-meta__label">BPM</span>
    <span class="track-meta__value"><%= ERB::Util.html_escape(track[:bpm] || '—') %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Key</span>
    <span class="track-meta__value">
      <%= ERB::Util.html_escape([track[:key], track[:camelot] && "(#{track[:camelot]})"].compact.join(' ')) %>
      <%= '—' if track[:key].nil? %>
    </span>
  </li>
```

- [ ] **Step 7: Estilo do badge**

Adicionar ao final de `public/style.css`:

```css
.chart-list__badge {
  display: inline-block;
  margin-top: 2px;
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 11px;
  font-variant-numeric: tabular-nums;
  color: var(--text-muted, #9aa0a6);
  background: rgba(127, 127, 127, 0.15);
}
```

- [ ] **Step 8: Verificação manual do app web**

Run: `bundle exec rake test` (suíte completa, para garantir que as views/rota não quebraram nos testes de `web_server`).
Expected: PASS. (Renderização visual é conferida na etapa de verify.)

- [ ] **Step 9: Lint + commit**

```bash
bundle exec rubocop lib/exportify/library.rb test/exportify/library_test.rb
git add lib/exportify/library.rb views/playlist.html.erb views/track.html.erb public/style.css test/exportify/library_test.rb
git commit -m "Exibir BPM e Camelot na lista e no detalhe da faixa"
```

---

### Task 6: Dependências (Makefile) + documentação

**Files:**
- Modify: `Makefile` (alvo `install-analysis`, incluído em `install`)
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:** nenhuma (infra/docs).

- [ ] **Step 1: Adicionar o alvo `install-analysis` ao Makefile**

Em `Makefile`, na linha `.PHONY`, acrescentar `install-analysis`:

```makefile
.PHONY: install check-ruby install-yt-dlp install-mutagen install-analysis bundle help
```

Na regra `install`, incluir a nova dependência:

```makefile
install: check-ruby install-yt-dlp install-mutagen install-analysis bundle
	@echo "\nAmbiente pronto."
```

No bloco `help`, adicionar a linha:

```makefile
	@echo "  make install-analysis - instala keyfinder-cli e aubio (BPM/key), se ainda não estiverem disponíveis"
```

Adicionar a regra (após `install-mutagen`):

```makefile
install-analysis:
	@if command -v keyfinder-cli >/dev/null 2>&1 && command -v aubio >/dev/null 2>&1; then \
		echo "keyfinder-cli e aubio já instalados."; \
	elif [ "$$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then \
		echo "Instalando keyfinder-cli e aubio via Homebrew..."; \
		brew install keyfinder-cli aubio; \
	elif [ "$$(uname -s)" = "Linux" ] && command -v apt-get >/dev/null 2>&1; then \
		echo "Instalando keyfinder-cli e aubio via apt..."; \
		sudo apt-get update && sudo apt-get install -y keyfinder-cli aubio; \
	else \
		echo "Não foi possível instalar keyfinder-cli/aubio automaticamente neste sistema."; \
		echo "Instale manualmente (keyfinder-cli e aubio) e rode novamente."; \
		exit 1; \
	fi
```

- [ ] **Step 2: Verificar o Makefile (dry-run)**

Run: `make -n install-analysis`
Expected: imprime os comandos do alvo sem executá-los (sem erro de sintaxe do Make).

- [ ] **Step 3: Atualizar o README**

Em `README.md`, na seção **Requirements**, adicionar após a linha do mutagen:

```markdown
- [keyfinder-cli](https://github.com/EvanPurkhiser/keyfinder-cli) e
  [aubio](https://aubio.org/) — detecção de tonalidade (key) e BPM —
  `brew install keyfinder-cli aubio`
```

Ainda na seção **Setup**, na frase que descreve o `make install`, mencionar que
ele também instala `keyfinder-cli` e `aubio`.

Adicionar uma nova subseção em **Usage**, após "Regravar tags ID3":

```markdown
### Analisar BPM e tonalidade (key)

Faixas novas já saem analisadas no download (BPM em `TBPM`, key em `TKEY`).
Para desligar a análise pontualmente:

```sh
exportify <url> --no-analyze
```

Para analisar faixas já baixadas (acervo antigo):

```sh
exportify analyze "Nome da Playlist"   # uma playlist
exportify analyze --all                # todas as playlists
```

Faixas que já têm BPM e key são puladas. Use `--reanalyze` para recalcular:

```sh
exportify analyze --all --reanalyze
```

A tonalidade é exibida no app web em notação Camelot (ex.: `128 · 8A`),
usada para mixagem harmônica.
```

- [ ] **Step 4: Atualizar o CHANGELOG**

Em `CHANGELOG.md`, na seção `## [Unreleased]` → `### Added`, acrescentar:

```markdown
- Detecção automática de BPM e tonalidade (key) no download, gravadas nas tags
  ID3 (`TBPM`/`TKEY`); desligável com `--no-analyze`.
- Subcomando `analyze` para detectar BPM/key de faixas já baixadas
  (`analyze "<playlist>"` ou `analyze --all`, com `--reanalyze` para recalcular).
- Exibição de BPM e tonalidade em notação Camelot no app web.
```

- [ ] **Step 5: Commit**

```bash
git add Makefile README.md CHANGELOG.md
git commit -m "Instalar keyfinder-cli/aubio e documentar análise de BPM/key"
```

---

## Verificação final

- [ ] Rodar a suíte completa e o lint:

```bash
bundle exec rake test
bundle exec rubocop
```

Expected: tudo verde.

- [ ] (Opcional, com os binários instalados) Verificação de ponta a ponta com um MP3 real:

```bash
make install-analysis
exportify analyze "<alguma playlist já baixada>"
exportify web    # conferir os badges de BPM/Camelot na lista e no detalhe
```

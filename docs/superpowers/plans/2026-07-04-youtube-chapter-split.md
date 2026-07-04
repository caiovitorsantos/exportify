# Download de vídeo único do YouTube com corte por capítulos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que `exportify <url_de_video>` baixe um vídeo único do YouTube e, se ele tiver capítulos declarados, separe automaticamente em um MP3 por capítulo com tags ID3 corretas; sem capítulos, baixa como uma faixa única.

**Architecture:** Novo `Exportify::YouTube.fetch_video` busca metadado completo do vídeo (`yt-dlp -J`) e monta uma lista de "faixas" — uma por capítulo, ou uma única faixa se não houver capítulos. `CLI.source_for` passa a reconhecer URLs `/watch?v=...`. Como cortar por capítulos exige baixar e processar o vídeo inteiro numa única chamada ao `yt-dlp --split-chapters` (não dá pra baixar capítulo por capítulo), esse caso ganha um método dedicado (`CLI.download_chaptered_video`) chamado antes do loop padrão de download; o caso sem capítulos reaproveita o loop existente sem nenhuma mudança nele.

**Tech Stack:** Ruby 3.3, Minitest, `yt-dlp` (via `Open3.capture3` para metadado, `system` para download+split), JSON stdlib.

## Global Constraints

- Ruby >= 3.3.
- `frozen_string_literal: true` no topo de todo arquivo `.rb` novo ou modificado.
- Strings com aspas simples (`Style/StringLiterals: EnforcedStyle: single_quotes`).
- Limite de linha: 120 colunas (`Layout/LineLength`).
- Módulos sem estado usam `module_function` (padrão já usado em `YouTube`, `Downloader`, `CLI`).
- `Minitest/MultipleAssertions: Max: 5` — nenhum teste novo pode ter mais de 5 `assert_*`.
- A funcionalidade não pode exigir nenhuma dependência nova além do `yt-dlp` já usado (usa `--split-chapters`, nativo do yt-dlp; nenhuma chamada direta a `ffmpeg` no nosso código).
- Rodar suíte de testes: `bundle exec rake test`. Rodar um arquivo isolado: `bundle exec ruby -Ilib -Itest test/exportify/<arquivo>_test.rb`.
- Lint: `bundle exec rubocop` — deve ficar limpo (0 offenses).
- Não alterar o contrato de campos consumido por `Exportify::Tagger.tag` (`raw_name`, `all_artists`, `artist`, `album`, `year`, `track_number`, `genre`).
- `lib/exportify/cli.rb` já está excluído das métricas de `Metrics/MethodLength`/`AbcSize`/`CyclomaticComplexity`/`PerceivedComplexity`/`BlockLength`/`ModuleLength` no `.rubocop.yml` — não é necessário se preocupar com esses cops nesse arquivo.

---

## Task 1: `Exportify::YouTube.fetch_video`

Busca metadado completo de um vídeo único via `yt-dlp -J` e monta a lista de faixas: uma por capítulo (se houver), ou uma única faixa (reaproveitando `build_track`, já existente) caso contrário.

**Files:**
- Modify: `lib/exportify/youtube.rb`
- Test: `test/exportify/youtube_test.rb`

**Interfaces:**
- Consumes: `Exportify::YouTube.split_title(title, fallback_artist)` e `Exportify::YouTube.build_track(entry, index, playlist_name)` (ambos já existentes no arquivo, inalterados)
- Produces: `Exportify::YouTube.fetch_video(url, browser: nil) -> { name: String, tracks: Array<Hash>, chaptered: true|false }`. Cada track de capítulo tem as chaves `:artist, :all_artists, :name, :raw_name, :album, :year, :track_number, :genre, :video_id, :chapter_start, :chapter_end`. A track única (sem capítulos) tem as mesmas chaves de `build_track`, sem `:chapter_start`/`:chapter_end`.

- [ ] **Step 1: Escrever os testes que falham**

Adicione a `test/exportify/youtube_test.rb`, antes do `end` final da classe (o helper `stub_yt_dlp` já existe no arquivo, reaproveite-o):

```ruby
  def test_fetch_video_returns_chaptered_tracks_when_chapters_present
    body = {
      'id' => 'vid1',
      'title' => 'Slow Touch Mix',
      'uploader' => 'ChartHistories',
      'chapters' => [
        { 'title' => 'Aftersoft', 'start_time' => 0.0, 'end_time' => 171.0 },
        { 'title' => 'Cloud Nine Room', 'start_time' => 171.0, 'end_time' => 372.0 }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      result = Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1')

      assert_equal 'Slow Touch Mix', result[:name]
      assert result[:chaptered]
      assert_equal 2, result[:tracks].size
    end
  end

  def test_fetch_video_builds_chapter_track_fields
    body = {
      'id' => 'vid1',
      'title' => 'Slow Touch Mix',
      'uploader' => 'ChartHistories',
      'chapters' => [
        { 'title' => 'Aftersoft', 'start_time' => 0.0, 'end_time' => 171.0 }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      track = Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1')[:tracks].first

      expected = {
        artist: 'ChartHistories',
        all_artists: 'ChartHistories',
        name: 'Aftersoft',
        raw_name: 'Aftersoft',
        album: 'Slow Touch Mix',
        year: '',
        track_number: 1,
        genre: '',
        video_id: 'vid1',
        chapter_start: 0.0,
        chapter_end: 171.0
      }

      assert_equal expected, track
    end
  end

  def test_fetch_video_returns_single_track_without_chapters
    body = {
      'id' => 'vid1',
      'title' => 'Rick Astley - Never Gonna Give You Up',
      'uploader' => 'Rick Astley',
      'chapters' => nil
    }.to_json

    stub_yt_dlp(stdout: body) do
      result = Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1')

      refute result[:chaptered]
      assert_equal 1, result[:tracks].size
      assert_equal 'Rick Astley', result[:tracks].first[:artist]
      assert_equal 'Never Gonna Give You Up', result[:tracks].first[:name]
    end
  end

  def test_fetch_video_aborts_when_yt_dlp_fails
    stub_yt_dlp(stdout: '', stderr: 'ERROR: Video unavailable', success: false) do
      assert_output(nil, /Video unavailable/) do
        assert_raises(SystemExit) { Exportify::YouTube.fetch_video('https://www.youtube.com/watch?v=vid1') }
      end
    end
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec ruby -Ilib -Itest test/exportify/youtube_test.rb`
Expected: `NoMethodError: undefined method 'fetch_video' for module Exportify::YouTube` nos 4 novos testes

- [ ] **Step 3: Implementar `fetch_video` e `build_chapter_track`**

Em `lib/exportify/youtube.rb`, adicione os dois métodos abaixo (por exemplo, logo depois de `fetch_playlist` e antes de `build_track`):

```ruby
    def fetch_video(url, browser: nil)
      cmd = ['yt-dlp', '-J', '--no-warnings', url]
      cmd += ['--cookies-from-browser', browser] if browser

      stdout, stderr, status = Open3.capture3(*cmd)
      abort "Erro ao acessar vídeo do YouTube: #{stderr.strip}" unless status.success?

      data     = JSON.parse(stdout)
      title    = data['title'] || 'YouTube Video'
      chapters = data['chapters']

      if chapters && !chapters.empty?
        {
          name: title,
          tracks: chapters.each_with_index.map { |chapter, i| build_chapter_track(chapter, i, data) },
          chaptered: true
        }
      else
        {
          name: title,
          tracks: [build_track(data, 0, title)],
          chaptered: false
        }
      end
    end

    def build_chapter_track(chapter, index, data)
      artist, name = split_title(chapter['title'].to_s, data['uploader'] || data['channel'])

      {
        artist: artist,
        all_artists: artist,
        name: name,
        raw_name: chapter['title'].to_s,
        album: data['title'].to_s,
        year: data['release_year'].to_s,
        track_number: index + 1,
        genre: '',
        video_id: data['id'],
        chapter_start: chapter['start_time'],
        chapter_end: chapter['end_time']
      }
    end
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec ruby -Ilib -Itest test/exportify/youtube_test.rb`
Expected: `17 runs, ... 0 failures, 0 errors, 0 skips`

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/youtube.rb test/exportify/youtube_test.rb
git commit -m "Adicionar YouTube.fetch_video para vídeo único com ou sem capítulos"
```

---

## Task 2: `CLI.source_for` reconhece URLs de vídeo único

**Files:**
- Modify: `lib/exportify/cli.rb:192-197`
- Test: `test/exportify/cli_test.rb`

**Interfaces:**
- Produces: `Exportify::CLI.source_for(url)` passa a poder retornar também `:youtube_video`, além dos já existentes `:spotify`, `:youtube`, `nil`

- [ ] **Step 1: Escrever os testes que falham**

Adicione a `test/exportify/cli_test.rb`, antes do `end` final da classe:

```ruby
  def test_source_for_detects_youtube_video
    assert_equal :youtube_video, Exportify::CLI.source_for('https://www.youtube.com/watch?v=abc123')
  end

  def test_source_for_detects_youtube_video_with_mix_list_param
    assert_equal :youtube_video, Exportify::CLI.source_for('https://www.youtube.com/watch?v=abc123&list=RDabc123')
  end

  def test_source_for_returns_nil_for_watch_url_without_v_param
    assert_nil Exportify::CLI.source_for('https://www.youtube.com/watch?list=PL123')
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: `test_source_for_detects_youtube_video` e `test_source_for_detects_youtube_video_with_mix_list_param` falham (`source_for` retorna `nil`, pois ainda só reconhece `/playlist`)

- [ ] **Step 3: Estender `source_for`**

Em `lib/exportify/cli.rb`, substitua o método `source_for`:

```ruby
    def source_for(url)
      return :spotify if url.include?('open.spotify.com')
      return :youtube if url.match?(%r{(music\.)?youtube\.com/playlist})
      return :youtube_video if url.match?(%r{(music\.)?youtube\.com/watch}) && url.match?(/[?&]v=/)

      nil
    end
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: todos os testes do arquivo passam (nenhuma regressão nos existentes)

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/cli.rb test/exportify/cli_test.rb
git commit -m "Reconhecer URLs de vídeo único do YouTube em CLI.source_for"
```

---

## Task 3: `CLI.download_chaptered_video`

Baixa e corta um vídeo por capítulos numa única chamada ao `yt-dlp --split-chapters`, renomeia os arquivos gerados para o padrão do projeto, taggeia cada um e remove o arquivo do vídeo completo (não cortado). Também cobre o modo `--retag` (retaggeia arquivos já existentes, sem baixar nada) e o caso "todos os capítulos já existem" (pula sem chamar o yt-dlp).

**Files:**
- Modify: `lib/exportify/cli.rb`
- Test: `test/exportify/cli_test.rb`

**Interfaces:**
- Consumes: `Downloader.sanitize(str)`, `Tagger.tag(filepath, track)` (ambos já existentes, inalterados)
- Produces: `Exportify::CLI.download_chaptered_video(data, output_dir, retag: false) -> { ok: Integer, skip: Integer, failed: Integer }`, onde `data` é `{ name:, tracks: }` (mesmo formato retornado por `YouTube.fetch_video`)

- [ ] **Step 1: Escrever os testes que falham**

Adicione a `test/exportify/cli_test.rb`, antes do `end` final da classe:

```ruby
  def test_download_chaptered_video_skips_when_all_files_exist
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      tracks = [
        { artist: 'Channel', name: 'Song A', video_id: 'vid1' },
        { artist: 'Channel', name: 'Song B', video_id: 'vid1' }
      ]
      FileUtils.touch(File.join(dir, 'Channel - Song A.mp3'))
      FileUtils.touch(File.join(dir, 'Channel - Song B.mp3'))

      result = nil
      Exportify::CLI.stub(:system, ->(*_args) { raise 'yt-dlp não deveria ser chamado' }) do
        result = Exportify::CLI.download_chaptered_video({ name: 'Video Title', tracks: tracks }, dir)
      end

      assert_equal({ ok: 0, skip: 2, failed: 0 }, result)
    end
  end

  def test_download_chaptered_video_downloads_renames_tags_and_cleans_up
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      tracks = [
        { artist: 'Lady Gaga', name: 'Aftersoft', video_id: 'vid1' },
        { artist: 'Lady Gaga', name: 'Cloud Nine Room', video_id: 'vid1' }
      ]
      result = nil

      Exportify::CLI.stub(
        :system,
        lambda { |*_args|
          FileUtils.touch(File.join(dir, '1 - Aftersoft.mp3'))
          FileUtils.touch(File.join(dir, '2 - Cloud Nine Room.mp3'))
          FileUtils.touch(File.join(dir, 'Full Video Title.mp3'))
          true
        }
      ) do
        Exportify::Tagger.stub(:tag, true) do
          result = Exportify::CLI.download_chaptered_video({ name: 'Full Video Title', tracks: tracks }, dir)
        end
      end

      assert_equal({ ok: 2, skip: 0, failed: 0 }, result)
      assert_path_exists File.join(dir, 'Lady Gaga - Aftersoft.mp3')
      assert_path_exists File.join(dir, 'Lady Gaga - Cloud Nine Room.mp3')
      refute_path_exists File.join(dir, 'Full Video Title.mp3')
    end
  end

  def test_download_chaptered_video_retag_mode_tags_existing_files_only
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      tracks = [
        { artist: 'Lady Gaga', name: 'Aftersoft', video_id: 'vid1' },
        { artist: 'Lady Gaga', name: 'Missing Track', video_id: 'vid1' }
      ]
      FileUtils.touch(File.join(dir, 'Lady Gaga - Aftersoft.mp3'))

      result = nil
      tagged = []

      Exportify::Tagger.stub(:tag, ->(path, _track) { tagged << path }) do
        Exportify::CLI.stub(:system, ->(*_args) { raise 'yt-dlp não deveria ser chamado em modo retag' }) do
          result = Exportify::CLI.download_chaptered_video(
            { name: 'Full Video Title', tracks: tracks }, dir, retag: true
          )
        end
      end

      assert_equal({ ok: 1, skip: 1, failed: 0 }, result)
      assert_equal [File.join(dir, 'Lady Gaga - Aftersoft.mp3')], tagged
    end
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: `NoMethodError: undefined method 'download_chaptered_video'` nos 3 novos testes

- [ ] **Step 3: Implementar `download_chaptered_video`**

Em `lib/exportify/cli.rb`, adicione o método (por exemplo, logo depois de `fetch_spotify_playlist`):

```ruby
    def download_chaptered_video(data, output_dir, retag: false)
      tracks = data[:tracks]
      expected_files = tracks.map do |track|
        "#{Downloader.sanitize(track[:artist])} - #{Downloader.sanitize(track[:name])}.mp3"
      end

      if retag
        ok = skip = 0

        tracks.each_with_index do |track, i|
          filepath = File.join(output_dir, expected_files[i])

          if File.exist?(filepath)
            Tagger.tag(filepath, track)
            ok += 1
          else
            skip += 1
          end
        end

        return { ok: ok, skip: skip, failed: 0 }
      end

      if expected_files.all? { |f| File.exist?(File.join(output_dir, f)) }
        return { ok: 0, skip: tracks.size, failed: 0 }
      end

      video_id  = tracks.first[:video_id]
      video_url = "https://www.youtube.com/watch?v=#{video_id}"

      success = system(
        'yt-dlp', video_url,
        '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
        '--split-chapters',
        '--paths', output_dir,
        '--output', 'chapter:%(section_number)s - %(section_title)s.%(ext)s',
        '--output', '%(title)s.%(ext)s',
        '--no-warnings', '--quiet'
      )

      return { ok: 0, skip: 0, failed: tracks.size } unless success

      ok = 0

      tracks.each_with_index do |track, i|
        source_file = Dir.glob(File.join(output_dir, "#{i + 1} - *.mp3")).first
        next unless source_file

        target_file = File.join(output_dir, expected_files[i])
        File.rename(source_file, target_file)
        Tagger.tag(target_file, track)
        ok += 1
      end

      Dir.glob(File.join(output_dir, '*.mp3')).each do |file|
        File.delete(file) unless expected_files.include?(File.basename(file))
      end

      { ok: ok, skip: 0, failed: tracks.size - ok }
    end
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: todos os testes do arquivo passam

- [ ] **Step 5: Rodar RuboCop**

Run: `bundle exec rubocop lib/exportify/cli.rb test/exportify/cli_test.rb`
Expected: `no offenses detected`

- [ ] **Step 6: Commit**

```bash
git add lib/exportify/cli.rb test/exportify/cli_test.rb
git commit -m "Adicionar CLI.download_chaptered_video para baixar e cortar vídeo por capítulos"
```

---

## Task 4: Religar `CLI.run` para a origem `:youtube_video`

**Files:**
- Modify: `lib/exportify/cli.rb`
- Test: `test/exportify/cli_test.rb`

**Interfaces:**
- Consumes: `Exportify::CLI.source_for(url)` (Task 2), `Exportify::YouTube.fetch_video(url, browser: nil)` (Task 1), `Exportify::CLI.download_chaptered_video(data, output_dir, retag: false)` (Task 3)

- [ ] **Step 1: Escrever os testes que falham**

Adicione a `test/exportify/cli_test.rb`, antes do `end` final da classe:

```ruby
  def test_youtube_video_source_with_chapters_calls_download_chaptered_video
    require 'tmpdir'

    fake_data = {
      name: 'Some Video',
      tracks: [
        { artist: 'Channel', name: 'Song A', video_id: 'vid1', chapter_start: 0.0, chapter_end: 10.0 }
      ],
      chaptered: true
    }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        Exportify::YouTube.stub(:fetch_video, fake_data) do
          Exportify::CLI.stub(:download_chaptered_video, ->(_data, _output_dir, retag:) { { ok: 1, skip: 0, failed: 0 } }) do
            assert_output(/1 tracks found/) do
              Exportify::CLI.run(['https://www.youtube.com/watch?v=vid1'])
            end
          end
        end
      end
    end
  end

  def test_youtube_video_source_without_chapters_uses_standard_loop
    require 'tmpdir'

    fake_data = {
      name: 'Some Video',
      tracks: [
        { artist: 'Channel', name: 'Song A', video_id: 'vid1', all_artists: 'Channel', raw_name: 'Song A',
          album: 'Some Video', year: '', track_number: 1, genre: '' }
      ],
      chaptered: false
    }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        Exportify::YouTube.stub(:fetch_video, fake_data) do
          Exportify::Downloader.stub(:download, true) do
            Exportify::Tagger.stub(:tag, true) do
              assert_output(/1 tracks found/) do
                Exportify::CLI.run(['https://www.youtube.com/watch?v=vid1'])
              end
            end
          end
        end
      end
    end
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: os dois novos testes falham com `SystemExit`/`Invalid playlist URL` (o `case source` ainda não tem o branch `:youtube_video`)

- [ ] **Step 3: Reescrever `CLI.run`**

Em `lib/exportify/cli.rb`, substitua o método `run` inteiro por:

```ruby
    def run(argv)
      return run_init(argv[1]) if argv[0] == 'init'

      retag   = false
      sync    = false
      browser = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage:\n  " \
                      "exportify init\n  " \
                      'exportify <playlist_or_video_url> [--retag] [--sync] [--browser=NOME]'
        opts.on('--retag', 'Regravar tags ID3 nos arquivos existentes') { retag = true }
        opts.on('--sync',  'Remover arquivos locais que não estão mais na playlist') { sync = true }
        opts.on('--browser=NOME', 'Navegador para extrair cookies (playlists privadas do YouTube)') do |b|
          browser = b
        end
      end

      parser.parse!(argv)
      url = argv[0]

      abort parser.banner unless url

      source = source_for(url)
      abort 'Invalid playlist URL' unless source

      puts 'Fetching playlist...'
      chaptered = false

      name, tracks =
        case source
        when :spotify
          fetch_spotify_playlist(url)
        when :youtube
          data = YouTube.fetch_playlist(url, browser: browser)
          [data[:name], data[:tracks]]
        when :youtube_video
          data = YouTube.fetch_video(url, browser: browser)
          chaptered = data[:chaptered]
          [data[:name], data[:tracks]]
        end

      output_dir = File.expand_path(File.join(Config.output_dir, Downloader.sanitize(name)))

      FileUtils.mkdir_p(output_dir)

      puts "#{tracks.size} tracks found"
      puts "Output: #{output_dir}\n\n"

      if chaptered
        result = download_chaptered_video({ name: name, tracks: tracks }, output_dir, retag: retag)
        ok     = result[:ok]
        skip   = result[:skip]
        failed = result[:failed]
      else
        ok = skip = failed = 0

        tracks.each_with_index do |track, i|
          artist   = Downloader.sanitize(track[:artist])
          name     = Downloader.sanitize(track[:name])
          filename = "#{artist} - #{name}.mp3"
          filepath = File.join(output_dir, filename)

          print "[#{i + 1}/#{tracks.size}] #{filename} "

          if retag
            if File.exist?(filepath)
              Tagger.tag(filepath, track)
              puts '(retagged)'
              ok += 1
            else
              puts '(not found, skipping)'
              skip += 1
            end
            next
          end

          if File.exist?(filepath)
            puts '(already exists, skipping)'
            skip += 1
            next
          end

          puts '(downloading...)'
          success = Downloader.download(track, output_dir)

          if success && File.exist?(filepath)
            Tagger.tag(filepath, track)
            ok += 1
          else
            failed += 1
          end
        end
      end

      removed = 0

      if sync
        expected = tracks.to_set do |track|
          "#{Downloader.sanitize(track[:artist])} - #{Downloader.sanitize(track[:name])}.mp3"
        end

        Dir.glob(File.join(output_dir, '*.mp3')).each do |file|
          next if expected.include?(File.basename(file))

          puts "Removing #{File.basename(file)}"
          File.delete(file)
          removed += 1
        end
      end

      if retag
        puts "\nDone: #{ok} retagged, #{skip} not found."
      else
        removed_msg = sync ? ", #{removed} removed" : ''
        puts "\nDone: #{ok} downloaded, #{skip} skipped, #{failed} failed#{removed_msg}."
      end
    end
```

Não recrie `fetch_spotify_playlist`, `download_chaptered_video` nem `source_for` — todos já existem no arquivo desde as tarefas anteriores; apenas substitua o método `run`.

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec rake test`
Expected: todos os testes passam (nenhuma regressão nos testes de Spotify/YouTube-playlist já existentes)

- [ ] **Step 5: Rodar RuboCop**

Run: `bundle exec rubocop lib/exportify/cli.rb test/exportify/cli_test.rb`
Expected: `no offenses detected`

- [ ] **Step 6: Commit**

```bash
git add lib/exportify/cli.rb test/exportify/cli_test.rb
git commit -m "Religar CLI.run para baixar vídeo único do YouTube (com ou sem capítulos)"
```

---

## Task 5: Documentação (README + CHANGELOG)

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Atualizar o README**

Em `README.md`, na seção `## Usage`, logo depois do bloco "Baixar uma playlist do YouTube ou YouTube Music" (linha 79 atual), adicione:

```markdown
### Baixar um vídeo único do YouTube (com capítulos)

```sh
exportify "https://www.youtube.com/watch?v=<id>"
```

Se o vídeo tiver capítulos declarados (comum em mixes e compilações, onde cada capítulo marca o início de uma música), o exportify baixa o vídeo uma única vez e separa automaticamente em um MP3 por capítulo, com artista extraído do título do capítulo (padrão `"Artista - Título"`, com fallback para o canal) e álbum = título do vídeo. Sem capítulos, baixa como uma faixa única. As flags `--retag`, `--sync` e `--browser` funcionam da mesma forma que para playlists.
```

Na seção `## Requirements`, ajuste a linha sobre YouTube para mencionar também vídeos únicos:

Troque:
```markdown
- Para playlists do YouTube/YouTube Music não é necessária nenhuma credencial adicional — só o `yt-dlp`.
```
por:
```markdown
- Para playlists ou vídeos únicos do YouTube/YouTube Music não é necessária nenhuma credencial adicional — só o `yt-dlp`.
```

- [ ] **Step 2: Atualizar o CHANGELOG**

Em `CHANGELOG.md`, dentro da seção `## [Unreleased]` já existente, adicione um item à lista de `### Added`:

```markdown
- Suporte a download de um vídeo único do YouTube com corte automático por
  capítulos (um MP3 por capítulo, com tags ID3 corretas); sem capítulos,
  baixa como uma faixa única.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "Documentar suporte a vídeo único do YouTube com corte por capítulos"
```

---

## Task 6: Verificação final

**Files:** nenhum (apenas execução de comandos)

- [ ] **Step 1: Rodar a suíte completa**

Run: `bundle exec rake test`
Expected: todos os testes passam, incluindo os novos de `youtube_test.rb` e `cli_test.rb`

- [ ] **Step 2: Rodar RuboCop no projeto inteiro**

Run: `bundle exec rubocop`
Expected: `no offenses detected`

- [ ] **Step 3: Rodar bundler-audit**

Run: `bundle exec bundler-audit check --update`
Expected: nenhuma vulnerabilidade encontrada (nenhuma gem nova foi adicionada nesta feature)

- [ ] **Step 4: Smoke test manual (opcional, requer yt-dlp instalado e internet)**

Run: `bin/exportify "https://www.youtube.com/watch?v=<video_com_capitulos>"`
Expected: cria subpasta com o nome do vídeo em `musics/` e gera um MP3 por capítulo, com tags ID3 preenchidas (artista, álbum = título do vídeo, número da faixa sequencial); o arquivo do vídeo completo não fica no disco ao final.

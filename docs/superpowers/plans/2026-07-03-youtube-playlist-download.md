# Download de playlists do YouTube/YouTube Music Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que `exportify <url>` baixe faixas de playlists do YouTube e do YouTube Music (além do Spotify), salvando MP3s com tags ID3 em subpastas, reaproveitando o pipeline de download/tag/sync já existente.

**Architecture:** Novo módulo `Exportify::YouTube` extrai nome + faixas de uma playlist do YouTube via `yt-dlp --flat-playlist -J` (sem OAuth/API key). `Exportify::CLI` passa a detectar a origem da URL (`:spotify` vs `:youtube`) e ramificar apenas a etapa de "obter nome + faixas"; o restante do pipeline (baixar, taggear, sync) é compartilhado entre as duas origens. `Exportify::Downloader.download` passa a baixar direto por `video_id` quando disponível, em vez de buscar via `ytsearch1:`.

**Tech Stack:** Ruby 3.3, Minitest, `yt-dlp` (shell-out via `Open3.capture3`/`system`), JSON stdlib.

## Global Constraints

- Ruby >= 3.3 (ver `exportify.gemspec` / `.ruby-version`).
- `frozen_string_literal: true` no topo de todo arquivo `.rb` novo ou modificado.
- Strings com aspas simples (`Style/StringLiterals: EnforcedStyle: single_quotes`).
- Limite de linha: 120 colunas (`Layout/LineLength`).
- Módulos sem estado usam `module_function` (padrão de `Spotify`, `Downloader`, `Config`).
- O fluxo YouTube não deve exigir nenhuma credencial/API key/OAuth — só o binário `yt-dlp`.
- Não alterar o contrato de campos consumido por `Exportify::Tagger.tag` (`raw_name`, `all_artists`, `artist`, `album`, `year`, `track_number`, `genre`).
- Rodar suíte de testes: `bundle exec rake test`. Rodar um arquivo isolado: `bundle exec ruby -Ilib -Itest test/exportify/<arquivo>_test.rb`.
- Lint: `bundle exec rubocop`.

---

## Task 1: `Exportify::YouTube.split_title`

Função pura que separa "Artista - Título" do título de um vídeo, com fallback para o nome do canal quando o padrão não é encontrado.

**Files:**
- Create: `lib/exportify/youtube.rb`
- Test: `test/exportify/youtube_test.rb`

**Interfaces:**
- Produces: `Exportify::YouTube.split_title(title, fallback_artist) -> [artist, name]` (ambos `String`)

- [ ] **Step 1: Escrever o teste que falha**

Crie `test/exportify/youtube_test.rb`:

```ruby
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
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/youtube_test.rb`
Expected: `NameError: uninitialized constant Exportify::YouTube` (ou erro equivalente, já que o módulo ainda não existe)

- [ ] **Step 3: Implementar `split_title`**

Crie `lib/exportify/youtube.rb`:

```ruby
# frozen_string_literal: true

module Exportify
  module YouTube
    module_function

    def split_title(title, fallback_artist)
      if title =~ /\A(.+?)\s*-\s*(.+)\z/
        [Regexp.last_match(1).strip, Regexp.last_match(2).strip]
      else
        [fallback_artist.to_s, title.to_s]
      end
    end
  end
end
```

Adicione o require em `lib/exportify.rb` (depois de `spotify`, antes de `downloader`, para manter a ordem alfabética dos módulos de origem de dados):

```ruby
require_relative 'exportify/spotify'
require_relative 'exportify/youtube'
require_relative 'exportify/downloader'
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/youtube_test.rb`
Expected: `3 runs, 3 assertions, 0 failures, 0 errors, 0 skips`

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/youtube.rb lib/exportify.rb test/exportify/youtube_test.rb
git commit -m "Adicionar YouTube.split_title para separar artista e título do vídeo"
```

---

## Task 2: `Exportify::YouTube.fetch_playlist`

Busca nome da playlist e lista de faixas via `yt-dlp --flat-playlist -J`, normalizando cada entrada para o mesmo formato de track usado pelo `Spotify.playlist_tracks`.

**Files:**
- Modify: `lib/exportify/youtube.rb`
- Test: `test/exportify/youtube_test.rb`

**Interfaces:**
- Consumes: `Exportify::YouTube.split_title(title, fallback_artist)` (Task 1)
- Produces: `Exportify::YouTube.fetch_playlist(url, browser: nil) -> { name: String, tracks: Array<Hash> }`, onde cada track tem as chaves `:artist, :all_artists, :name, :raw_name, :album, :year, :track_number, :genre, :video_id`

- [ ] **Step 1: Escrever os testes que falham**

Adicione a `test/exportify/youtube_test.rb`:

```ruby
require 'json'
require 'ostruct'
require 'open3'

class YouTubeTest < Minitest::Test
  # ... (testes de split_title já existentes permanecem)

  def stub_yt_dlp(stdout:, stderr: '', success: true, &block)
    status = OpenStruct.new(success?: success)
    Open3.stub(:capture3, [stdout, stderr, status], &block)
  end

  def test_fetch_playlist_returns_name_and_tracks
    body = {
      'title' => 'Minha Playlist',
      'entries' => [
        { 'id' => 'vid1', 'title' => 'Rick Astley - Never Gonna Give You Up', 'uploader' => 'Rick Astley' },
        { 'id' => 'vid2', 'title' => 'Video Sem Padrão', 'uploader' => 'Canal Qualquer' }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      result = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')

      assert_equal 'Minha Playlist', result[:name]
      assert_equal 2, result[:tracks].size
    end
  end

  def test_fetch_playlist_normalizes_first_track_fields
    body = {
      'title' => 'Minha Playlist',
      'entries' => [
        { 'id' => 'vid1', 'title' => 'Rick Astley - Never Gonna Give You Up', 'uploader' => 'Rick Astley' }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      track = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')[:tracks].first

      assert_equal 'Rick Astley', track[:artist]
      assert_equal 'Rick Astley', track[:all_artists]
      assert_equal 'Never Gonna Give You Up', track[:name]
      assert_equal 'Rick Astley - Never Gonna Give You Up', track[:raw_name]
      assert_equal 'Minha Playlist', track[:album]
      assert_equal 'vid1', track[:video_id]
    end
  end

  def test_fetch_playlist_assigns_sequential_track_numbers
    body = {
      'title' => 'Minha Playlist',
      'entries' => [
        { 'id' => 'vid1', 'title' => 'A - B', 'uploader' => 'X' },
        { 'id' => 'vid2', 'title' => 'C - D', 'uploader' => 'Y' }
      ]
    }.to_json

    stub_yt_dlp(stdout: body) do
      tracks = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')[:tracks]

      assert_equal 1, tracks[0][:track_number]
      assert_equal 2, tracks[1][:track_number]
    end
  end

  def test_fetch_playlist_leaves_year_and_genre_blank
    body = {
      'title' => 'Minha Playlist',
      'entries' => [{ 'id' => 'vid1', 'title' => 'A - B', 'uploader' => 'X' }]
    }.to_json

    stub_yt_dlp(stdout: body) do
      track = Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123')[:tracks].first

      assert_equal '', track[:year]
      assert_equal '', track[:genre]
    end
  end

  def test_fetch_playlist_aborts_when_yt_dlp_fails
    stub_yt_dlp(stdout: '', stderr: 'ERROR: Private video', success: false) do
      assert_output(nil, /Private video/) do
        assert_raises(SystemExit) { Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123') }
      end
    end
  end

  def test_fetch_playlist_aborts_when_playlist_is_empty
    body = { 'title' => 'Vazia', 'entries' => [] }.to_json

    stub_yt_dlp(stdout: body) do
      assert_output(nil, /vazia ou inacessível/) do
        assert_raises(SystemExit) { Exportify::YouTube.fetch_playlist('https://www.youtube.com/playlist?list=PL123') }
      end
    end
  end
end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec ruby -Ilib -Itest test/exportify/youtube_test.rb`
Expected: `NoMethodError: undefined method 'fetch_playlist' for module Exportify::YouTube` nos 6 novos testes

- [ ] **Step 3: Implementar `fetch_playlist`**

Substitua o conteúdo de `lib/exportify/youtube.rb` por:

```ruby
# frozen_string_literal: true

require 'json'
require 'open3'

module Exportify
  module YouTube
    module_function

    def fetch_playlist(url, browser: nil)
      cmd = ['yt-dlp', '--flat-playlist', '-J', '--no-warnings', url]
      cmd += ['--cookies-from-browser', browser] if browser

      stdout, stderr, status = Open3.capture3(*cmd)
      abort "Erro ao acessar playlist do YouTube: #{stderr.strip}" unless status.success?

      data    = JSON.parse(stdout)
      entries = data['entries'] || []
      abort 'Playlist do YouTube vazia ou inacessível.' if entries.empty?

      playlist_name = data['title'] || 'YouTube Playlist'

      {
        name: playlist_name,
        tracks: entries.each_with_index.map { |entry, i| build_track(entry, i, playlist_name) }
      }
    end

    def build_track(entry, index, playlist_name)
      artist, name = split_title(entry['title'].to_s, entry['uploader'] || entry['channel'])

      {
        artist: artist,
        all_artists: artist,
        name: name,
        raw_name: entry['title'].to_s,
        album: playlist_name,
        year: '',
        track_number: index + 1,
        genre: '',
        video_id: entry['id']
      }
    end

    def split_title(title, fallback_artist)
      if title =~ /\A(.+?)\s*-\s*(.+)\z/
        [Regexp.last_match(1).strip, Regexp.last_match(2).strip]
      else
        [fallback_artist.to_s, title.to_s]
      end
    end
  end
end
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec ruby -Ilib -Itest test/exportify/youtube_test.rb`
Expected: `9 runs, ... 0 failures, 0 errors, 0 skips`

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/youtube.rb test/exportify/youtube_test.rb
git commit -m "Adicionar YouTube.fetch_playlist para listar faixas via yt-dlp"
```

---

## Task 3: `Downloader.download` baixa direto por `video_id`

Quando a track tem `video_id` (origem YouTube), baixar o vídeo direto pela URL, sem busca via `ytsearch1:`.

**Files:**
- Modify: `lib/exportify/downloader.rb:7-19`
- Test: `test/exportify/downloader_test.rb`

**Interfaces:**
- Consumes: track Hash com chave opcional `:video_id` (produzida por `YouTube.fetch_playlist`, Task 2)
- Produces: `Exportify::Downloader.download(track, output_dir)` — comportamento inalterado para tracks sem `:video_id`

- [ ] **Step 1: Escrever os testes que falham**

Adicione a `test/exportify/downloader_test.rb`, antes do `end` final da classe:

```ruby
  def test_download_with_video_id_uses_direct_url
    track = {
      video_id: 'dQw4w9WgXcQ',
      artist: 'Rick Astley',
      all_artists: 'Rick Astley',
      name: 'Never Gonna Give You Up',
      raw_name: 'Never Gonna Give You Up'
    }
    received_args = nil

    Exportify::Downloader.stub(:system, ->(*args) { received_args = args; true }) do
      Exportify::Downloader.download(track, '/tmp')
    end

    assert_includes received_args, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
    refute received_args.any? { |a| a.to_s.start_with?('ytsearch1:') }
  end

  def test_download_without_video_id_uses_search
    track = {
      artist: 'Britney Spears',
      all_artists: 'Britney Spears',
      name: 'Womanizer',
      raw_name: 'Womanizer'
    }
    received_args = nil

    Exportify::Downloader.stub(:system, ->(*args) { received_args = args; true }) do
      Exportify::Downloader.download(track, '/tmp')
    end

    assert received_args.any? { |a| a.to_s.start_with?('ytsearch1:') }
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec ruby -Ilib -Itest test/exportify/downloader_test.rb`
Expected: `test_download_with_video_id_uses_direct_url` falha (`assert_includes` não encontra a URL direta, pois o código ainda sempre usa `ytsearch1:`)

- [ ] **Step 3: Implementar o branch por `video_id`**

Em `lib/exportify/downloader.rb`, substitua o método `download`:

```ruby
    def download(track, output_dir)
      artist   = sanitize(track[:artist])
      name     = sanitize(track[:name])
      template = File.join(output_dir, "#{artist} - #{name}.%(ext)s")

      source = if track[:video_id]
                 "https://www.youtube.com/watch?v=#{track[:video_id]}"
               else
                 query = "#{track[:raw_name]} #{track[:all_artists]} official audio"
                 "ytsearch1:#{query}"
               end

      system(
        'yt-dlp', source,
        '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
        '--output', template,
        '--no-playlist', '--quiet', '--no-warnings'
      )
    end
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec ruby -Ilib -Itest test/exportify/downloader_test.rb`
Expected: `13 runs, ... 0 failures, 0 errors, 0 skips`

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/downloader.rb test/exportify/downloader_test.rb
git commit -m "Baixar direto pelo video_id quando a track vier do YouTube"
```

---

## Task 4: `CLI.source_for` detecta a origem da URL

**Files:**
- Modify: `lib/exportify/cli.rb`
- Test: `test/exportify/cli_test.rb`

**Interfaces:**
- Produces: `Exportify::CLI.source_for(url) -> :spotify | :youtube | nil`

- [ ] **Step 1: Escrever os testes que falham**

Adicione a `test/exportify/cli_test.rb`, antes do `end` final da classe:

```ruby
  def test_source_for_detects_spotify
    assert_equal :spotify, Exportify::CLI.source_for('https://open.spotify.com/playlist/abc123')
  end

  def test_source_for_detects_youtube
    assert_equal :youtube, Exportify::CLI.source_for('https://www.youtube.com/playlist?list=PL123')
  end

  def test_source_for_detects_youtube_music
    assert_equal :youtube, Exportify::CLI.source_for('https://music.youtube.com/playlist?list=PL123')
  end

  def test_source_for_returns_nil_for_unknown_domain
    assert_nil Exportify::CLI.source_for('https://example.com/whatever')
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: `NoMethodError: undefined method 'source_for'`

- [ ] **Step 3: Implementar `source_for`**

Em `lib/exportify/cli.rb`, adicione o método (dentro do `module CLI`, próximo aos outros `module_function`, por exemplo logo depois de `read_secret`):

```ruby
    def source_for(url)
      return :spotify if url.include?('open.spotify.com')
      return :youtube if url.match?(%r{(music\.)?youtube\.com/playlist})

      nil
    end
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: `18 runs, ... 0 failures, 0 errors, 0 skips`

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/cli.rb test/exportify/cli_test.rb
git commit -m "Adicionar CLI.source_for para detectar origem Spotify/YouTube da URL"
```

---

## Task 5: Ramificar `CLI.run` por origem e adicionar flag `--browser`

Liga tudo: banner e flag `--browser`, ramificação Spotify/YouTube para obter nome+faixas, mantendo o restante do pipeline (mkdir, loop de download/retag, resumo, `--sync`) compartilhado.

**Importante:** a extração de query string feita hoje (`argv[0]&.split('?', 2)&.first`) **não pode** ser aplicada à URL usada para `YouTube.fetch_playlist` — URLs de playlist do YouTube guardam o ID da playlist justamente na query string (`?list=...`). Essa normalização deve ficar restrita ao branch do Spotify.

**Files:**
- Modify: `lib/exportify/cli.rb`
- Test: `test/exportify/cli_test.rb`

**Interfaces:**
- Consumes:
  - `Exportify::CLI.source_for(url)` (Task 4)
  - `Exportify::YouTube.fetch_playlist(url, browser: nil)` (Task 2) — retorna `{ name:, tracks: }`
  - `Exportify::Spotify.playlist_name`, `Exportify::Spotify.playlist_tracks`, `Exportify::Spotify.enrich_with_genres` (já existentes, inalterados)

- [ ] **Step 1: Escrever o teste de integração que falha**

Adicione a `test/exportify/cli_test.rb`, antes do `end` final da classe:

```ruby
  def test_youtube_source_skips_spotify_credentials_check
    require 'tmpdir'
    ENV.delete('SPOTIFY_CLIENT_ID')
    ENV.delete('SPOTIFY_CLIENT_SECRET')

    fake_data = {
      name: 'Minha Playlist',
      tracks: [
        { artist: 'Rick Astley', all_artists: 'Rick Astley', name: 'Never Gonna Give You Up',
          raw_name: 'Never Gonna Give You Up', album: 'Minha Playlist', year: '', track_number: 1,
          genre: '', video_id: 'vid1' }
      ]
    }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:load, -> { {} }) do
        Exportify::Config.stub(:output_dir, dir) do
          Exportify::YouTube.stub(:fetch_playlist, fake_data) do
            Exportify::Downloader.stub(:download, true) do
              Exportify::Tagger.stub(:tag, true) do
                assert_output(/1 tracks found/) do
                  Exportify::CLI.run(['https://www.youtube.com/playlist?list=PL123'])
                end
              end
            end
          end
        end
      end
    end
  ensure
    ENV['SPOTIFY_CLIENT_ID']     = 'fake_id'
    ENV['SPOTIFY_CLIENT_SECRET'] = 'fake_secret'
  end

  def test_youtube_url_query_string_is_not_stripped_before_fetch
    require 'tmpdir'
    received_url = nil
    fake_data = { name: 'P', tracks: [] }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        Exportify::YouTube.stub(:fetch_playlist, ->(url, browser: nil) { received_url = url; fake_data }) do
          Exportify::CLI.run(['https://www.youtube.com/playlist?list=PL123'])
        end
      end
    end

    assert_equal 'https://www.youtube.com/playlist?list=PL123', received_url
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: `test_youtube_source_skips_spotify_credentials_check` falha — hoje `run` sempre tenta extrair `playlist_id` no formato do Spotify e aborta com `'Invalid playlist URL'` para uma URL do YouTube

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
                      'exportify <playlist_url> [--retag] [--sync] [--browser=NOME]'
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
      name, tracks =
        case source
        when :spotify
          fetch_spotify_playlist(url)
        when :youtube
          data = YouTube.fetch_playlist(url, browser: browser)
          [data[:name], data[:tracks]]
        end

      output_dir = File.expand_path(File.join(Config.output_dir, Downloader.sanitize(name)))

      FileUtils.mkdir_p(output_dir)

      puts "#{tracks.size} tracks found"
      puts "Output: #{output_dir}\n\n"

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

    def fetch_spotify_playlist(url)
      playlist_url = url.split('?', 2).first
      playlist_id  = playlist_url.match(%r{playlist/([A-Za-z0-9]+)})&.captures&.first
      abort 'Invalid playlist URL' unless playlist_id

      abort 'Credenciais não configuradas. Execute: exportify init' unless Auth.client_id && Auth.client_secret

      puts 'Authenticating with Spotify...'
      token = Auth.access_token

      name   = Spotify.playlist_name(playlist_id, token)
      tracks = Spotify.playlist_tracks(playlist_id, token)
      tracks = Spotify.enrich_with_genres(tracks, token)
      [name, tracks]
    end
```

`source_for` já existe no arquivo desde a Task 4 — não recrie nem duplique esse método, apenas mantenha-o como está.

Adicione o require em `lib/exportify/cli.rb`, junto aos demais `require_relative` no topo do arquivo:

```ruby
require_relative 'spotify'
require_relative 'youtube'
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec rake test`
Expected: todos os testes passam (nenhuma regressão nos existentes, incluindo `test_exits_with_invalid_url`, `test_exits_without_credentials`, `test_retag_flag_parsed_by_optionparser`, `test_sync_flag_parsed_by_optionparser`)

- [ ] **Step 5: Rodar RuboCop**

Run: `bundle exec rubocop lib/exportify/cli.rb lib/exportify/youtube.rb lib/exportify/downloader.rb`
Expected: `no offenses detected`

- [ ] **Step 6: Commit**

```bash
git add lib/exportify/cli.rb test/exportify/cli_test.rb
git commit -m "Ramificar CLI.run por origem Spotify/YouTube e adicionar flag --browser"
```

---

## Task 6: Documentação (README + CHANGELOG)

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Atualizar o README**

Em `README.md`, na seção `## Usage`, logo depois do bloco "Baixar uma playlist" existente, adicione:

```markdown
### Baixar uma playlist do YouTube ou YouTube Music

```sh
exportify https://www.youtube.com/playlist?list=<id>
exportify https://music.youtube.com/playlist?list=<id>
```

Para playlists privadas, use `--browser` para reaproveitar os cookies de um navegador logado no YouTube:

```sh
exportify https://www.youtube.com/playlist?list=<id> --browser=chrome
```

Faixas do YouTube não têm artista/álbum/gênero estruturados como no Spotify: o nome do artista é extraído do padrão `"Artista - Título"` no título do vídeo (com fallback para o nome do canal), e o nome da playlist é usado como álbum. Os campos ano e gênero ficam em branco. As flags `--retag` e `--sync` funcionam da mesma forma que para playlists do Spotify.
```

Na seção `## Requirements`, adicione uma nota sobre a origem alternativa (sem exigir credencial nova):

```markdown
- Para playlists do YouTube/YouTube Music não é necessária nenhuma credencial adicional — só o `yt-dlp`.
```

- [ ] **Step 2: Atualizar o CHANGELOG**

Em `CHANGELOG.md`, adicione uma seção `## [Unreleased]` no topo, antes de `## [1.0.1]`:

```markdown
## [Unreleased]

### Added

- Suporte a download de playlists do YouTube e YouTube Music (além do
  Spotify), incluindo playlists privadas via `--browser` (cookies do
  navegador).
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "Documentar suporte a playlists do YouTube/YouTube Music"
```

---

## Task 7: Verificação final

**Files:** nenhum (apenas execução de comandos)

- [ ] **Step 1: Rodar a suíte completa**

Run: `bundle exec rake test`
Expected: todos os testes passam, incluindo os novos de `youtube_test.rb`, `downloader_test.rb` e `cli_test.rb`

- [ ] **Step 2: Rodar RuboCop no projeto inteiro**

Run: `bundle exec rubocop`
Expected: `no offenses detected`

- [ ] **Step 3: Rodar bundler-audit**

Run: `bundle exec bundler-audit check --update`
Expected: nenhuma vulnerabilidade encontrada (nenhuma gem nova foi adicionada nesta feature, então não deve haver mudanças aqui)

- [ ] **Step 4: Smoke test manual (opcional, requer yt-dlp instalado e internet)**

Run: `bin/exportify "https://www.youtube.com/playlist?list=<uma_playlist_publica_pequena>"`
Expected: cria subpasta com o nome da playlist em `musics/` e baixa os MP3s com tags ID3 preenchidas

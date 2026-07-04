# App web para visualizar playlists baixadas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar um app web somente leitura (`bin/exportify web`) para navegar pelas playlists e músicas já baixadas em disco, com detalhes de cada faixa (tags ID3, duração, tamanho) e player de áudio embutido.

**Architecture:** Novo módulo `Exportify::Library` lê playlists/faixas de `Config.output_dir` e metadados ID3 via `mutagen` (shell-out a `python3 -c`, mesmo padrão de `Tagger`). Novo módulo `Exportify::WebServer` sobe um `WEBrick::HTTPServer`, renderiza templates ERB server-side e serve os `.mp3` via `WEBrick::HTTPServlet::FileHandler` (suporte nativo a `Range` para o `<audio controls>`). Turbo (via CDN) dá navegação fluida entre páginas.

**Tech Stack:** Ruby 3.3, Minitest, WEBrick (já é dependência), ERB (stdlib), `python3`/`mutagen` (já usado por `Tagger`), Turbo via CDN.

## Global Constraints

- Ruby >= 3.3 (ver `exportify.gemspec` / `.ruby-version`).
- `frozen_string_literal: true` no topo de todo arquivo `.rb` novo ou modificado.
- Strings com aspas simples (`Style/StringLiterals: EnforcedStyle: single_quotes`).
- Limite de linha: 120 colunas (`Layout/LineLength`).
- Módulos sem estado usam `module_function` (padrão de `Spotify`, `Downloader`, `Config`, `Tagger`).
- Rodar suíte de testes: `bundle exec rake test`. Rodar um arquivo isolado: `bundle exec ruby -Ilib -Itest test/exportify/<arquivo>_test.rb`.
- Lint: `bundle exec rubocop`.
- O app web é **somente leitura**: não dispara downloads, não edita tags ID3, não cria/apaga playlists, sem autenticação (uso local pessoal).
- Turbo é carregado via CDN para navegação fluida. **Stimulus não é usado nesta versão**: o player é o `<audio controls>` nativo do navegador (play/pause/seek de graça) e não há lista com faixa "tocando agora" para destacar — adicionar Stimulus sem um comportamento concreto para controlar seria complexidade sem uso (YAGNI).
- O `<script>` do Turbo carregado via CDN usa `integrity`/`crossorigin` (Subresource Integrity), para não confiar cegamente no CDN. O hash em `views/layout.html.erb` (Task 5) foi calculado a partir do arquivo real publicado (`@hotwired/turbo@8.0.23/dist/turbo.es2017-umd.js`) via `curl | openssl dgst -sha384`. Se a versão do Turbo for atualizada no futuro, o hash precisa ser recalculado do mesmo jeito.
- `Config.output_dir` retorna um caminho possivelmente relativo (ex.: `'musics'`); todo acesso a disco deve passar por `File.expand_path(Config.output_dir)`.

---

## Task 1: `Exportify::Library.playlists`

**Files:**
- Create: `lib/exportify/library.rb`
- Modify: `lib/exportify.rb`
- Test: `test/exportify/library_test.rb`

**Interfaces:**
- Consumes: `Exportify::Config.output_dir -> String` (já existe em `lib/exportify/config.rb:22`)
- Produces: `Exportify::Library.playlists -> Array<{ name: String, track_count: Integer }>`, ordenado alfabeticamente por `name`. Retorna `[]` se o diretório não existir.

- [ ] **Step 1: Escrever o teste que falha**

Crie `test/exportify/library_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

class LibraryTest < Minitest::Test
  def test_playlists_returns_name_and_track_count_sorted
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Trap Brasil'))
      FileUtils.mkdir_p(File.join(dir, 'Rock dos Anos 80'))
      FileUtils.touch(File.join(dir, 'Rock dos Anos 80', 'Queen - Bohemian Rhapsody.mp3'))
      FileUtils.touch(File.join(dir, 'Rock dos Anos 80', 'David Bowie - Heroes.mp3'))
      FileUtils.touch(File.join(dir, 'Trap Brasil', 'Matuê - Kenny G.mp3'))

      Exportify::Config.stub(:output_dir, dir) do
        result = Exportify::Library.playlists

        assert_equal(
          [
            { name: 'Rock dos Anos 80', track_count: 2 },
            { name: 'Trap Brasil', track_count: 1 }
          ],
          result
        )
      end
    end
  end

  def test_playlists_ignores_non_mp3_files
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Playlist'))
      FileUtils.touch(File.join(dir, 'Playlist', 'cover.jpg'))

      Exportify::Config.stub(:output_dir, dir) do
        assert_equal [{ name: 'Playlist', track_count: 0 }], Exportify::Library.playlists
      end
    end
  end

  def test_playlists_returns_empty_array_when_output_dir_missing
    Exportify::Config.stub(:output_dir, '/tmp/exportify-test-does-not-exist') do
      assert_equal [], Exportify::Library.playlists
    end
  end
end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/library_test.rb`
Expected: `NameError: uninitialized constant Exportify::Library`

- [ ] **Step 3: Implementar `Exportify::Library.playlists`**

Crie `lib/exportify/library.rb`:

```ruby
# frozen_string_literal: true

require_relative 'config'

module Exportify
  module Library
    module_function

    def playlists
      root = File.expand_path(Config.output_dir)
      return [] unless Dir.exist?(root)

      Dir.children(root)
         .select { |entry| File.directory?(File.join(root, entry)) }
         .sort
         .map { |name| { name: name, track_count: Dir.glob(File.join(root, name, '*.mp3')).size } }
    end
  end
end
```

Adicione o require em `lib/exportify.rb` (após `require_relative 'exportify/tagger'`):

```ruby
require_relative 'exportify/library'
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/library_test.rb`
Expected: `3 runs, ... 0 failures, 0 errors`

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/library.rb lib/exportify.rb test/exportify/library_test.rb
git commit -m "feat: adicionar Exportify::Library.playlists"
```

---

## Task 2: `Exportify::Library.read_tags`

**Files:**
- Modify: `lib/exportify/library.rb`
- Modify: `test/exportify/library_test.rb`

**Interfaces:**
- Consumes: nada de tasks anteriores.
- Produces: `Exportify::Library.read_tags(filepath) -> Hash` com chaves símbolo `:title, :all_artists, :artist, :album, :year, :track_number, :genre, :duration_seconds` (strings, exceto `duration_seconds` que é `Float`), ou `nil` se a leitura falhar (arquivo inválido, `python3`/`mutagen` indisponível, JSON inválido). Usado pelas Tasks 3 e 4.

- [ ] **Step 1: Escrever o teste que falha**

Adicione em `test/exportify/library_test.rb` (topo do arquivo, adicionar requires; corpo da classe, adicionar os testes):

```ruby
require 'open3'
require 'ostruct'
```

```ruby
  def test_read_tags_returns_parsed_json_on_success
    json = '{"title":"Bohemian Rhapsody","all_artists":"Queen","artist":"Queen",' \
           '"album":"A Night at the Opera","year":"1975","track_number":"1",' \
           '"genre":"Rock","duration_seconds":354.5}'
    status = OpenStruct.new(success?: true)

    Open3.stub(:capture3, [json, '', status]) do
      tags = Exportify::Library.read_tags('/tmp/song.mp3')

      assert_equal 'Bohemian Rhapsody', tags[:title]
      assert_equal 354.5, tags[:duration_seconds]
    end
  end

  def test_read_tags_returns_nil_when_python_fails
    status = OpenStruct.new(success?: false)

    Open3.stub(:capture3, ['', 'error', status]) do
      assert_nil Exportify::Library.read_tags('/tmp/song.mp3')
    end
  end

  def test_read_tags_returns_nil_on_invalid_json
    status = OpenStruct.new(success?: true)

    Open3.stub(:capture3, ['not json', '', status]) do
      assert_nil Exportify::Library.read_tags('/tmp/song.mp3')
    end
  end

  def test_read_tags_script_includes_filepath
    script = nil
    status = OpenStruct.new(success?: true)

    Open3.stub(:capture3, lambda { |_cmd, _flag, s|
      script = s
      ['{}', '', status]
    }) do
      Exportify::Library.read_tags('/tmp/my song.mp3')
    end

    assert_includes script, '/tmp/my song.mp3'
  end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/library_test.rb`
Expected: `NoMethodError: undefined method 'read_tags' for module Exportify::Library`

- [ ] **Step 3: Implementar `read_tags`**

Em `lib/exportify/library.rb`, adicione no topo do arquivo:

```ruby
require 'open3'
require 'json'
```

E dentro de `module Library`, adicione o método (após `playlists`):

```ruby
    def read_tags(filepath)
      script = <<~PY
        from mutagen.mp3 import MP3
        import json

        audio = MP3(#{filepath.inspect})
        tags = audio.tags or {}

        print(json.dumps({
          'title': str(tags.get('TIT2', '')),
          'all_artists': str(tags.get('TPE1', '')),
          'artist': str(tags.get('TPE2', '')),
          'album': str(tags.get('TALB', '')),
          'year': str(tags.get('TDRC', '')),
          'track_number': str(tags.get('TRCK', '')),
          'genre': str(tags.get('TCON', '')),
          'duration_seconds': audio.info.length,
        }))
      PY

      stdout, _stderr, status = Open3.capture3('python3', '-c', script)
      return nil unless status.success?

      JSON.parse(stdout, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/library_test.rb`
Expected: `7 runs, ... 0 failures, 0 errors`

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/library.rb test/exportify/library_test.rb
git commit -m "feat: adicionar Exportify::Library.read_tags"
```

---

## Task 3: `Exportify::Library.tracks`

**Files:**
- Modify: `lib/exportify/library.rb`
- Modify: `test/exportify/library_test.rb`

**Interfaces:**
- Consumes: `Exportify::Library.read_tags(filepath) -> Hash | nil` (Task 2), `Exportify::Config.output_dir` (Task 1).
- Produces:
  - `Exportify::Library.playlist_dir(playlist_name) -> String | nil` — caminho absoluto da pasta da playlist, ou `nil` se `playlist_name` não existir em `Config.output_dir`. Usado pela Task 4.
  - `Exportify::Library.fallback_from_filename(filename) -> { artist: String, title: String }` — deriva artista/título do padrão `"Artista - Título.mp3"`. Usado pela Task 4.
  - `Exportify::Library.tracks(playlist_name) -> Array<{ filename:, title:, artist: }> | nil` — `nil` se a playlist não existir; senão lista ordenada por `track_number` (faixas sem número numérico vão para o fim, em ordem alfabética de arquivo).

- [ ] **Step 1: Escrever o teste que falha**

Adicione em `test/exportify/library_test.rb`:

```ruby
  def test_tracks_returns_nil_for_unknown_playlist
    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.tracks('Does Not Exist')
      end
    end
  end

  def test_tracks_lists_files_with_metadata
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'Queen - Bohemian Rhapsody.mp3'))

      tags = { title: 'Bohemian Rhapsody', artist: 'Queen', track_number: '1' }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, tags) do
          result = Exportify::Library.tracks('Rock')

          assert_equal(
            [{ filename: 'Queen - Bohemian Rhapsody.mp3', title: 'Bohemian Rhapsody', artist: 'Queen' }],
            result
          )
        end
      end
    end
  end

  def test_tracks_falls_back_to_filename_when_tags_missing
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'David Bowie - Heroes.mp3'))

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, nil) do
          result = Exportify::Library.tracks('Rock')

          assert_equal(
            [{ filename: 'David Bowie - Heroes.mp3', title: 'Heroes', artist: 'David Bowie' }],
            result
          )
        end
      end
    end
  end

  def test_tracks_sorted_by_track_number_with_missing_last
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'B - Second.mp3'))
      FileUtils.touch(File.join(playlist_dir, 'A - First.mp3'))
      FileUtils.touch(File.join(playlist_dir, 'Z - NoNumber.mp3'))

      by_filename = {
        'B - Second.mp3' => { track_number: '2' },
        'A - First.mp3' => { track_number: '1' },
        'Z - NoNumber.mp3' => {}
      }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, ->(filepath) { by_filename[File.basename(filepath)] }) do
          result = Exportify::Library.tracks('Rock')

          assert_equal ['A - First.mp3', 'B - Second.mp3', 'Z - NoNumber.mp3'], result.map { |t| t[:filename] }
        end
      end
    end
  end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/library_test.rb`
Expected: `NoMethodError: undefined method 'tracks' for module Exportify::Library`

- [ ] **Step 3: Implementar `tracks` e os helpers**

Em `lib/exportify/library.rb`, adicione (após `read_tags`):

```ruby
    def playlist_dir(playlist_name)
      root = File.expand_path(Config.output_dir)
      return nil unless Dir.exist?(root)
      return nil unless Dir.children(root).include?(playlist_name)

      File.join(root, playlist_name)
    end

    def fallback_from_filename(filename)
      base = File.basename(filename, '.mp3')
      artist, title = base.split(' - ', 2)
      { artist: artist || base, title: title || base }
    end

    def tracks(playlist_name)
      dir = playlist_dir(playlist_name)
      return nil unless dir

      Dir.glob(File.join(dir, '*.mp3'))
         .map { |filepath| track_summary(filepath) }
         .sort_by { |summary| [summary[:sort_key], summary[:filename]] }
         .each { |summary| summary.delete(:sort_key) }
    end

    def track_summary(filepath)
      filename = File.basename(filepath)
      tags     = read_tags(filepath)
      fallback = fallback_from_filename(filename)

      title  = tags && !tags[:title].to_s.strip.empty? ? tags[:title] : fallback[:title]
      artist = tags && !tags[:artist].to_s.strip.empty? ? tags[:artist] : fallback[:artist]
      number = tags && tags[:track_number].to_s[/\d+/]&.to_i

      { filename: filename, title: title, artist: artist, sort_key: number || Float::INFINITY }
    end
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/library_test.rb`
Expected: `11 runs, ... 0 failures, 0 errors`

- [ ] **Step 5: Commit**

```bash
git add lib/exportify/library.rb test/exportify/library_test.rb
git commit -m "feat: adicionar Exportify::Library.tracks"
```

---

## Task 4: `Exportify::Library.track`

**Files:**
- Modify: `lib/exportify/library.rb`
- Modify: `test/exportify/library_test.rb`

**Interfaces:**
- Consumes: `Exportify::Library.playlist_dir`, `Exportify::Library.read_tags`, `Exportify::Library.fallback_from_filename` (Tasks 2–3).
- Produces: `Exportify::Library.track(playlist_name, filename) -> Hash | nil`. Hash com chaves `:title, :artist, :all_artists, :album, :year, :track_number, :genre, :duration_seconds, :file_size_bytes`. Campos ausentes (exceto `title`/`artist`, que sempre têm fallback) vêm como `nil`. Retorna `nil` se a playlist ou o arquivo não existirem. Usado pela Task 7.

- [ ] **Step 1: Escrever o teste que falha**

Adicione em `test/exportify/library_test.rb`:

```ruby
  def test_track_returns_nil_for_unknown_playlist
    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.track('Unknown', 'song.mp3')
      end
    end
  end

  def test_track_returns_nil_for_unknown_file
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Rock'))

      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.track('Rock', 'missing.mp3')
      end
    end
  end

  def test_track_returns_full_metadata
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      filepath = File.join(playlist_dir, 'Queen - Bohemian Rhapsody.mp3')
      File.write(filepath, 'x' * 2048)

      tags = {
        title: 'Bohemian Rhapsody', artist: 'Queen', all_artists: 'Queen',
        album: 'A Night at the Opera', year: '1975', track_number: '1',
        genre: 'Rock', duration_seconds: 354.5
      }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, tags) do
          result = Exportify::Library.track('Rock', 'Queen - Bohemian Rhapsody.mp3')

          assert_equal 'Bohemian Rhapsody', result[:title]
          assert_equal 'A Night at the Opera', result[:album]
          assert_equal 354.5, result[:duration_seconds]
          assert_equal 2048, result[:file_size_bytes]
        end
      end
    end
  end

  def test_track_falls_back_when_tags_unavailable
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      filepath = File.join(playlist_dir, 'David Bowie - Heroes.mp3')
      FileUtils.touch(filepath)

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, nil) do
          result = Exportify::Library.track('Rock', 'David Bowie - Heroes.mp3')

          assert_equal 'Heroes', result[:title]
          assert_equal 'David Bowie', result[:artist]
          assert_nil result[:album]
          assert_nil result[:duration_seconds]
          assert_equal 0, result[:file_size_bytes]
        end
      end
    end
  end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/library_test.rb`
Expected: `NoMethodError: undefined method 'track' for module Exportify::Library`

- [ ] **Step 3: Implementar `track`**

Em `lib/exportify/library.rb`, adicione (após `track_summary`):

```ruby
    def track(playlist_name, filename)
      dir = playlist_dir(playlist_name)
      return nil unless dir
      return nil unless Dir.children(dir).include?(filename)

      filepath = File.join(dir, filename)
      tags     = read_tags(filepath)
      fallback = fallback_from_filename(filename)

      {
        title: presence(tags && tags[:title]) || fallback[:title],
        artist: presence(tags && tags[:artist]) || fallback[:artist],
        all_artists: presence(tags && tags[:all_artists]) || fallback[:artist],
        album: presence(tags && tags[:album]),
        year: presence(tags && tags[:year]),
        track_number: presence(tags && tags[:track_number]),
        genre: presence(tags && tags[:genre]),
        duration_seconds: tags && tags[:duration_seconds],
        file_size_bytes: File.size(filepath)
      }
    end

    def presence(value)
      value.to_s.strip.empty? ? nil : value
    end
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/library_test.rb`
Expected: `15 runs, ... 0 failures, 0 errors`

- [ ] **Step 5: Rodar rubocop**

Run: `bundle exec rubocop lib/exportify/library.rb test/exportify/library_test.rb`
Expected: `no offenses detected`

- [ ] **Step 6: Commit**

```bash
git add lib/exportify/library.rb test/exportify/library_test.rb
git commit -m "feat: adicionar Exportify::Library.track"
```

---

## Task 5: `Exportify::WebServer` — núcleo, página inicial e 404

**Files:**
- Create: `lib/exportify/web_server.rb`
- Create: `views/layout.html.erb`
- Create: `views/index.html.erb`
- Create: `views/not_found.html.erb`
- Create: `public/style.css`
- Test: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `Exportify::Library.playlists` (Task 1), `Exportify::Config.output_dir` (existente).
- Produces:
  - `Exportify::WebServer.build_server(port) -> WEBrick::HTTPServer` (configurado, sem chamar `.start`) — usado pelos testes e pela Task 8.
  - `Exportify::WebServer.start(port: 4567) -> void` — usado pela Task 8 (CLI).
  - `Exportify::WebServer.handle_request(req, res) -> void` — despacha rotas; nesta task só trata `'/'` e 404. Tasks 6 e 7 estendem o `case`.
  - `Exportify::WebServer::PUBLIC_DIR -> String` (caminho absoluto de `public/`).

- [ ] **Step 1: Escrever o teste que falha**

Crie `test/exportify/web_server_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'exportify/web_server'
require 'net/http'
require 'tmpdir'
require 'fileutils'

class WebServerTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def with_server
    Exportify::Config.stub(:output_dir, @dir) do
      server = Exportify::WebServer.build_server(0)
      thread = Thread.new { server.start }

      yield server.config[:Port]
    ensure
      server.shutdown
      thread&.join
    end
  end

  def test_get_root_lists_playlists
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_equal '200', response.code
      assert_includes response.body, 'Rock'
    end
  end

  def test_get_root_shows_empty_state_when_no_playlists
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_equal '200', response.code
      assert_includes response.body, 'exportify'
    end
  end

  def test_get_unknown_path_returns_404
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/does-not-exist"))

      assert_equal '404', response.code
    end
  end
end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/web_server_test.rb`
Expected: `LoadError: cannot load such file -- exportify/web_server`

- [ ] **Step 3: Criar a folha de estilo**

Crie `public/style.css`:

```css
* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: system-ui, -apple-system, sans-serif;
  background: #FAFAFA;
  color: #1A1A1A;
}

.container {
  max-width: 960px;
  margin: 0 auto;
  padding: 2rem 1.5rem;
}

a {
  color: #2563EB;
}

a:hover {
  color: #1D4ED8;
}

.breadcrumb {
  display: inline-block;
  margin-bottom: 1.5rem;
  text-decoration: none;
  font-size: 0.9rem;
}

.empty-state {
  text-align: center;
  color: #6B7280;
  padding: 4rem 1rem;
}

.empty-state code {
  background: #E5E7EB;
  padding: 0.2rem 0.4rem;
  border-radius: 4px;
  color: #1A1A1A;
}

.playlist-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 1rem;
}

.playlist-card {
  display: block;
  border: 1px solid #E5E7EB;
  border-radius: 8px;
  padding: 1.5rem;
  text-decoration: none;
  color: inherit;
  transition: border-color 0.15s ease;
}

.playlist-card:hover {
  border-color: #2563EB;
}

.playlist-card__icon {
  font-size: 2rem;
  color: #2563EB;
  margin-bottom: 0.5rem;
}

.playlist-card__name {
  font-weight: 600;
}

.playlist-card__count {
  color: #6B7280;
  font-size: 0.875rem;
}

.track-list {
  list-style: none;
  padding: 0;
  margin: 0;
  border-top: 1px solid #E5E7EB;
}

.track-list__item {
  border-bottom: 1px solid #E5E7EB;
}

.track-list__link {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.85rem 0.5rem;
  text-decoration: none;
  color: #1A1A1A;
}

.track-list__link:hover {
  background: #F3F4F6;
}

.track-list__artist {
  color: #6B7280;
}

.track-detail__title {
  font-size: 1.5rem;
  margin-bottom: 0.25rem;
}

.track-detail__artist {
  color: #2563EB;
  font-weight: 500;
  margin: 0 0 1.5rem;
}

.track-detail__player {
  width: 100%;
  margin-bottom: 2rem;
}

.track-meta {
  list-style: none;
  padding: 0;
  margin: 0;
}

.track-meta__row {
  display: flex;
  justify-content: space-between;
  padding: 0.6rem 0;
  border-bottom: 1px solid #E5E7EB;
}

.track-meta__label {
  color: #6B7280;
}

.track-meta__value {
  font-weight: 500;
}

.not-found {
  text-align: center;
  color: #6B7280;
  padding: 4rem 1rem;
}
```

- [ ] **Step 4: Criar os templates**

Crie `views/layout.html.erb`:

```erb
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Exportify</title>
<link rel="stylesheet" href="/assets/style.css">
<script src="https://unpkg.com/@hotwired/turbo@8.0.23/dist/turbo.es2017-umd.js"
        integrity="sha384-2ePXINFSJiSCWUJkjFJGYdr2kyM132s7uBi9k+JISp4P+AjN9DXn4H/1enWEHu36"
        crossorigin="anonymous"></script>
</head>
<body>
<main class="container">
<%= content %>
</main>
</body>
</html>
```

Crie `views/index.html.erb`:

```erb
<% if playlists.empty? %>
  <div class="empty-state">
    <p>Nenhuma playlist baixada ainda.</p>
    <p>Use <code>bin/exportify &lt;url_da_playlist&gt;</code> para baixar uma.</p>
  </div>
<% else %>
  <div class="playlist-grid">
    <% playlists.each do |playlist| %>
      <a class="playlist-card" href="/playlists/<%= ERB::Util.url_encode(playlist[:name]) %>">
        <div class="playlist-card__icon">&#9835;</div>
        <div class="playlist-card__name"><%= playlist[:name] %></div>
        <div class="playlist-card__count"><%= playlist[:track_count] %> faixas</div>
      </a>
    <% end %>
  </div>
<% end %>
```

Crie `views/not_found.html.erb`:

```erb
<div class="not-found">
  <p><%= message %></p>
  <p><a href="/">&larr; Voltar para playlists</a></p>
</div>
```

- [ ] **Step 5: Implementar `Exportify::WebServer`**

Crie `lib/exportify/web_server.rb`:

```ruby
# frozen_string_literal: true

require 'webrick'
require 'erb'
require 'uri'
require_relative 'library'
require_relative 'config'

module Exportify
  module WebServer
    ROOT_DIR   = File.expand_path('../..', __dir__)
    VIEWS_DIR  = File.join(ROOT_DIR, 'views')
    PUBLIC_DIR = File.join(ROOT_DIR, 'public')

    module_function

    def start(port: 4567)
      server = build_server(port)

      trap('INT') { server.shutdown }
      puts "Servidor rodando em http://localhost:#{server.config[:Port]}"
      server.start
    end

    def build_server(port)
      server = WEBrick::HTTPServer.new(Port: port, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])

      server.mount('/library', WEBrick::HTTPServlet::FileHandler, File.expand_path(Config.output_dir))
      server.mount('/assets', WEBrick::HTTPServlet::FileHandler, PUBLIC_DIR)
      server.mount_proc('/') { |req, res| handle_request(req, res) }

      server
    end

    def handle_request(req, res)
      case req.path
      when '/'
        render_index(res)
      else
        render_not_found(res)
      end
    end

    def render_index(res)
      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template('index', playlists: Library.playlists)
    end

    def render_not_found(res, message = 'Página não encontrada.')
      res.status = 404
      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template('not_found', message: message)
    end

    def render_template(name, locals)
      content = render_erb("#{name}.html.erb", locals)
      render_erb('layout.html.erb', locals.merge(content: content))
    end

    def render_erb(filename, locals)
      path    = File.join(VIEWS_DIR, filename)
      context = TemplateContext.new(locals)
      ERB.new(File.read(path), trim_mode: '-').result(context.get_binding)
    end

    class TemplateContext
      def initialize(locals)
        locals.each_key do |key|
          instance_variable_set(:"@#{key}", locals[key])
          define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        end
      end

      def get_binding
        binding
      end
    end
  end
end
```

- [ ] **Step 6: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/web_server_test.rb`
Expected: `3 runs, ... 0 failures, 0 errors`

- [ ] **Step 7: Rodar rubocop**

Run: `bundle exec rubocop lib/exportify/web_server.rb test/exportify/web_server_test.rb`
Expected: `no offenses detected`

- [ ] **Step 8: Commit**

```bash
git add lib/exportify/web_server.rb views/layout.html.erb views/index.html.erb views/not_found.html.erb \
        public/style.css test/exportify/web_server_test.rb
git commit -m "feat: adicionar Exportify::WebServer com página inicial e 404"
```

---

## Task 6: Rota de faixas da playlist (`/playlists/:nome`)

**Files:**
- Modify: `lib/exportify/web_server.rb`
- Create: `views/playlist.html.erb`
- Modify: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `Exportify::Library.tracks(playlist_name) -> Array | nil` (Task 3), `Exportify::WebServer.render_template`/`render_not_found` (Task 5).
- Produces: rota `GET /playlists/:nome` funcional; `Exportify::WebServer.render_playlist(res, name)`.

- [ ] **Step 1: Escrever o teste que falha**

Adicione em `test/exportify/web_server_test.rb`:

```ruby
  def test_get_playlist_lists_tracks
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock"))

      assert_equal '200', response.code
      assert_includes response.body, 'Bohemian Rhapsody'
    end
  end

  def test_get_unknown_playlist_returns_404
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Unknown"))

      assert_equal '404', response.code
    end
  end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/web_server_test.rb`
Expected: `test_get_playlist_lists_tracks` falha com `404` em vez de `200` (a rota cai no `else` de `handle_request`, que hoje só conhece `/`)

- [ ] **Step 3: Criar o template**

Crie `views/playlist.html.erb`:

```erb
<a class="breadcrumb" href="/">&larr; Playlists</a>
<h1><%= playlist_name %></h1>
<ul class="track-list">
  <% tracks.each do |track| %>
    <li class="track-list__item">
      <a class="track-list__link"
         href="/playlists/<%= ERB::Util.url_encode(playlist_name) %>/faixas/<%= ERB::Util.url_encode(track[:filename]) %>">
        <span><%= track[:title] %></span>
        <span class="track-list__artist"><%= track[:artist] %></span>
      </a>
    </li>
  <% end %>
</ul>
```

- [ ] **Step 4: Adicionar a rota**

Em `lib/exportify/web_server.rb`, atualize `handle_request`:

```ruby
    def handle_request(req, res)
      case req.path
      when '/'
        render_index(res)
      when %r{\A/playlists/([^/]+)\z}
        render_playlist(res, URI.decode_www_form_component(Regexp.last_match(1)))
      else
        render_not_found(res)
      end
    end
```

E adicione (após `render_index`):

```ruby
    def render_playlist(res, name)
      tracks = Library.tracks(name)
      return render_not_found(res, 'Playlist não encontrada.') unless tracks

      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template('playlist', playlist_name: name, tracks: tracks)
    end
```

- [ ] **Step 5: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/web_server_test.rb`
Expected: `5 runs, ... 0 failures, 0 errors`

- [ ] **Step 6: Commit**

```bash
git add lib/exportify/web_server.rb views/playlist.html.erb test/exportify/web_server_test.rb
git commit -m "feat: adicionar rota de faixas da playlist"
```

---

## Task 7: Rota de detalhes da faixa (`/playlists/:nome/faixas/:arquivo`)

**Files:**
- Modify: `lib/exportify/web_server.rb`
- Create: `views/track.html.erb`
- Modify: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `Exportify::Library.track(playlist_name, filename) -> Hash | nil` (Task 4).
- Produces: rota `GET /playlists/:nome/faixas/:arquivo` funcional; `Exportify::WebServer.render_track(res, playlist_name, filename)`, `Exportify::WebServer.format_duration(seconds) -> String`, `Exportify::WebServer.format_file_size(bytes) -> String`.

- [ ] **Step 1: Escrever o teste que falha**

Adicione em `test/exportify/web_server_test.rb`:

```ruby
  def test_format_duration_formats_minutes_and_seconds
    assert_equal '5:54', Exportify::WebServer.format_duration(354.4)
  end

  def test_format_duration_returns_dash_for_nil
    assert_equal '—', Exportify::WebServer.format_duration(nil)
  end

  def test_format_file_size_formats_kilobytes
    assert_equal '2.0 KB', Exportify::WebServer.format_file_size(2048)
  end

  def test_format_file_size_formats_megabytes
    assert_equal '2.0 MB', Exportify::WebServer.format_file_size(2 * 1_048_576)
  end

  def test_format_file_size_returns_dash_for_nil
    assert_equal '—', Exportify::WebServer.format_file_size(nil)
  end

  def test_get_track_shows_details_and_player
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      url = URI("http://127.0.0.1:#{port}/playlists/Rock/faixas/Queen%20-%20Bohemian%20Rhapsody.mp3")
      response = Net::HTTP.get_response(url)

      assert_equal '200', response.code
      assert_includes response.body, 'Bohemian Rhapsody'
      assert_includes response.body, '<audio'
    end
  end

  def test_get_unknown_track_returns_404
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock/faixas/missing.mp3"))

      assert_equal '404', response.code
    end
  end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/web_server_test.rb`
Expected: `NoMethodError: undefined method 'format_duration' for module Exportify::WebServer`

- [ ] **Step 3: Criar o template**

Crie `views/track.html.erb`:

```erb
<a class="breadcrumb" href="/playlists/<%= ERB::Util.url_encode(playlist_name) %>">&larr; <%= playlist_name %></a>
<h1 class="track-detail__title"><%= track[:title] %></h1>
<p class="track-detail__artist"><%= track[:artist] %></p>

<audio class="track-detail__player" controls
       src="/library/<%= ERB::Util.url_encode(playlist_name) %>/<%= ERB::Util.url_encode(filename) %>"></audio>

<ul class="track-meta">
  <li class="track-meta__row">
    <span class="track-meta__label">Álbum</span>
    <span class="track-meta__value"><%= track[:album] || '—' %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Ano</span>
    <span class="track-meta__value"><%= track[:year] || '—' %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Faixa nº</span>
    <span class="track-meta__value"><%= track[:track_number] || '—' %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Gênero</span>
    <span class="track-meta__value"><%= track[:genre] || '—' %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Duração</span>
    <span class="track-meta__value"><%= duration %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Tamanho</span>
    <span class="track-meta__value"><%= file_size %></span>
  </li>
</ul>
```

- [ ] **Step 4: Adicionar a rota e os formatadores**

Em `lib/exportify/web_server.rb`, atualize `handle_request`:

```ruby
    def handle_request(req, res)
      case req.path
      when '/'
        render_index(res)
      when %r{\A/playlists/([^/]+)/faixas/([^/]+)\z}
        render_track(
          res,
          URI.decode_www_form_component(Regexp.last_match(1)),
          URI.decode_www_form_component(Regexp.last_match(2))
        )
      when %r{\A/playlists/([^/]+)\z}
        render_playlist(res, URI.decode_www_form_component(Regexp.last_match(1)))
      else
        render_not_found(res)
      end
    end
```

E adicione (após `render_playlist`):

```ruby
    def render_track(res, playlist_name, filename)
      track = Library.track(playlist_name, filename)
      return render_not_found(res, 'Faixa não encontrada.') unless track

      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template(
        'track',
        playlist_name: playlist_name,
        filename: filename,
        track: track,
        duration: format_duration(track[:duration_seconds]),
        file_size: format_file_size(track[:file_size_bytes])
      )
    end

    def format_duration(seconds)
      return '—' unless seconds

      total = seconds.round
      format('%d:%02d', total / 60, total % 60)
    end

    def format_file_size(bytes)
      return '—' unless bytes

      if bytes >= 1_048_576
        format('%.1f MB', bytes / 1_048_576.0)
      else
        format('%.1f KB', bytes / 1024.0)
      end
    end
```

- [ ] **Step 5: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/web_server_test.rb`
Expected: `12 runs, ... 0 failures, 0 errors`

- [ ] **Step 6: Rodar rubocop**

Run: `bundle exec rubocop lib/exportify/web_server.rb test/exportify/web_server_test.rb`
Expected: `no offenses detected`

- [ ] **Step 7: Commit**

```bash
git add lib/exportify/web_server.rb views/track.html.erb test/exportify/web_server_test.rb
git commit -m "feat: adicionar rota de detalhes da faixa com player de audio"
```

---

## Task 8: Subcomando `bin/exportify web`

**Files:**
- Modify: `lib/exportify/cli.rb`
- Modify: `test/exportify/cli_test.rb`
- Modify: `exportify.gemspec`
- Modify: `README.md`

**Interfaces:**
- Consumes: `Exportify::WebServer.start(port:) -> void` (Task 5).
- Produces: `exportify web [--port PORTA]` funcional via `bin/exportify`.

- [ ] **Step 1: Escrever o teste que falha**

Adicione em `test/exportify/cli_test.rb` (no topo do arquivo, adicionar require; no corpo da classe, os testes):

```ruby
require 'exportify/web_server'
```

```ruby
  def test_web_subcommand_starts_server_with_default_port
    called_with = nil

    Exportify::WebServer.stub(:start, ->(port:) { called_with = port }) do
      Exportify::CLI.run(['web'])
    end

    assert_equal 4567, called_with
  end

  def test_web_subcommand_accepts_custom_port
    called_with = nil

    Exportify::WebServer.stub(:start, ->(port:) { called_with = port }) do
      Exportify::CLI.run(['web', '--port', '8080'])
    end

    assert_equal 8080, called_with
  end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: `assert_equal 4567, called_with` falha (`called_with` continua `nil`, pois `exportify web` hoje cai no fluxo normal do Spotify e aborta por falta de URL válida)

- [ ] **Step 3: Implementar o subcomando**

Em `lib/exportify/cli.rb`, no início do método `run`, adicione a nova ramificação (logo abaixo da linha de `init`):

```ruby
    def run(argv)
      return run_init(argv[1]) if argv[0] == 'init'
      return run_web(argv[1..]) if argv[0] == 'web'

      retag = false
```

Atualize o `banner` dentro do `OptionParser.new do |opts| ... end` para mencionar o novo subcomando:

```ruby
        opts.banner = "Usage:\n  " \
                      "exportify init\n  " \
                      "exportify web [--port PORTA]\n  " \
                      'exportify <spotify_playlist_url> [--retag] [--sync]'
```

Adicione o novo método (após `run_init`, antes de `open_tty`):

```ruby
    def run_web(argv)
      port = 4567

      OptionParser.new do |opts|
        opts.banner = 'Usage: exportify web [--port PORTA]'
        opts.on('--port PORTA', Integer, 'Porta do servidor (padrão: 4567)') { |value| port = value }
      end.parse!(argv)

      require_relative 'web_server'
      WebServer.start(port: port)
    end
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `bundle exec ruby -Ilib -Itest test/exportify/cli_test.rb`
Expected: `... 0 failures, 0 errors`

- [ ] **Step 5: Rodar a suíte completa e o rubocop**

Run: `bundle exec rake test`
Expected: todos os testes passam (incluindo os das Tasks 1–7)

Run: `bundle exec rubocop`
Expected: `no offenses detected`

- [ ] **Step 6: Atualizar o gemspec para empacotar views/ e public/**

Em `exportify.gemspec`, atualize a linha `spec.files`:

```ruby
  spec.files         = Dir['lib/**/*.rb', 'bin/*', 'views/**/*.erb', 'public/**/*', 'README.md', 'exportify.gemspec']
```

- [ ] **Step 7: Atualizar o README**

Em `README.md`, adicione uma nova seção antes de `## Desenvolvimento` (após a seção `### Regravar tags ID3`):

```md
### Visualizar playlists baixadas (app web)

Para navegar pelas playlists e músicas já baixadas em um painel web:

\`\`\`sh
bin/exportify web
\`\`\`

Abre um servidor local em `http://localhost:4567` com a lista de playlists,
as faixas de cada uma e os detalhes (tags ID3, duração, tamanho) com player
de áudio. Para usar outra porta:

\`\`\`sh
bin/exportify web --port 8080
\`\`\`

> App somente leitura — os downloads continuam sendo feitos via CLI
> (`bin/exportify <url>`).
```

- [ ] **Step 8: Commit**

```bash
git add lib/exportify/cli.rb test/exportify/cli_test.rb exportify.gemspec README.md
git commit -m "feat: adicionar subcomando 'exportify web'"
```

---

## Verificação manual final

Após a Task 8, suba o servidor de verdade contra a pasta `musics/` real do projeto e confira no navegador:

```bash
bin/exportify web
```

- Abrir `http://localhost:4567/` e ver os cards de playlists.
- Clicar em uma playlist e ver a lista de faixas.
- Clicar em uma faixa e ouvir o player de áudio, com os metadados corretos.
- Testar uma URL de playlist/arquivo inexistente e confirmar a página 404.

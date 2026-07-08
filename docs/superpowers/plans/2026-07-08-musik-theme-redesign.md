# Reestilizar o app web no tema Musik — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reestilizar as 4 páginas do app web do Exportify (`/`, `/playlists/:nome`, `/playlists/:nome/faixas/:arquivo`, 404) no visual do tema ThemeForest "Musik" — sidebar escura fixa, cards com capa gerada, lista numerada estilo "Charts", coluna de gêneros — e adicionar dark mode (localStorage) e busca/filtro local (JS puro).

**Architecture:** Camada web pura (sem novas gems): `lib/exportify/cover.rb` gera capas por hash determinístico; `Library.genres` extrai gêneros das tags ID3; `WebServer::TemplateContext` ganha `render_partial` para compor `layout.html.erb` com parciais de sidebar/topbar; `public/style.css` e `public/app.js` (novo) entregam o visual e a interatividade (dark mode, busca, filtro por gênero), com Turbo Drive já carregado exigindo o evento `turbo:load` em vez de `DOMContentLoaded`.

**Tech Stack:** Ruby 3.3 + WEBrick + ERB (sem build step), CSS puro com custom properties, JavaScript vanilla (sem framework), Minitest.

## Global Constraints

- `TargetRubyVersion: 3.3`, `Layout/LineLength Max: 120`, aspas simples (`Style/StringLiterals`), `# frozen_string_literal: true` obrigatório em todo arquivo `.rb` novo (ver `.rubocop.yml`).
- Nenhuma gem nova — usar só stdlib (`digest`, já disponível).
- Turbo Drive é carregado via CDN em `layout.html.erb`; qualquer JS que precise rodar em toda navegação deve escutar `turbo:load`, não `DOMContentLoaded` (Turbo substitui só o `<body>` entre navegações, então `DOMContentLoaded` não dispara de novo).
- Views ERB não usam nenhum helper de asset pipeline — `Exportify::Cover` é referenciado diretamente como `Exportify::Cover.for(...)` dentro do `.erb`, exigindo `require_relative 'cover'` em `lib/exportify/web_server.rb`.
- Testes existentes em `test/exportify/web_server_test.rb` e `test/exportify/library_test.rb` checam texto puro no corpo da resposta HTTP — nenhuma mudança pode remover esse texto (nomes de playlist, título de faixa, `<audio`, etc.).
- Rodar `bundle exec rake test` e `bundle exec rubocop` ao final de cada task que toca `.rb`.

---

### Task 1: `Exportify::Cover` — capas geradas por hash

**Files:**
- Create: `lib/exportify/cover.rb`
- Test: `test/exportify/cover_test.rb`

**Interfaces:**
- Produces: `Exportify::Cover.for(text) -> { from: "#RRGGBB", to: "#RRGGBB", initial: "X" }`, determinístico por `text`.

- [ ] **Step 1: Escrever o teste (vai falhar, arquivo ainda não existe)**

```ruby
# test/exportify/cover_test.rb
# frozen_string_literal: true

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
```

Adicione `require 'test_helper'` como primeira linha do arquivo (padrão dos outros testes) — o snippet acima omite por brevidade, mas o arquivo final deve começar com:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'exportify/cover'

class CoverTest < Minitest::Test
  # ... (métodos acima)
end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec rake test TEST=test/exportify/cover_test.rb`
Expected: FAIL com `LoadError: cannot load such file -- exportify/cover`

- [ ] **Step 3: Implementar `Exportify::Cover`**

```ruby
# lib/exportify/cover.rb
# frozen_string_literal: true

require 'digest'

module Exportify
  module Cover
    module_function

    PALETTE = [
      %w[#F97316 #FACC15],
      %w[#EC4899 #8B5CF6],
      %w[#06B6D4 #3B82F6],
      %w[#10B981 #A3E635],
      %w[#EF4444 #F97316],
      %w[#8B5CF6 #6366F1],
      %w[#F43F5E #FB923C],
      %w[#14B8A6 #22D3EE]
    ].freeze

    def for(text)
      key = text.to_s
      hash = Digest::MD5.hexdigest(key).to_i(16)
      from, to = PALETTE[hash % PALETTE.size]
      { from: from, to: to, initial: initial_for(key) }
    end

    def initial_for(text)
      letter = text.strip[0]
      letter ? letter.upcase : '♪'
    end
  end
end
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `bundle exec rake test TEST=test/exportify/cover_test.rb`
Expected: PASS (5 exemplos, 0 falhas)

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop lib/exportify/cover.rb test/exportify/cover_test.rb`
Expected: `no offenses detected`

- [ ] **Step 6: Commit**

```bash
git add lib/exportify/cover.rb test/exportify/cover_test.rb
git commit -m "Adicionar Exportify::Cover para gerar capas por hash determinístico"
```

---

### Task 2: `Library.genres` + gênero por faixa

**Files:**
- Modify: `lib/exportify/library.rb`
- Modify: `test/exportify/library_test.rb`

**Interfaces:**
- Consumes: `Library.playlist_dir`, `Library.read_tags`, `Library.presence` (já existentes)
- Produces: `Exportify::Library.genres(playlist_name) -> Array<String>` (únicos, ordenados, sem vazios); `Library.tracks(playlist_name)` passa a incluir a chave `:genre` (String ou `nil`) em cada item.

- [ ] **Step 1: Escrever os testes de `genres` (vão falhar, método não existe)**

Adicionar ao final de `test/exportify/library_test.rb`, antes do `end` da classe:

```ruby
  def test_genres_returns_unique_sorted_non_empty_genres
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'A.mp3'))
      FileUtils.touch(File.join(playlist_dir, 'B.mp3'))
      FileUtils.touch(File.join(playlist_dir, 'C.mp3'))

      by_filename = {
        'A.mp3' => { genre: 'Rock' },
        'B.mp3' => { genre: 'Pop' },
        'C.mp3' => { genre: 'Rock' }
      }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, ->(filepath) { by_filename[File.basename(filepath)] }) do
          assert_equal ['Pop', 'Rock'], Exportify::Library.genres('Rock')
        end
      end
    end
  end

  def test_genres_ignores_missing_or_blank_genre_tags
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'A.mp3'))
      FileUtils.touch(File.join(playlist_dir, 'B.mp3'))

      by_filename = { 'A.mp3' => { genre: '' }, 'B.mp3' => nil }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, ->(filepath) { by_filename[File.basename(filepath)] }) do
          assert_equal [], Exportify::Library.genres('Rock')
        end
      end
    end
  end

  def test_genres_returns_empty_array_for_unknown_playlist
    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        assert_equal [], Exportify::Library.genres('Unknown')
      end
    end
  end
```

- [ ] **Step 2: Rodar e confirmar falha**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Expected: FAIL com `NoMethodError: undefined method 'genres'`

- [ ] **Step 3: Implementar `Library.genres`**

Adicionar em `lib/exportify/library.rb`, logo após o método `tracks` (depois da linha `.each { |summary| summary.delete(:sort_key) }` e seu `end`):

```ruby
    def genres(playlist_name)
      dir = playlist_dir(playlist_name)
      return [] unless dir

      Dir.glob(File.join(dir, '*.mp3')).filter_map do |filepath|
        tags = read_tags(filepath)
        presence(tags && tags[:genre])
      end.uniq.sort
    end
```

- [ ] **Step 4: Rodar e confirmar que os 3 testes novos passam**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Expected: PASS nos 3 testes de `genres`; os testes de `tracks`/`track_summary` que checam igualdade exata de hash ainda vão FALHAR neste ponto (serão corrigidos no próximo passo).

- [ ] **Step 5: Adicionar `genre` a `track_summary` e atualizar os testes existentes que checam o hash completo**

Em `lib/exportify/library.rb`, substituir:

```ruby
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

por:

```ruby
    def track_summary(filepath)
      filename = File.basename(filepath)
      tags     = read_tags(filepath)
      fallback = fallback_from_filename(filename)

      title  = tags && !tags[:title].to_s.strip.empty? ? tags[:title] : fallback[:title]
      artist = tags && !tags[:artist].to_s.strip.empty? ? tags[:artist] : fallback[:artist]
      number = tags && tags[:track_number].to_s[/\d+/]&.to_i
      genre  = presence(tags && tags[:genre])

      { filename: filename, title: title, artist: artist, genre: genre, sort_key: number || Float::INFINITY }
    end
```

Em `test/exportify/library_test.rb`, atualizar `test_tracks_lists_files_with_metadata`, trocando:

```ruby
          assert_equal(
            [{ filename: 'Queen - Bohemian Rhapsody.mp3', title: 'Bohemian Rhapsody', artist: 'Queen' }],
            result
          )
```

por:

```ruby
          assert_equal(
            [{ filename: 'Queen - Bohemian Rhapsody.mp3', title: 'Bohemian Rhapsody', artist: 'Queen', genre: nil }],
            result
          )
```

E `test_tracks_falls_back_to_filename_when_tags_missing`, trocando:

```ruby
          assert_equal(
            [{ filename: 'David Bowie - Heroes.mp3', title: 'Heroes', artist: 'David Bowie' }],
            result
          )
```

por:

```ruby
          assert_equal(
            [{ filename: 'David Bowie - Heroes.mp3', title: 'Heroes', artist: 'David Bowie', genre: nil }],
            result
          )
```

E adicionar um teste novo dedicado ao campo `genre` (logo após `test_tracks_lists_files_with_metadata`):

```ruby
  def test_tracks_includes_genre_from_tags
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      FileUtils.touch(File.join(playlist_dir, 'Queen - Bohemian Rhapsody.mp3'))

      tags = { title: 'Bohemian Rhapsody', artist: 'Queen', track_number: '1', genre: 'Rock' }

      Exportify::Config.stub(:output_dir, dir) do
        Exportify::Library.stub(:read_tags, tags) do
          result = Exportify::Library.tracks('Rock')

          assert_equal 'Rock', result.first[:genre]
        end
      end
    end
  end
```

- [ ] **Step 6: Rodar toda a suíte de `library_test.rb` e confirmar que passa**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Expected: PASS em todos os testes (inclui os 3 de `genres` + os atualizados de `tracks`)

- [ ] **Step 7: Lint**

Run: `bundle exec rubocop lib/exportify/library.rb test/exportify/library_test.rb`
Expected: `no offenses detected`

- [ ] **Step 8: Commit**

```bash
git add lib/exportify/library.rb test/exportify/library_test.rb
git commit -m "Adicionar Library.genres e incluir gênero em track_summary"
```

---

### Task 3: `render_partial` + parciais de sidebar/topbar + novo `layout.html.erb`

**Files:**
- Modify: `lib/exportify/web_server.rb`
- Create: `views/_sidebar.html.erb`
- Create: `views/_topbar.html.erb`
- Modify: `views/layout.html.erb`
- Modify: `test/exportify/web_server_test.rb`

**Interfaces:**
- Produces: `TemplateContext#render_partial(name)` (renderiza `views/_<name>.html.erb` com os mesmos locals da página); markup `.app-shell` > `.sidebar` + `.main` > (`.topbar` + `.page-content`); elementos `#theme-toggle`, `#fullscreen-toggle`, `#search-input`.

- [ ] **Step 1: Escrever o teste (vai falhar, sidebar ainda não existe)**

Adicionar em `test/exportify/web_server_test.rb`, logo após `test_get_root_lists_playlists`:

```ruby
  def test_get_root_renders_sidebar_and_topbar
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_includes response.body, 'class="sidebar"'
      assert_includes response.body, 'id="search-input"'
    end
  end
```

- [ ] **Step 2: Rodar e confirmar falha**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: FAIL — `response.body` não contém `class="sidebar"`

- [ ] **Step 3: Adicionar `require_relative 'cover'` e `render_partial` em `web_server.rb`**

Substituir o topo do arquivo:

```ruby
require 'webrick'
require 'erb'
require 'uri'
require_relative 'library'
require_relative 'config'
```

por:

```ruby
require 'webrick'
require 'erb'
require 'uri'
require_relative 'library'
require_relative 'config'
require_relative 'cover'
```

Substituir a classe `TemplateContext`:

```ruby
    class TemplateContext
      def initialize(locals)
        locals.each_key do |key|
          instance_variable_set(:"@#{key}", locals[key])
          define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        end
      end

      def template_binding
        binding
      end
    end
```

por:

```ruby
    class TemplateContext
      def initialize(locals)
        @locals = locals
        locals.each_key do |key|
          instance_variable_set(:"@#{key}", locals[key])
          define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        end
      end

      def template_binding
        binding
      end

      def render_partial(name)
        WebServer.render_erb("_#{name}.html.erb", @locals)
      end
    end
```

- [ ] **Step 4: Criar `views/_sidebar.html.erb`**

```erb
<nav class="sidebar">
  <a class="sidebar__logo" href="/">&#9835; Exportify</a>

  <div class="sidebar__nav">
    <a class="sidebar__nav-item" href="/">Playlists</a>
  </div>

  <div class="sidebar__section">
    <span class="sidebar__section-title">Configurações</span>

    <button type="button" class="sidebar__toggle" id="theme-toggle" aria-pressed="false">
      <span>Tema escuro</span>
      <span class="switch" aria-hidden="true"></span>
    </button>

    <button type="button" class="sidebar__toggle" id="fullscreen-toggle">
      <span>Tela cheia</span>
    </button>
  </div>

  <div class="sidebar__footer">
    <a href="https://github.com/caiovitorsantos/exportify" target="_blank" rel="noopener">GitHub</a>
  </div>
</nav>
```

- [ ] **Step 5: Criar `views/_topbar.html.erb`**

```erb
<header class="topbar">
  <input type="search" id="search-input" class="topbar__search" placeholder="Buscar..." autocomplete="off">
</header>
```

- [ ] **Step 6: Reescrever `views/layout.html.erb`**

```erb
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Exportify</title>
<script>
(function () {
  var theme = 'light';
  try { theme = localStorage.getItem('exportify-theme') || 'light'; } catch (e) { /* modo privado */ }
  document.documentElement.dataset.theme = theme;
})();
</script>
<link rel="stylesheet" href="/assets/style.css">
<script src="https://unpkg.com/@hotwired/turbo@8.0.23/dist/turbo.es2017-umd.js"
        integrity="sha384-2ePXINFSJiSCWUJkjFJGYdr2kyM132s7uBi9k+JISp4P+AjN9DXn4H/1enWEHu36"
        crossorigin="anonymous"></script>
</head>
<body>
<div class="app-shell">
<%= render_partial('sidebar') %>
<div class="main">
<%= render_partial('topbar') %>
<main class="page-content">
<%= content %>
</main>
</div>
</div>
<script src="/assets/app.js"></script>
</body>
</html>
```

- [ ] **Step 7: Rodar toda a suíte de `web_server_test.rb` e confirmar que passa**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: PASS em todos os testes, incluindo o novo `test_get_root_renders_sidebar_and_topbar`. O `<script src="/assets/app.js">` vai gerar um 404 real de navegador (ainda não existe), mas isso não quebra nenhum teste HTTP atual — será resolvido na Task 5.

- [ ] **Step 8: Lint**

Run: `bundle exec rubocop lib/exportify/web_server.rb test/exportify/web_server_test.rb`
Expected: `no offenses detected`

- [ ] **Step 9: Commit**

```bash
git add lib/exportify/web_server.rb views/_sidebar.html.erb views/_topbar.html.erb views/layout.html.erb test/exportify/web_server_test.rb
git commit -m "Adicionar sidebar/topbar e render_partial ao layout"
```

---

### Task 4: `public/style.css` — sistema visual completo

**Files:**
- Modify: `public/style.css` (reescrita completa)
- Modify: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: markup da Task 3 (`.sidebar`, `.topbar`, `#theme-toggle[aria-pressed]`, `.switch`)
- Produces: contrato de classes CSS que as Tasks 6-8 vão usar nas views: `.cover`, `.cover--card`, `.cover--sm`, `.cover--lg`, `.playlist-grid`, `.playlist-card*`, `.chart-list*`, `.playlist-layout`, `.aside*`, `.genre-pill*`; variáveis de tema `[data-theme="dark"]`.

- [ ] **Step 1: Escrever um teste de regressão para a rota de assets (a rota já existe, isso trava o comportamento antes da reescrita do CSS)**

Adicionar em `test/exportify/web_server_test.rb`:

```ruby
  def test_get_style_css_is_served
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/assets/style.css"))

      assert_equal '200', response.code
    end
  end
```

- [ ] **Step 2: Rodar e confirmar que já passa (regressão, não há mudança de rota)**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb -n test_get_style_css_is_served`
Expected: PASS (a rota `/assets/*` já existe desde antes; este teste apenas trava o comportamento antes da reescrita do CSS)

- [ ] **Step 3: Substituir todo o conteúdo de `public/style.css`**

```css
* {
  box-sizing: border-box;
}

:root {
  --bg: #FAFAFA;
  --text: #1A1A1A;
  --text-secondary: #6B7280;
  --accent: #2563EB;
  --accent-hover: #1D4ED8;
  --border: #E5E7EB;
  --surface: #FFFFFF;
  --sidebar-bg: #0E0E12;
  --sidebar-text: #F5F5F5;
  --sidebar-text-secondary: #9CA3AF;
}

:root[data-theme="dark"] {
  --bg: #121214;
  --text: #F5F5F5;
  --text-secondary: #9CA3AF;
  --accent: #3B82F6;
  --accent-hover: #60A5FA;
  --border: #26262C;
  --surface: #1A1A1F;
}

body {
  margin: 0;
  font-family: system-ui, -apple-system, sans-serif;
  background: var(--bg);
  color: var(--text);
}

a {
  color: var(--accent);
}

a:hover {
  color: var(--accent-hover);
}

.app-shell {
  display: grid;
  grid-template-columns: 240px 1fr;
  min-height: 100vh;
}

.main {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.page-content {
  padding: 2rem;
  max-width: 1100px;
  width: 100%;
}

.sidebar {
  background: var(--sidebar-bg);
  color: var(--sidebar-text);
  padding: 1.5rem 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 2rem;
}

.sidebar__logo {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--sidebar-text);
  text-decoration: none;
}

.sidebar__nav {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.sidebar__nav-item {
  color: var(--sidebar-text-secondary);
  text-decoration: none;
  padding: 0.5rem 0.6rem;
  border-radius: 6px;
  font-size: 0.95rem;
}

.sidebar__nav-item:hover {
  background: rgba(255, 255, 255, 0.06);
  color: var(--sidebar-text);
}

.sidebar__section {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.sidebar__section-title {
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--sidebar-text-secondary);
  margin-bottom: 0.25rem;
}

.sidebar__toggle {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: none;
  border: none;
  color: var(--sidebar-text-secondary);
  font: inherit;
  font-size: 0.9rem;
  padding: 0.4rem 0.1rem;
  cursor: pointer;
  text-align: left;
}

.sidebar__toggle:hover {
  color: var(--sidebar-text);
}

.switch {
  width: 32px;
  height: 18px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.15);
  position: relative;
  flex-shrink: 0;
}

.switch::after {
  content: '';
  position: absolute;
  top: 2px;
  left: 2px;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: var(--sidebar-text);
  transition: transform 0.15s ease;
}

.sidebar__toggle[aria-pressed="true"] .switch {
  background: var(--accent);
}

.sidebar__toggle[aria-pressed="true"] .switch::after {
  transform: translateX(14px);
}

.sidebar__footer {
  margin-top: auto;
  font-size: 0.8rem;
}

.sidebar__footer a {
  color: var(--sidebar-text-secondary);
}

.sidebar__footer a:hover {
  color: var(--sidebar-text);
}

.topbar {
  padding: 1.25rem 2rem 0;
}

.topbar__search {
  width: 100%;
  max-width: 360px;
  padding: 0.6rem 0.9rem;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--text);
  font: inherit;
}

.breadcrumb {
  display: inline-block;
  margin-bottom: 1.5rem;
  text-decoration: none;
  font-size: 0.9rem;
}

.empty-state,
.not-found {
  text-align: center;
  color: var(--text-secondary);
  padding: 4rem 1rem;
}

.empty-state code {
  background: var(--border);
  padding: 0.2rem 0.4rem;
  border-radius: 4px;
  color: var(--text);
}

.cover {
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  color: #FFFFFF;
  font-weight: 700;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
}

.cover--card {
  width: 100%;
  aspect-ratio: 1;
  font-size: 2rem;
  margin-bottom: 0.75rem;
}

.cover--sm {
  width: 44px;
  height: 44px;
  font-size: 1rem;
  border-radius: 6px;
  flex-shrink: 0;
}

.cover--lg {
  width: 220px;
  height: 220px;
  font-size: 4rem;
  margin-bottom: 1.5rem;
}

.playlist-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 1.5rem;
}

.playlist-card {
  display: block;
  text-decoration: none;
  color: inherit;
}

.playlist-card__name {
  font-weight: 600;
}

.playlist-card__count {
  color: var(--text-secondary);
  font-size: 0.875rem;
}

.playlist-layout {
  display: grid;
  grid-template-columns: 1fr 220px;
  gap: 2.5rem;
  align-items: start;
}

.chart-list {
  list-style: none;
  padding: 0;
  margin: 0;
  border-top: 1px solid var(--border);
}

.chart-list__item {
  border-bottom: 1px solid var(--border);
}

.chart-list__link {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.6rem 0.5rem;
  text-decoration: none;
  color: var(--text);
}

.chart-list__link:hover {
  background: var(--border);
}

.chart-list__index {
  width: 1.5rem;
  color: var(--text-secondary);
  font-variant-numeric: tabular-nums;
}

.chart-list__info {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.chart-list__title {
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.chart-list__artist {
  color: var(--text-secondary);
  font-size: 0.875rem;
}

.aside {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.aside__title {
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-secondary);
}

.genre-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.genre-pill {
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--text);
  border-radius: 999px;
  padding: 0.35rem 0.8rem;
  font-size: 0.85rem;
  cursor: pointer;
}

.genre-pill:hover {
  border-color: var(--accent);
}

.genre-pill--active {
  background: var(--accent);
  border-color: var(--accent);
  color: #FFFFFF;
}

.track-detail__title {
  font-size: 1.5rem;
  margin-bottom: 0.25rem;
}

.track-detail__artist {
  color: var(--accent);
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
  border-bottom: 1px solid var(--border);
}

.track-meta__label {
  color: var(--text-secondary);
}

.track-meta__value {
  font-weight: 500;
}

@media (max-width: 900px) {
  .app-shell {
    grid-template-columns: 1fr;
  }

  .sidebar {
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
    padding: 1rem;
  }

  .sidebar__nav,
  .sidebar__footer {
    display: none;
  }

  .sidebar__section {
    flex-direction: row;
    gap: 1rem;
  }

  .sidebar__section-title {
    display: none;
  }

  .topbar {
    padding: 1rem;
  }

  .page-content {
    padding: 1.25rem;
  }

  .playlist-layout {
    grid-template-columns: 1fr;
  }
}
```

- [ ] **Step 4: Rodar a suíte completa e confirmar que nada quebrou**

Run: `bundle exec rake test`
Expected: PASS em todos os testes (CSS não afeta texto renderizado)

- [ ] **Step 5: Commit**

```bash
git add public/style.css test/exportify/web_server_test.rb
git commit -m "Reescrever style.css no visual do tema Musik (sidebar escura, cards, dark mode)"
```

---

### Task 5: `public/app.js` — dark mode, fullscreen e filtro

**Files:**
- Create: `public/app.js`
- Modify: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `#theme-toggle`, `#fullscreen-toggle`, `#search-input` (Task 3); `.genre-pill`, `[data-genre]` (Task 7)
- Produces: comportamento client-side; espera elementos `#search-container` e `[data-search-text]` nas páginas que quiserem filtro (Tasks 6 e 7)

- [ ] **Step 1: Escrever o teste (vai falhar, arquivo ainda não existe → 404)**

Adicionar em `test/exportify/web_server_test.rb`:

```ruby
  def test_get_app_js_is_served
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/assets/app.js"))

      assert_equal '200', response.code
    end
  end
```

- [ ] **Step 2: Rodar e confirmar falha**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb -n test_get_app_js_is_served`
Expected: FAIL — código `404`

- [ ] **Step 3: Criar `public/app.js`**

```js
(function () {
  'use strict';

  function updateThemeToggleState() {
    var toggle = document.getElementById('theme-toggle');
    if (!toggle) return;
    toggle.setAttribute('aria-pressed', String(document.documentElement.dataset.theme === 'dark'));
  }

  function setTheme(theme) {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem('exportify-theme', theme);
    } catch (e) {
      /* modo privado, ignora */
    }
    updateThemeToggleState();
  }

  function initThemeToggle() {
    var toggle = document.getElementById('theme-toggle');
    if (!toggle) return;
    updateThemeToggleState();
    toggle.addEventListener('click', function () {
      var current = document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
      setTheme(current === 'dark' ? 'light' : 'dark');
    });
  }

  function initFullscreenToggle() {
    var toggle = document.getElementById('fullscreen-toggle');
    if (!toggle) return;
    toggle.addEventListener('click', function () {
      if (document.fullscreenElement) {
        document.exitFullscreen();
      } else {
        document.documentElement.requestFullscreen();
      }
    });
  }

  function filterItems(term) {
    var container = document.getElementById('search-container');
    if (!container) return;
    var needle = term.trim().toLowerCase();
    container.querySelectorAll('[data-search-text]').forEach(function (el) {
      var haystack = el.dataset.searchText.toLowerCase();
      el.hidden = needle.length > 0 && haystack.indexOf(needle) === -1;
    });
  }

  function initSearch() {
    var input = document.getElementById('search-input');
    if (!input) return;
    var container = document.getElementById('search-container');
    input.hidden = !container;
    if (!container) return;
    input.value = '';
    input.addEventListener('input', function () {
      filterItems(input.value);
    });
  }

  function initGenrePills() {
    var pills = document.querySelectorAll('.genre-pill');
    var input = document.getElementById('search-input');
    pills.forEach(function (pill) {
      pill.addEventListener('click', function () {
        var isActive = !pill.classList.contains('genre-pill--active');
        pills.forEach(function (other) {
          other.classList.remove('genre-pill--active');
        });
        pill.classList.toggle('genre-pill--active', isActive);
        var term = isActive ? pill.dataset.genre : '';
        if (input) input.value = term;
        filterItems(term);
      });
    });
  }

  document.addEventListener('turbo:load', function () {
    initThemeToggle();
    initFullscreenToggle();
    initSearch();
    initGenrePills();
  });
})();
```

- [ ] **Step 4: Rodar e confirmar que passa**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb -n test_get_app_js_is_served`
Expected: PASS

- [ ] **Step 5: Rodar a suíte completa**

Run: `bundle exec rake test`
Expected: PASS em todos os testes

- [ ] **Step 6: Commit**

```bash
git add public/app.js test/exportify/web_server_test.rb
git commit -m "Adicionar app.js com dark mode, fullscreen e filtro de busca/gênero"
```

---

### Task 6: `views/index.html.erb` — grade de playlists com capa

**Files:**
- Modify: `views/index.html.erb`
- Modify: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `Exportify::Cover.for(text)` (Task 1); CSS `.cover.cover--card`, `.playlist-grid`, `.playlist-card*` (Task 4); JS `#search-container`, `[data-search-text]` (Task 5)

- [ ] **Step 1: Escrever o teste (vai falhar, capa/atributo ainda não existem na view)**

Adicionar em `test/exportify/web_server_test.rb`, logo após `test_get_root_renders_sidebar_and_topbar`:

```ruby
  def test_get_root_renders_generated_cover_and_search_text
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_includes response.body, 'class="cover cover--card"'
      assert_includes response.body, 'data-search-text="Rock"'
    end
  end
```

- [ ] **Step 2: Rodar e confirmar falha**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb -n test_get_root_renders_generated_cover_and_search_text`
Expected: FAIL — `response.body` não contém `class="cover cover--card"`

- [ ] **Step 3: Reescrever `views/index.html.erb`**

```erb
<% if playlists.empty? %>
  <div class="empty-state">
    <p>Nenhuma playlist baixada ainda.</p>
    <p>Use <code>bin/exportify &lt;url_da_playlist&gt;</code> para baixar uma.</p>
  </div>
<% else %>
  <div class="playlist-grid" id="search-container">
    <% playlists.each do |playlist| %>
      <% cover = Exportify::Cover.for(playlist[:name]) %>
      <a class="playlist-card"
         href="/playlists/<%= ERB::Util.url_encode(playlist[:name]) %>"
         data-search-text="<%= ERB::Util.html_escape(playlist[:name]) %>">
        <div class="cover cover--card"
             style="background: linear-gradient(135deg, <%= cover[:from] %>, <%= cover[:to] %>)">
          <%= cover[:initial] %>
        </div>
        <div class="playlist-card__name"><%= ERB::Util.html_escape(playlist[:name]) %></div>
        <div class="playlist-card__count"><%= playlist[:track_count] %> faixas</div>
      </a>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 4: Rodar toda a suíte de `web_server_test.rb`**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: PASS em todos os testes, incluindo `test_get_root_lists_playlists` e o novo teste desta task

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop test/exportify/web_server_test.rb`
Expected: `no offenses detected`

- [ ] **Step 6: Commit**

```bash
git add views/index.html.erb test/exportify/web_server_test.rb
git commit -m "Reestilizar a home com grade de cards e capas geradas"
```

---

### Task 7: `views/playlist.html.erb` — lista estilo Charts + gêneros

**Files:**
- Modify: `views/playlist.html.erb`
- Modify: `lib/exportify/web_server.rb`
- Modify: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `Exportify::Cover.for` (Task 1), `Library.genres` (Task 2), CSS `.chart-list*`, `.playlist-layout`, `.aside*`, `.genre-pill` (Task 4), JS `#search-container`, `[data-search-text]`, `[data-genre]` (Task 5)
- Produces: `WebServer#render_playlist` passa `genres:` como local para a view `playlist`

- [ ] **Step 1: Escrever o teste (vai falhar, lista ainda não é `.chart-list`)**

Adicionar em `test/exportify/web_server_test.rb`, logo após `test_get_playlist_lists_tracks`:

```ruby
  def test_get_playlist_renders_chart_list_with_numbered_index
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock"))

      assert_includes response.body, 'class="chart-list"'
      assert_includes response.body, 'chart-list__index'
    end
  end
```

- [ ] **Step 2: Rodar e confirmar falha**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb -n test_get_playlist_renders_chart_list_with_numbered_index`
Expected: FAIL — `response.body` não contém `class="chart-list"`

- [ ] **Step 3: Passar `genres` para a view em `web_server.rb`**

Substituir:

```ruby
    def render_playlist(res, name)
      tracks = Library.tracks(name)
      return render_not_found(res, 'Playlist não encontrada.') unless tracks

      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template('playlist', playlist_name: name, tracks: tracks)
    end
```

por:

```ruby
    def render_playlist(res, name)
      tracks = Library.tracks(name)
      return render_not_found(res, 'Playlist não encontrada.') unless tracks

      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template('playlist', playlist_name: name, tracks: tracks, genres: Library.genres(name))
    end
```

- [ ] **Step 4: Reescrever `views/playlist.html.erb`**

```erb
<a class="breadcrumb" href="/">&larr; Playlists</a>
<h1><%= ERB::Util.html_escape(playlist_name) %></h1>

<div class="playlist-layout">
  <ol class="chart-list" id="search-container">
    <% tracks.each_with_index do |track, index| %>
      <% cover = Exportify::Cover.for("#{track[:artist]} - #{track[:title]}") %>
      <li class="chart-list__item">
        <a class="chart-list__link"
           href="/playlists/<%= ERB::Util.url_encode(playlist_name) %>/faixas/<%= ERB::Util.url_encode(track[:filename]) %>"
           data-search-text="<%= ERB::Util.html_escape("#{track[:title]} #{track[:artist]} #{track[:genre]}") %>">
          <span class="chart-list__index"><%= index + 1 %></span>
          <div class="cover cover--sm"
               style="background: linear-gradient(135deg, <%= cover[:from] %>, <%= cover[:to] %>)">
            <%= cover[:initial] %>
          </div>
          <span class="chart-list__info">
            <span class="chart-list__title"><%= ERB::Util.html_escape(track[:title]) %></span>
            <span class="chart-list__artist"><%= ERB::Util.html_escape(track[:artist]) %></span>
          </span>
        </a>
      </li>
    <% end %>
  </ol>

  <% if genres.any? %>
    <aside class="aside">
      <span class="aside__title">Gêneros</span>
      <div class="genre-pills">
        <% genres.each do |genre| %>
          <button type="button" class="genre-pill" data-genre="<%= ERB::Util.html_escape(genre) %>">
            <%= ERB::Util.html_escape(genre) %>
          </button>
        <% end %>
      </div>
    </aside>
  <% end %>
</div>
```

- [ ] **Step 5: Rodar toda a suíte de `web_server_test.rb`**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: PASS em todos os testes, incluindo `test_get_playlist_lists_tracks` e o novo teste desta task

- [ ] **Step 6: Rodar a suíte completa**

Run: `bundle exec rake test`
Expected: PASS em todos os testes

- [ ] **Step 7: Lint**

Run: `bundle exec rubocop lib/exportify/web_server.rb test/exportify/web_server_test.rb`
Expected: `no offenses detected`

- [ ] **Step 8: Commit**

```bash
git add views/playlist.html.erb lib/exportify/web_server.rb test/exportify/web_server_test.rb
git commit -m "Reestilizar a lista de faixas como Charts numerado com pills de gênero"
```

---

### Task 8: `views/track.html.erb` — capa grande na página de faixa

**Files:**
- Modify: `views/track.html.erb`
- Modify: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `Exportify::Cover.for` (Task 1), CSS `.cover--lg` (Task 4)

- [ ] **Step 1: Escrever o teste (vai falhar, capa grande ainda não existe)**

Adicionar em `test/exportify/web_server_test.rb`, logo após `test_get_track_shows_details_and_player`:

```ruby
  def test_get_track_renders_large_cover
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      url = URI("http://127.0.0.1:#{port}/playlists/Rock/faixas/Queen%20-%20Bohemian%20Rhapsody.mp3")
      response = Net::HTTP.get_response(url)

      assert_includes response.body, 'cover--lg'
    end
  end
```

- [ ] **Step 2: Rodar e confirmar falha**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb -n test_get_track_renders_large_cover`
Expected: FAIL — `response.body` não contém `cover--lg`

- [ ] **Step 3: Reescrever `views/track.html.erb`**

```erb
<a class="breadcrumb" href="/playlists/<%= ERB::Util.url_encode(playlist_name) %>">
  &larr; <%= ERB::Util.html_escape(playlist_name) %>
</a>

<% cover = Exportify::Cover.for("#{track[:artist]} - #{track[:title]}") %>
<div class="cover cover--lg"
     style="background: linear-gradient(135deg, <%= cover[:from] %>, <%= cover[:to] %>)">
  <%= cover[:initial] %>
</div>

<h1 class="track-detail__title"><%= ERB::Util.html_escape(track[:title]) %></h1>
<p class="track-detail__artist"><%= ERB::Util.html_escape(track[:artist]) %></p>

<audio class="track-detail__player" controls
       src="/library/<%= ERB::Util.url_encode(playlist_name) %>/<%= ERB::Util.url_encode(filename) %>"></audio>

<ul class="track-meta">
  <li class="track-meta__row">
    <span class="track-meta__label">Álbum</span>
    <span class="track-meta__value"><%= ERB::Util.html_escape(track[:album] || '—') %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Ano</span>
    <span class="track-meta__value"><%= ERB::Util.html_escape(track[:year] || '—') %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Faixa nº</span>
    <span class="track-meta__value"><%= ERB::Util.html_escape(track[:track_number] || '—') %></span>
  </li>
  <li class="track-meta__row">
    <span class="track-meta__label">Gênero</span>
    <span class="track-meta__value"><%= ERB::Util.html_escape(track[:genre] || '—') %></span>
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

- [ ] **Step 4: Rodar toda a suíte de `web_server_test.rb`**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: PASS em todos os testes, incluindo `test_get_track_shows_details_and_player` e o novo teste desta task

- [ ] **Step 5: Rodar a suíte completa**

Run: `bundle exec rake test`
Expected: PASS em todos os testes

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop test/exportify/web_server_test.rb`
Expected: `no offenses detected`

- [ ] **Step 7: Commit**

```bash
git add views/track.html.erb test/exportify/web_server_test.rb
git commit -m "Reestilizar a página de faixa com capa grande"
```

---

### Task 9: Verificação final e QA manual

**Files:** nenhum arquivo novo — só verificação.

- [ ] **Step 1: Rodar a suíte completa**

Run: `bundle exec rake test`
Expected: PASS em todos os testes (Cover, Library, WebServer)

- [ ] **Step 2: Rodar rubocop no projeto inteiro**

Run: `bundle exec rubocop`
Expected: `no offenses detected`

- [ ] **Step 3: QA manual no navegador**

Rodar `bin/exportify web` com pelo menos uma playlist baixada em `musics/` (o repo já tem playlists de teste em `musics/`) e verificar manualmente:

- [ ] Home (`/`): grade de cards com capas coloridas, contagem de faixas, sidebar escura fixa à esquerda
- [ ] Busca na home: digitar parte do nome de uma playlist e ver os outros cards sumirem
- [ ] Clicar numa playlist → lista numerada estilo Charts, com capas pequenas
- [ ] Busca na playlist: digitar título/artista de uma faixa e ver a lista filtrar
- [ ] Pills de gênero (se a playlist tiver faixas com tag de gênero): clicar filtra a lista; clicar de novo desfaz o filtro
- [ ] Clicar numa faixa → capa grande, player de áudio funcional, metadados
- [ ] Toggle "Tema escuro" na sidebar: conteúdo principal e coluna direita trocam de cor; sidebar continua escura; recarregar a página mantém o tema escolhido (via `localStorage`)
- [ ] Botão "Tela cheia": entra e sai do modo fullscreen
- [ ] Redimensionar a janela para < 900px: sidebar vira uma barra horizontal compacta, coluna de gêneros some
- [ ] URL inexistente → página 404 dentro do mesmo layout, com link de volta

- [ ] **Step 4: Commit final (se houver ajustes do QA manual)**

```bash
git status
# se houver mudanças pendentes de ajustes do QA:
git add -A
git commit -m "Ajustes finais de QA manual no redesign do tema Musik"
```

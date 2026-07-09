# Ações no app web (criar playlist, retag, sync) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar três ações à interface web do Exportify (`bin/exportify web`) — criar playlist, retag e sync — disparando `bin/exportify` como subprocesso em background e expondo progresso via polling.

**Architecture:** Cada ação faz um `POST` que dispara `Exportify::Jobs.start(cmd)`, que roda `bin/exportify <url> [--retag|--sync] [--browser=X]` numa `Thread` via `Open3.popen2e`, guardando log/status num registro thread-safe em memória. O frontend faz polling em `GET /jobs/:id` até `done`/`error`. A URL de origem de cada playlist é persistida em `.exportify.json` dentro do diretório da playlist, gravado pelo próprio `CLI.run`.

**Tech Stack:** Ruby 3.3 (WEBrick, Open3, Minitest), ERB, JS puro (sem build step), `<dialog>` HTML nativo.

## Global Constraints

- `Layout/LineLength` máximo 120 colunas (`.rubocop.yml`).
- `Style/StringLiterals`: aspas simples em Ruby.
- Todo arquivo Ruby novo começa com `# frozen_string_literal: true`.
- Módulos seguem o padrão `module_function` já usado em `Library`, `Downloader`, `Spotify`, `Youtube`, `Tagger`, `Config`.
- Comandos de subprocesso são sempre montados como array (nunca string interpolada), para evitar injeção de shell — mesmo padrão já usado em `CLI.download_chaptered_video`.
- Testes usam Minitest (`bundle exec rake test`), sem gems novas de teste.
- Nenhuma gem nova é adicionada ao `Gemfile`/`exportify.gemspec` — tudo usa stdlib (`Open3`, `SecureRandom`, `JSON`, `WEBrick`).

---

### Task 1: `Exportify::Library.source` — ler `.exportify.json`

**Files:**
- Modify: `lib/exportify/library.rb`
- Test: `test/exportify/library_test.rb`

**Interfaces:**
- Produces: `Exportify::Library.source(playlist_name) -> { url: String, browser: String|nil } | nil`

- [ ] **Step 1: Escrever o teste que falha**

Adicionar ao final de `test/exportify/library_test.rb`, antes do último `end` da classe:

```ruby
  def test_source_returns_parsed_metadata_when_file_exists
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      File.write(
        File.join(playlist_dir, '.exportify.json'),
        '{"url":"https://open.spotify.com/playlist/abc123","browser":"chrome"}'
      )

      Exportify::Config.stub(:output_dir, dir) do
        result = Exportify::Library.source('Rock')

        assert_equal 'https://open.spotify.com/playlist/abc123', result[:url]
        assert_equal 'chrome', result[:browser]
      end
    end
  end

  def test_source_returns_nil_when_file_missing
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Rock'))

      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.source('Rock')
      end
    end
  end

  def test_source_returns_nil_when_json_is_invalid
    Dir.mktmpdir do |dir|
      playlist_dir = File.join(dir, 'Rock')
      FileUtils.mkdir_p(playlist_dir)
      File.write(File.join(playlist_dir, '.exportify.json'), 'not json')

      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.source('Rock')
      end
    end
  end

  def test_source_returns_nil_for_unknown_playlist
    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        assert_nil Exportify::Library.source('Does Not Exist')
      end
    end
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Expected: FAIL com `NoMethodError: undefined method 'source' for Exportify::Library`

- [ ] **Step 3: Implementar `Library.source`**

Em `lib/exportify/library.rb`, adicionar logo após o método `playlist_dir` (depois da linha `58`, antes de `fallback_from_filename`):

```ruby
    def source(playlist_name)
      dir = playlist_dir(playlist_name)
      return nil unless dir

      path = File.join(dir, '.exportify.json')
      return nil unless File.exist?(path)

      JSON.parse(File.read(path), symbolize_names: true)
    rescue JSON::ParserError
      nil
    end
```

`require 'json'` já está no topo do arquivo (linha 4) — nenhum require novo é necessário.

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec rake test TEST=test/exportify/library_test.rb`
Expected: PASS (todos os testes, incluindo os 4 novos)

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop lib/exportify/library.rb test/exportify/library_test.rb`
Expected: `no offenses detected`

- [ ] **Step 6: Commit**

```bash
git add lib/exportify/library.rb test/exportify/library_test.rb
git commit -m "$(cat <<'EOF'
Adicionar Library.source para ler metadado .exportify.json

EOF
)"
```

---

### Task 2: `CLI.run` grava `.exportify.json` ao baixar uma playlist

**Files:**
- Modify: `lib/exportify/cli.rb`
- Test: `test/exportify/cli_test.rb`

**Interfaces:**
- Consumes: nada de tasks anteriores.
- Produces: `Exportify::CLI.write_source_metadata(output_dir, url:, browser:)` — grava `<output_dir>/.exportify.json`. Usado pelo `Library.source` (Task 1) para ler esse mesmo arquivo depois.

- [ ] **Step 1: Escrever o teste que falha**

Adicionar ao final de `test/exportify/cli_test.rb`, antes do último `end` da classe:

```ruby
  def test_run_writes_source_metadata_after_download
    require 'tmpdir'

    fake_data = { name: 'Minha Playlist', tracks: [] }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:load, -> { {} }) do
        Exportify::Config.stub(:output_dir, dir) do
          Exportify::YouTube.stub(:fetch_playlist, fake_data) do
            assert_output(/1 tracks found|0 tracks found/) do
              Exportify::CLI.run(['https://www.youtube.com/playlist?list=PL123'])
            end
          end
        end
      end

      metadata_path = File.join(dir, 'Minha Playlist', '.exportify.json')
      assert_path_exists metadata_path

      metadata = JSON.parse(File.read(metadata_path), symbolize_names: true)
      assert_equal 'https://www.youtube.com/playlist?list=PL123', metadata[:url]
      assert_nil metadata[:browser]
    end
  end

  def test_run_writes_source_metadata_with_browser
    require 'tmpdir'

    fake_data = { name: 'Minha Playlist', tracks: [] }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        Exportify::YouTube.stub(:fetch_playlist, fake_data) do
          Exportify::CLI.run(['https://www.youtube.com/playlist?list=PL123', '--browser=firefox'])
        end
      end

      metadata_path = File.join(dir, 'Minha Playlist', '.exportify.json')
      metadata = JSON.parse(File.read(metadata_path), symbolize_names: true)
      assert_equal 'firefox', metadata[:browser]
    end
  end
```

Adicionar `require 'json'` no topo de `test/exportify/cli_test.rb` (depois de `require 'exportify/web_server'`).

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec rake test TEST=test/exportify/cli_test.rb`
Expected: FAIL (arquivo `.exportify.json` não existe — `Minitest::Assertion: Expected path '.../.exportify.json' to exist`)

- [ ] **Step 3: Implementar `write_source_metadata` e chamar em `run`**

Em `lib/exportify/cli.rb`, adicionar `require 'json'` junto aos outros requires no topo (depois de `require 'optparse'`, linha 4):

```ruby
require 'fileutils'
require 'optparse'
require 'json'
require_relative 'auth'
```

No método `run`, logo após `FileUtils.mkdir_p(output_dir)` (linha 64), adicionar a chamada:

```ruby
      output_dir = File.expand_path(File.join(Config.output_dir, Downloader.sanitize(name)))

      FileUtils.mkdir_p(output_dir)
      write_source_metadata(output_dir, url: url, browser: browser)

      puts "#{tracks.size} tracks found"
```

Adicionar o método novo logo depois de `fetch_spotify_playlist` (depois da linha `153 end`, antes de `def download_chaptered_video`):

```ruby
    def write_source_metadata(output_dir, url:, browser:)
      File.write(File.join(output_dir, '.exportify.json'), JSON.generate({ url: url, browser: browser }))
    end
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec rake test TEST=test/exportify/cli_test.rb`
Expected: PASS (todos os testes, incluindo os 2 novos e os já existentes — nenhum teste anterior deve quebrar)

- [ ] **Step 5: Rodar a suíte completa (garante que nada mais quebrou)**

Run: `bundle exec rake test`
Expected: PASS em todos os arquivos

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop lib/exportify/cli.rb test/exportify/cli_test.rb`
Expected: `no offenses detected`

- [ ] **Step 7: Commit**

```bash
git add lib/exportify/cli.rb test/exportify/cli_test.rb
git commit -m "$(cat <<'EOF'
Gravar .exportify.json com a URL de origem ao baixar uma playlist

EOF
)"
```

---

### Task 3: `Exportify::Jobs` — jobs em background via subprocesso

**Files:**
- Create: `lib/exportify/jobs.rb`
- Modify: `lib/exportify.rb` (adicionar `require_relative 'exportify/jobs'`)
- Test: `test/exportify/jobs_test.rb`

**Interfaces:**
- Produces:
  - `Exportify::Jobs.start(cmd) -> String` — `cmd` é um array de argumentos (ex: `['ruby', '-e', 'puts 1']`); retorna um `job_id` (hex de 16 caracteres).
  - `Exportify::Jobs.status(job_id) -> { status: 'running'|'done'|'error', log: Array<String> } | nil`

- [ ] **Step 1: Escrever o teste que falha**

Criar `test/exportify/jobs_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'exportify/jobs'

class JobsTest < Minitest::Test
  def test_start_returns_job_id_and_status_becomes_done_with_captured_log
    job_id = Exportify::Jobs.start(['ruby', '-e', "puts 'line1'; puts 'line2'"])

    result = wait_for_completion(job_id)

    assert_equal 'done', result[:status]
    assert_equal ['line1', 'line2'], result[:log]
  end

  def test_start_marks_status_error_on_non_zero_exit
    job_id = Exportify::Jobs.start(['ruby', '-e', 'exit 1'])

    result = wait_for_completion(job_id)

    assert_equal 'error', result[:status]
  end

  def test_status_returns_nil_for_unknown_job_id
    assert_nil Exportify::Jobs.status('does-not-exist')
  end

  def test_status_reports_running_before_completion
    job_id = Exportify::Jobs.start(['ruby', '-e', 'sleep 1'])

    assert_equal 'running', Exportify::Jobs.status(job_id)[:status]
  end

  private

  def wait_for_completion(job_id, timeout: 5)
    deadline = Time.now + timeout

    loop do
      result = Exportify::Jobs.status(job_id)
      return result if result[:status] != 'running'
      raise "job #{job_id} não terminou em #{timeout}s" if Time.now > deadline

      sleep 0.02
    end
  end
end
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `bundle exec rake test TEST=test/exportify/jobs_test.rb`
Expected: FAIL com `LoadError: cannot load such file -- exportify/jobs`

- [ ] **Step 3: Implementar `Exportify::Jobs`**

Criar `lib/exportify/jobs.rb`:

```ruby
# frozen_string_literal: true

require 'open3'
require 'securerandom'

module Exportify
  module Jobs
    module_function

    @jobs = {}
    @registry_mutex = Mutex.new

    def start(cmd)
      job_id = SecureRandom.hex(8)
      job = { status: 'running', log: [], mutex: Mutex.new }

      @registry_mutex.synchronize { @jobs[job_id] = job }

      Thread.new { run(job, cmd) }

      job_id
    end

    def status(job_id)
      job = @registry_mutex.synchronize { @jobs[job_id] }
      return nil unless job

      job[:mutex].synchronize { { status: job[:status], log: job[:log].dup } }
    end

    def run(job, cmd)
      Open3.popen2e(*cmd) do |_stdin, stdout_err, wait_thread|
        stdout_err.each_line do |line|
          job[:mutex].synchronize { job[:log] << line.chomp }
        end

        job[:mutex].synchronize { job[:status] = wait_thread.value.success? ? 'done' : 'error' }
      end
    rescue StandardError => e
      job[:mutex].synchronize do
        job[:log] << "Erro: #{e.message}"
        job[:status] = 'error'
      end
    end
  end
end
```

Adicionar o require em `lib/exportify.rb` (depois de `require_relative 'exportify/library'`):

```ruby
require_relative 'exportify/library'
require_relative 'exportify/jobs'
require_relative 'exportify/cli'
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec rake test TEST=test/exportify/jobs_test.rb`
Expected: PASS (os 4 testes; pode levar ~1-2s por causa dos `sleep`/subprocessos reais)

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop lib/exportify/jobs.rb lib/exportify.rb test/exportify/jobs_test.rb`
Expected: `no offenses detected`

- [ ] **Step 6: Commit**

```bash
git add lib/exportify/jobs.rb lib/exportify.rb test/exportify/jobs_test.rb
git commit -m "$(cat <<'EOF'
Adicionar Exportify::Jobs para rodar ações em background

EOF
)"
```

---

### Task 4: `WebServer` — `POST /playlists` (criar) + `GET /jobs/:id`

**Files:**
- Modify: `lib/exportify/web_server.rb`
- Test: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `Exportify::Jobs.start(cmd) -> String` e `Exportify::Jobs.status(job_id) -> Hash|nil` (Task 3); `Exportify::CLI.source_for(url) -> Symbol|nil` (já existente em `lib/exportify/cli.rb`).
- Produces: rotas HTTP `POST /playlists` e `GET /jobs/:id`, usadas pelo frontend na Task 6.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao topo de `test/exportify/web_server_test.rb` (depois de `require 'fileutils'`):

```ruby
require 'json'
```

Adicionar ao final da classe `WebServerTest`, antes do último `end`:

```ruby
  def test_post_playlists_creates_job_for_valid_url
    with_server do |port|
      Exportify::Jobs.stub(:start, ->(_cmd) { 'job123' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists")
        response = Net::HTTP.post_form(uri, 'url' => 'https://open.spotify.com/playlist/abc123')

        assert_equal '202', response.code
        assert_equal({ 'job_id' => 'job123' }, JSON.parse(response.body))
      end
    end
  end

  def test_post_playlists_rejects_invalid_url
    with_server do |port|
      uri = URI("http://127.0.0.1:#{port}/playlists")
      response = Net::HTTP.post_form(uri, 'url' => 'https://example.com/whatever')

      assert_equal '400', response.code
      assert JSON.parse(response.body)['error']
    end
  end

  def test_post_playlists_threads_url_and_browser_into_command
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, ->(cmd) { received_cmd = cmd; 'job123' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists")
        Net::HTTP.post_form(uri, 'url' => 'https://open.spotify.com/playlist/abc123', 'browser' => 'chrome')
      end
    end

    assert_includes received_cmd, 'https://open.spotify.com/playlist/abc123'
    assert_includes received_cmd, '--browser=chrome'
  end

  def test_post_playlists_omits_browser_flag_when_blank
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, ->(cmd) { received_cmd = cmd; 'job123' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists")
        Net::HTTP.post_form(uri, 'url' => 'https://open.spotify.com/playlist/abc123')
      end
    end

    refute(received_cmd.any? { |arg| arg.start_with?('--browser') })
  end

  def test_get_job_status_returns_json
    with_server do |port|
      Exportify::Jobs.stub(:status, ->(id) { { status: 'done', log: ['ok'] } if id == 'job123' }) do
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/jobs/job123"))

        assert_equal '200', response.code
        assert_equal({ 'status' => 'done', 'log' => ['ok'] }, JSON.parse(response.body))
      end
    end
  end

  def test_get_unknown_job_returns_404
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/jobs/does-not-exist"))

      assert_equal '404', response.code
    end
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: FAIL — `POST /playlists` e `GET /jobs/:id` caem no handler 404 atual (HTML, não JSON), então `JSON.parse(response.body)` explode ou os códigos de status não batem.

- [ ] **Step 3: Implementar as rotas**

Em `lib/exportify/web_server.rb`, adicionar requires no topo (depois de `require 'uri'`, linha 5):

```ruby
require 'uri'
require 'json'
require 'rbconfig'
require_relative 'library'
require_relative 'config'
require_relative 'cover'
require_relative 'jobs'
```

Adicionar a constante do binário logo depois de `PUBLIC_DIR` (linha 14):

```ruby
    ROOT_DIR   = File.expand_path('../..', __dir__)
    VIEWS_DIR  = File.join(ROOT_DIR, 'views')
    PUBLIC_DIR = File.join(ROOT_DIR, 'public')
    EXPORTIFY_BIN = File.join(ROOT_DIR, 'bin', 'exportify')
```

Substituir o método `handle_request` (linhas 36-51) por:

```ruby
    def handle_request(req, res)
      return handle_post(req, res) if req.request_method == 'POST'

      case req.path
      when '/'
        render_index(res)
      when %r{\A/jobs/([^/]+)\z}
        render_job_status(res, Regexp.last_match(1))
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

    def handle_post(req, res)
      case req.path
      when '/playlists'
        create_playlist(req, res)
      else
        render_not_found(res)
      end
    end

    def create_playlist(req, res)
      url = req.query['url'].to_s.strip

      return render_json(res, 400, error: 'URL inválida. Use um link de playlist do Spotify ou YouTube.') \
        unless CLI.source_for(url)

      browser = Library.presence(req.query['browser'])
      cmd = [RbConfig.ruby, EXPORTIFY_BIN, url]
      cmd << "--browser=#{browser}" if browser

      render_json(res, 202, job_id: Jobs.start(cmd))
    end

    def render_job_status(res, job_id)
      status = Jobs.status(job_id)
      return render_json(res, 404, error: 'Job não encontrado.') unless status

      render_json(res, 200, status)
    end

    def render_json(res, code, payload)
      res.status = code
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate(payload)
    end
```

`create_playlist` chama `CLI.source_for` — como `WebServer` já faz `require_relative 'library'` e `Library` depende de `Config`, mas `CLI` ainda não é requerido por `web_server.rb`. Adicionar `require_relative 'cli'` junto aos outros requires do topo:

```ruby
require_relative 'library'
require_relative 'config'
require_relative 'cover'
require_relative 'jobs'
require_relative 'cli'
```

`Library.presence` já existe (linhas 121-123 de `lib/exportify/library.rb`) e é reaproveitado aqui em vez de duplicar a checagem de string em branco.

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: PASS em todos os testes (os novos e os já existentes)

- [ ] **Step 5: Rodar a suíte completa**

Run: `bundle exec rake test`
Expected: PASS em todos os arquivos

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop lib/exportify/web_server.rb test/exportify/web_server_test.rb`
Expected: `no offenses detected`

- [ ] **Step 7: Commit**

```bash
git add lib/exportify/web_server.rb test/exportify/web_server_test.rb
git commit -m "$(cat <<'EOF'
Adicionar POST /playlists e GET /jobs/:id ao app web

EOF
)"
```

---

### Task 5: `WebServer` — `POST /playlists/:nome/retag` e `.../sync`

**Files:**
- Modify: `lib/exportify/web_server.rb`
- Test: `test/exportify/web_server_test.rb`

**Interfaces:**
- Consumes: `Library.source(playlist_name)` (Task 1), `Library.playlist_dir(playlist_name)` (já existente), `Jobs.start` (Task 3), `render_json` (Task 4).
- Produces: rotas `POST /playlists/:nome/retag` e `POST /playlists/:nome/sync`, consumidas pelo frontend na Task 6. `render_playlist` passa a incluir o local `source:` no template, consumido pela view na Task 6.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao final da classe `WebServerTest`, antes do último `end`:

```ruby
  def test_post_retag_uses_stored_source_url_and_browser
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    File.write(
      File.join(@dir, 'Rock', '.exportify.json'),
      '{"url":"https://open.spotify.com/playlist/abc123","browser":"chrome"}'
    )
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, ->(cmd) { received_cmd = cmd; 'job123' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists/Rock/retag")
        response = Net::HTTP.post_form(uri, {})

        assert_equal '202', response.code
      end
    end

    assert_includes received_cmd, 'https://open.spotify.com/playlist/abc123'
    assert_includes received_cmd, '--retag'
    assert_includes received_cmd, '--browser=chrome'
  end

  def test_post_sync_uses_stored_source_url
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    File.write(File.join(@dir, 'Rock', '.exportify.json'), '{"url":"https://open.spotify.com/playlist/abc123"}')
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, ->(cmd) { received_cmd = cmd; 'job123' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists/Rock/sync")
        Net::HTTP.post_form(uri, {})
      end
    end

    assert_includes received_cmd, '--sync'
    refute_includes received_cmd, '--retag'
  end

  def test_post_retag_without_stored_source_accepts_url_param
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    received_cmd = nil

    with_server do |port|
      Exportify::Jobs.stub(:start, ->(cmd) { received_cmd = cmd; 'job123' }) do
        uri = URI("http://127.0.0.1:#{port}/playlists/Rock/retag")
        response = Net::HTTP.post_form(uri, 'url' => 'https://open.spotify.com/playlist/xyz')

        assert_equal '202', response.code
      end
    end

    assert_includes received_cmd, 'https://open.spotify.com/playlist/xyz'
  end

  def test_post_retag_without_stored_source_or_url_param_returns422
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))

    with_server do |port|
      uri = URI("http://127.0.0.1:#{port}/playlists/Rock/retag")
      response = Net::HTTP.post_form(uri, {})

      assert_equal '422', response.code
    end
  end

  def test_post_retag_unknown_playlist_returns_404
    with_server do |port|
      uri = URI("http://127.0.0.1:#{port}/playlists/Unknown/retag")
      response = Net::HTTP.post_form(uri, {})

      assert_equal '404', response.code
    end
  end

  def test_get_playlist_exposes_source_presence_for_view
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    File.write(File.join(@dir, 'Rock', '.exportify.json'), '{"url":"https://open.spotify.com/playlist/abc123"}')

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock"))

      assert_includes response.body, 'data-has-source="1"'
    end
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: FAIL — rotas `retag`/`sync` caem no 404 padrão; `data-has-source` ainda não existe na view.

- [ ] **Step 3: Implementar as rotas e passar `source` para a view**

Em `lib/exportify/web_server.rb`, atualizar `handle_post` para incluir as novas rotas:

```ruby
    def handle_post(req, res)
      case req.path
      when '/playlists'
        create_playlist(req, res)
      when %r{\A/playlists/([^/]+)/retag\z}
        run_playlist_action(req, res, URI.decode_www_form_component(Regexp.last_match(1)), '--retag')
      when %r{\A/playlists/([^/]+)/sync\z}
        run_playlist_action(req, res, URI.decode_www_form_component(Regexp.last_match(1)), '--sync')
      else
        render_not_found(res)
      end
    end
```

Adicionar `run_playlist_action` logo depois de `create_playlist`:

```ruby
    def run_playlist_action(req, res, playlist_name, flag)
      return render_json(res, 404, error: 'Playlist não encontrada.') unless Library.playlist_dir(playlist_name)

      source = Library.source(playlist_name)
      url = source ? source[:url] : Library.presence(req.query['url'])

      return render_json(res, 422, error: 'Informe a URL de origem desta playlist.') unless url

      browser = source ? source[:browser] : nil
      cmd = [RbConfig.ruby, EXPORTIFY_BIN, url, flag]
      cmd << "--browser=#{browser}" if browser

      render_json(res, 202, job_id: Jobs.start(cmd))
    end
```

Atualizar `render_playlist` (já existente) para passar `source:` ao template:

```ruby
    def render_playlist(res, name)
      tracks = Library.tracks(name)
      return render_not_found(res, 'Playlist não encontrada.') unless tracks

      res['Content-Type'] = 'text/html; charset=utf-8'
      genres = tracks.filter_map { |track| track[:genre] }.uniq.sort
      res.body = render_template(
        'playlist',
        playlist_name: name, tracks: tracks, genres: genres, source: Library.source(name)
      )
    end
```

Em `views/playlist.html.erb`, adicionar o atributo `data-has-source` num elemento visível na resposta mesmo antes da Task 6 terminar a UI completa — substituir as duas primeiras linhas do arquivo (breadcrumb + `h1`):

```erb
<a class="breadcrumb" href="/">&larr; Playlists</a>
<h1 data-has-source="<%= source ? '1' : '' %>"><%= ERB::Util.html_escape(playlist_name) %></h1>
```

(A Task 6 vai mover esse atributo para os botões de ação; por ora ele só precisa existir para o teste `test_get_playlist_exposes_source_presence_for_view` passar e confirmar que o dado chega até a view.)

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: PASS em todos os testes

- [ ] **Step 5: Rodar a suíte completa**

Run: `bundle exec rake test`
Expected: PASS em todos os arquivos

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop lib/exportify/web_server.rb test/exportify/web_server_test.rb views/playlist.html.erb`
Expected: `no offenses detected` (rubocop não cobre `.erb`, mas rodar garante que os `.rb` continuam limpos)

- [ ] **Step 7: Commit**

```bash
git add lib/exportify/web_server.rb test/exportify/web_server_test.rb views/playlist.html.erb
git commit -m "$(cat <<'EOF'
Adicionar POST /playlists/:nome/retag e /sync ao app web

EOF
)"
```

---

### Task 6: Frontend — modal de progresso e botões de ação

**Files:**
- Create: `views/_job_modal.html.erb`
- Modify: `views/layout.html.erb`
- Modify: `views/index.html.erb`
- Modify: `views/playlist.html.erb`
- Modify: `public/app.js`
- Modify: `public/style.css`
- Test: `test/exportify/web_server_test.rb` (asserts de markup)

**Interfaces:**
- Consumes: `POST /playlists`, `POST /playlists/:nome/retag`, `POST /playlists/:nome/sync`, `GET /jobs/:id` (Tasks 4 e 5).

- [ ] **Step 1: Escrever os testes de markup que falham**

Adicionar ao final da classe `WebServerTest`, antes do último `end`:

```ruby
  def test_get_root_renders_create_playlist_trigger
    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))

      assert_includes response.body, 'data-job-trigger="create"'
      assert_includes response.body, 'id="job-modal"'
    end
  end

  def test_get_playlist_renders_retag_and_sync_triggers
    FileUtils.mkdir_p(File.join(@dir, 'Rock'))
    FileUtils.touch(File.join(@dir, 'Rock', 'Queen - Bohemian Rhapsody.mp3'))

    with_server do |port|
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/playlists/Rock"))

      assert_includes response.body, 'data-job-trigger="retag"'
      assert_includes response.body, 'data-job-trigger="sync"'
      assert_includes response.body, 'data-playlist="Rock"'
    end
  end
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: FAIL — nenhum desses atributos existe ainda na página.

- [ ] **Step 3: Criar o partial do modal**

Criar `views/_job_modal.html.erb`:

```erb
<dialog id="job-modal" class="modal">
  <h2 id="job-modal__title">Nova playlist</h2>

  <div id="job-modal__form">
    <label class="modal__field" id="job-modal__url-field">
      URL da playlist
      <input type="url" id="job-modal__url" placeholder="https://open.spotify.com/playlist/...">
    </label>

    <label class="modal__field" id="job-modal__browser-field">
      Navegador (opcional, para playlists privadas do YouTube)
      <select id="job-modal__browser">
        <option value="">Nenhum</option>
        <option value="chrome">Chrome</option>
        <option value="firefox">Firefox</option>
        <option value="safari">Safari</option>
        <option value="edge">Edge</option>
      </select>
    </label>

    <button type="button" id="job-modal__submit" class="btn btn--primary">Confirmar</button>
  </div>

  <div id="job-modal__progress" class="modal__log" hidden></div>
  <p id="job-modal__error" class="modal__error" hidden></p>

  <button type="button" id="job-modal__close" class="btn">Fechar</button>
</dialog>
```

- [ ] **Step 4: Incluir o partial no layout**

Em `views/layout.html.erb`, adicionar a linha `<%= render_partial('job_modal') %>` logo antes do `</div>` que fecha `.app-shell`:

```erb
<div class="app-shell">
<%= render_partial('sidebar') %>
<div class="main">
<%= render_partial('topbar') %>
<main class="page-content">
<%= content %>
</main>
</div>
<%= render_partial('job_modal') %>
</div>
</body>
</html>
```

- [ ] **Step 5: Adicionar o botão "Nova playlist" na home**

Em `views/index.html.erb`, substituir o conteúdo do arquivo por:

```erb
<div class="page-header">
  <h1>Playlists</h1>
  <button type="button" class="btn btn--primary" data-job-trigger="create">+ Nova playlist</button>
</div>

<% if playlists.empty? %>
  <div class="empty-state">
    <p>Nenhuma playlist baixada ainda.</p>
    <p>Use <code>bin/exportify &lt;url_da_playlist&gt;</code> ou o botão acima para baixar uma.</p>
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
          <%= ERB::Util.html_escape(cover[:initial]) %>
        </div>
        <div class="playlist-card__name"><%= ERB::Util.html_escape(playlist[:name]) %></div>
        <div class="playlist-card__count"><%= playlist[:track_count] %> faixas</div>
      </a>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 6: Adicionar os botões "Sincronizar"/"Retag" na página da playlist**

Em `views/playlist.html.erb`, substituir as linhas alteradas pela Task 5 (breadcrumb + `h1`) por:

```erb
<a class="breadcrumb" href="/">&larr; Playlists</a>
<div class="page-header">
  <h1><%= ERB::Util.html_escape(playlist_name) %></h1>
  <div class="page-header__actions">
    <button type="button" class="btn" data-job-trigger="sync"
            data-playlist="<%= ERB::Util.html_escape(playlist_name) %>"
            data-has-source="<%= source ? '1' : '' %>">Sincronizar</button>
    <button type="button" class="btn" data-job-trigger="retag"
            data-playlist="<%= ERB::Util.html_escape(playlist_name) %>"
            data-has-source="<%= source ? '1' : '' %>">Retag</button>
  </div>
</div>
```

- [ ] **Step 7: Rodar os testes de markup e confirmar que passam**

Run: `bundle exec rake test TEST=test/exportify/web_server_test.rb`
Expected: PASS em todos os testes

- [ ] **Step 8: Implementar o JS do modal**

Em `public/app.js`, adicionar a função `initJobModal` antes do bloco `document.addEventListener('turbo:load', ...)`:

```javascript
  function initJobModal() {
    var modal = document.getElementById('job-modal');
    if (!modal) return;

    var titleEl = document.getElementById('job-modal__title');
    var formSection = document.getElementById('job-modal__form');
    var urlField = document.getElementById('job-modal__url');
    var urlFieldWrap = document.getElementById('job-modal__url-field');
    var browserFieldWrap = document.getElementById('job-modal__browser-field');
    var browserField = document.getElementById('job-modal__browser');
    var submitBtn = document.getElementById('job-modal__submit');
    var closeBtn = document.getElementById('job-modal__close');
    var progress = document.getElementById('job-modal__progress');
    var errorBox = document.getElementById('job-modal__error');

    var TITLES = { create: 'Nova playlist', retag: 'Regravar tags', sync: 'Sincronizar playlist' };
    var action = null;
    var playlistName = null;
    var pollTimer = null;

    function reset() {
      formSection.hidden = false;
      progress.hidden = true;
      progress.textContent = '';
      errorBox.hidden = true;
      urlField.value = '';
      browserField.value = '';
      submitBtn.disabled = false;
      if (pollTimer) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
    }

    function openModal(trigger) {
      action = trigger.dataset.jobTrigger;
      playlistName = trigger.dataset.playlist || null;
      reset();
      titleEl.textContent = TITLES[action] || '';
      urlFieldWrap.hidden = action !== 'create' && trigger.dataset.hasSource === '1';
      browserFieldWrap.hidden = action !== 'create';
      modal.showModal();
    }

    function endpointFor() {
      if (action === 'create') return '/playlists';
      return '/playlists/' + encodeURIComponent(playlistName) + '/' + action;
    }

    function extractPlaylistName(log) {
      var match = log.join('\n').match(/^Output: (.+)$/m);
      if (!match) return null;
      return match[1].trim().split('/').pop();
    }

    function poll(jobId) {
      pollTimer = setInterval(function () {
        fetch('/jobs/' + jobId)
          .then(function (r) { return r.json(); })
          .then(function (data) {
            progress.textContent = data.log.join('\n');
            progress.scrollTop = progress.scrollHeight;

            if (data.status === 'done') {
              clearInterval(pollTimer);
              var name = action === 'create' ? extractPlaylistName(data.log) : playlistName;
              window.location.href = name ? '/playlists/' + encodeURIComponent(name) : '/';
            } else if (data.status === 'error') {
              clearInterval(pollTimer);
              errorBox.hidden = false;
              errorBox.textContent = data.log[data.log.length - 1] || 'Falha desconhecida.';
            }
          });
      }, 1500);
    }

    function submit() {
      submitBtn.disabled = true;

      var params = new URLSearchParams();
      if (!urlFieldWrap.hidden) params.set('url', urlField.value);
      if (action === 'create') params.set('browser', browserField.value);

      fetch(endpointFor(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString()
      })
        .then(function (r) {
          return r.json().then(function (data) {
            if (!r.ok) throw new Error(data.error || 'Falha ao iniciar a ação.');
            return data;
          });
        })
        .then(function (data) {
          formSection.hidden = true;
          progress.hidden = false;
          poll(data.job_id);
        })
        .catch(function (err) {
          errorBox.hidden = false;
          errorBox.textContent = err.message;
          submitBtn.disabled = false;
        });
    }

    document.querySelectorAll('[data-job-trigger]').forEach(function (trigger) {
      trigger.addEventListener('click', function () { openModal(trigger); });
    });

    submitBtn.addEventListener('click', submit);
    closeBtn.addEventListener('click', function () {
      if (pollTimer) clearInterval(pollTimer);
      modal.close();
    });
  }
```

Registrar a chamada dentro do listener já existente:

```javascript
  document.addEventListener('turbo:load', function () {
    initThemeToggle();
    initFullscreenToggle();
    initSearch();
    initGenrePills();
    initJobModal();
  });
```

- [ ] **Step 9: Adicionar os estilos do modal e dos botões**

Em `public/style.css`, adicionar ao final do arquivo (antes do bloco `@media (max-width: 900px)` para que as regras responsivas continuem sendo as últimas):

```css
.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.page-header h1 {
  margin: 0;
}

.page-header__actions {
  display: flex;
  gap: 0.75rem;
}

.btn {
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--text);
  border-radius: 8px;
  padding: 0.5rem 1rem;
  font: inherit;
  cursor: pointer;
}

.btn:hover {
  border-color: var(--accent);
}

.btn--primary {
  background: var(--accent);
  border-color: var(--accent);
  color: #FFFFFF;
}

.btn--primary:hover {
  background: var(--accent-hover);
  border-color: var(--accent-hover);
}

dialog.modal {
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 1.5rem;
  width: min(480px, 90vw);
  background: var(--surface);
  color: var(--text);
}

dialog.modal::backdrop {
  background: rgba(0, 0, 0, 0.5);
}

.modal__field {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  margin-bottom: 1rem;
  font-size: 0.875rem;
  color: var(--text-secondary);
}

.modal__field input,
.modal__field select {
  padding: 0.55rem 0.75rem;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--bg);
  color: var(--text);
  font: inherit;
}

.modal__log {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 0.75rem;
  font-family: ui-monospace, monospace;
  font-size: 0.8rem;
  white-space: pre-wrap;
  max-height: 240px;
  overflow-y: auto;
  margin-bottom: 1rem;
}

.modal__error {
  color: #DC2626;
  font-size: 0.875rem;
  margin-bottom: 1rem;
}
```

Mover o bloco `@media (max-width: 900px) { ... }` (o que já existia no final do arquivo) para depois destas novas regras, se o Write reescrever o arquivo inteiro — a ordem entre regras não relacionadas ao media query não importa para especificidade aqui, então basta anexar as regras novas antes do bloco `@media` existente.

- [ ] **Step 10: Verificação manual no navegador**

Run: `bundle exec bin/exportify web`

No navegador (`http://localhost:4567`):
1. Clicar em "+ Nova playlist", preencher uma URL de playlist do Spotify/YouTube válida (uma que você tenha acesso), confirmar que o modal muda para o log de progresso e atualiza a cada ~1.5s.
2. Ao concluir, confirmar redirecionamento para `/playlists/<nome>`.
3. Na página da playlist recém-criada, clicar em "Retag" e depois em "Sincronizar", confirmar que ambos abrem o modal, mostram log e recarregam a página ao final.
4. Testar com uma URL inválida no "Nova playlist" — confirmar que o erro aparece no modal sem fechar a página.
5. Testar em `data-theme="dark"` (toggle na sidebar) — confirmar que o modal e os botões têm contraste adequado.

Reportar o resultado antes de prosseguir — esta etapa não é automatizável pela suíte de testes.

- [ ] **Step 11: Rodar a suíte completa e lint**

Run: `bundle exec rake test && bundle exec rubocop`
Expected: PASS em todos os testes, `no offenses detected` no lint

- [ ] **Step 12: Commit**

```bash
git add views/_job_modal.html.erb views/layout.html.erb views/index.html.erb views/playlist.html.erb \
        public/app.js public/style.css test/exportify/web_server_test.rb
git commit -m "$(cat <<'EOF'
Adicionar modal de progresso e botões de ação no app web

EOF
)"
```

---

### Task 7: Atualizar README e rodar verificação final

**Files:**
- Modify: `README.md`

**Interfaces:**
- Nenhuma nova — apenas documentação.

- [ ] **Step 1: Atualizar a seção do app web**

Em `README.md`, substituir o trecho (linhas 107-124):

```markdown
### Visualizar playlists baixadas (app web)

Para navegar pelas playlists e músicas já baixadas em um painel web:

```sh
bin/exportify web
```

Abre um servidor local em `http://localhost:4567` com a lista de playlists,
as faixas de cada uma e os detalhes (tags ID3, duração, tamanho) com player
de áudio. Para usar outra porta:

```sh
bin/exportify web --port 8080
```

> App somente leitura — os downloads continuam sendo feitos via CLI
> (`bin/exportify <url>`).
```

por:

```markdown
### Visualizar e gerenciar playlists pelo app web

Para navegar pelas playlists e músicas já baixadas em um painel web:

```sh
bin/exportify web
```

Abre um servidor local em `http://localhost:4567` com a lista de playlists,
as faixas de cada uma e os detalhes (tags ID3, duração, tamanho) com player
de áudio. Para usar outra porta:

```sh
bin/exportify web --port 8080
```

Pela interface também é possível:

- **Nova playlist** — colar uma URL do Spotify ou YouTube/YouTube Music na
  home e baixar sem usar o terminal.
- **Sincronizar** — na página de uma playlist já baixada, busca faixas
  novas e remove do disco as que saíram da playlist (equivalente a
  `--sync`).
- **Retag** — regrava as tags ID3 dos arquivos existentes sem rebaixar
  (equivalente a `--retag`).

Cada ação roda `bin/exportify` como subprocesso e mostra o progresso em um
modal com o mesmo log exibido no terminal. O CLI continua funcionando
normalmente para quem preferir o terminal.
```

- [ ] **Step 2: Rodar a suíte completa, lint e auditoria de dependências**

Run: `bundle exec rake test && bundle exec rubocop && bundle exec bundler-audit check --update`
Expected: PASS em tudo — mesmos três comandos que o CI roda a cada push (ver seção "Desenvolvimento" do `README.md`)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
Documentar as ações de criar playlist, retag e sync no app web

EOF
)"
```

---

## Fora de escopo (lembrete do design)

Ver `docs/superpowers/specs/2026-07-09-web-actions-design.md` — sem edição manual de tags, sem apagar playlists/faixas pela web, sem cancelar jobs, sem fila persistente, sem autenticação, sem lock contra jobs concorrentes na mesma playlist.

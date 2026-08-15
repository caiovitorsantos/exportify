# Design: Ações no app web (criar playlist, retag, sync)

## Contexto

O app web (`bin/exportify web`, ver
[2026-07-03-web-viewer-design.md](2026-07-03-web-viewer-design.md)) é hoje
somente leitura: lista playlists e faixas já baixadas pela CLI, sem nenhuma
ação de escrita. Todo download/retag/sync continua sendo feito via
`bin/exportify <url> [--retag] [--sync]` no terminal.

Este design adiciona três ações disparáveis pela interface web,
reaproveitando a CLI existente como subprocesso (sem duplicar a lógica de
download/tag):

1. **Criar playlist** — colar uma URL (Spotify ou YouTube/YouTube Music) e
   baixar como uma nova playlist.
2. **Retag** — regravar as tags ID3 de uma playlist já baixada, sem
   rebaixar (equivalente a `--retag`).
3. **Sync** — buscar faixas novas e remover do disco as que saíram da
   playlist (equivalente a `--sync`).

## Fora de escopo

- Editar tags manualmente pela interface (continua sendo só o que a API do
  Spotify/YouTube fornece, via retag).
- Apagar playlists inteiras ou faixas individuais pela web.
- Cancelar um job em andamento.
- Fila/histórico persistente de jobs — o estado vive em memória e se perde
  ao reiniciar o servidor (aceitável para uso local).
- Autenticação/controle de acesso — mesma decisão do design anterior, app
  local de uso pessoal.
- Lock server-side contra dois jobs simultâneos na mesma playlist — risco
  baixo em uso single-user; o botão fica só desabilitado no client
  enquanto o job roda.

## Arquitetura

Cada ação dispara `bin/exportify` como **subprocesso em background**
(mesmo padrão já usado no projeto para invocar `yt-dlp` via `system`), em
vez de refatorar `CLI.run` para rodar in-process. Isso garante que a web
executa exatamente o mesmo código testado do CLI, sem risco de divergência
de comportamento entre os dois caminhos.

```
Browser --POST /playlists--> WebServer --Jobs.start--> Thread
                                                            \
                                                             Open3.popen2e("bin/exportify", url, "--sync")
                                                            /
Browser --GET /jobs/:id (polling)--> WebServer <-- job.log, job.status
```

## Metadado `.exportify.json`

Para retag/sync saberem qual URL reexecutar, `CLI.run` passa a gravar
`<output_dir>/<playlist>/.exportify.json` sempre que baixa uma playlist
(CLI ou web — é o mesmo código):

```json
{ "url": "https://open.spotify.com/playlist/...", "browser": "chrome" }
```

- `browser` é `null` quando `--browser` não foi usado.
- Gravado depois do `FileUtils.mkdir_p(output_dir)`, antes do loop de
  download, via um novo método `write_source_metadata(output_dir, url:, browser:)`
  em `Exportify::CLI`.
- Playlists baixadas antes desta mudança não têm o arquivo. `Library` passa
  a expor `Library.source(playlist_name)`, que retorna o hash do JSON ou
  `nil`. A UI trata `nil` pedindo a URL uma vez (ver seção Frontend) e o
  próximo download grava o metadado normalmente.
- `Library.playlists`/`Library.tracks` ignoram arquivos que começam com
  `.` (já é o comportamento implícito do `Dir.glob('*.mp3')`, mas
  `Dir.children` usado em `playlists` precisa filtrar dotfiles — hoje já
  filtra por `File.directory?`, então não há mudança necessária ali).

## `Exportify::Jobs` (novo módulo)

`lib/exportify/jobs.rb`, sem estado de instância exposto — registro
thread-safe em memória:

```ruby
module Exportify
  module Jobs
    module_function

    Job = Struct.new(:id, :status, :log, :mutex, keyword_init: true)

    @jobs = {}
    @jobs_mutex = Mutex.new

    # cmd: array de argumentos pro Open3 (ex: ["bin/exportify", url, "--sync"])
    def start(cmd)
      job = Job.new(id: SecureRandom.hex(8), status: 'running', log: [], mutex: Mutex.new)
      @jobs_mutex.synchronize { @jobs[job.id] = job }

      Thread.new { run(job, cmd) }

      job.id
    end

    def status(job_id)
      job = @jobs_mutex.synchronize { @jobs[job_id] }
      return nil unless job

      job.mutex.synchronize { { status: job.status, log: job.log.dup } }
    end

    def run(job, cmd)
      Open3.popen2e(*cmd) do |_stdin, stdout_err, wait_thread|
        stdout_err.each_line do |line|
          job.mutex.synchronize { job.log << line.chomp }
        end

        job.mutex.synchronize { job.status = wait_thread.value.success? ? 'done' : 'error' }
      end
    rescue StandardError => e
      job.mutex.synchronize do
        job.log << "Erro: #{e.message}"
        job.status = 'error'
      end
    end
  end
end
```

- `cmd` sempre é montado com um array (nunca string interpolada), evitando
  injeção de shell — mesmo padrão de segurança já usado em
  `download_chaptered_video`.
- O binário invocado é o próprio `bin/exportify` do projeto (caminho
  absoluto resolvido a partir de `ROOT_DIR`), garantindo que roda com o
  mesmo Ruby/bundle do servidor.

## Rotas HTTP novas

| Rota | Método | Descrição |
|---|---|---|
| `/playlists` | `POST` | Cria job de download. Body: `url` (obrigatório), `browser` (opcional). |
| `/playlists/:nome/retag` | `POST` | Cria job com `--retag`, usando `url`/`browser` do `.exportify.json` (ou do body, se o metadado não existir). |
| `/playlists/:nome/sync` | `POST` | Idem, com `--sync`. |
| `/jobs/:id` | `GET` | `{ "status": "running"\|"done"\|"error", "log": ["...", ...] }` em JSON. |

`WebServer.handle_request` passa a despachar por `req.request_method` além
do `req.path`. Validação de URL (`POST /playlists`) reaproveita
`Exportify::CLI.source_for` — se inválida, responde `400` sem criar job.

## `bin/exportify` — subcomandos internos para os jobs

Os comandos disparados pelo `Jobs` são chamadas normais ao binário
existente (`bin/exportify <url> [--retag] [--sync] [--browser=X]`) — nenhum
subcomando novo é necessário na CLI além da gravação do metadado descrita
acima.

## Frontend

**Home (`views/index.html.erb`)**: botão "+ Nova playlist" ao lado do
título. Abre um modal (`<dialog>` nativo do HTML, sem dependência nova)
com campo de URL e select opcional de navegador
(chrome/firefox/safari/edge, mapeando `--browser`).

**Página da playlist (`views/playlist.html.erb`)**: dois botões ao lado do
`<h1>`: "Sincronizar" e "Retag". Se `Library.source(playlist_name)` for
`nil`, o clique abre primeiro um prompt simples pedindo a URL (uma vez só;
o próximo job já grava `.exportify.json`).

**Modal de progresso (componente único, reaproveitado pelas 3 ações)**:
depois do POST inicial, mostra o `log` em uma área de texto rolável,
atualizada por polling em `GET /jobs/:id` a cada ~1.5s. Estados:

- `running`: log crescendo, spinner simples.
- `done`: mensagem de sucesso; se foi criação de playlist, extrai o nome
  da playlist da linha `Output: <dir>` do log (regex) e redireciona para
  `/playlists/<nome>`; se foi retag/sync, recarrega a página atual.
- `error`: mostra a última linha do log como mensagem de erro, botão
  "Fechar".

**JS novo em `public/app.js`**: bloco `initJobModal()` — abre/fecha
`<dialog>`, faz o `fetch` POST inicial, faz polling do job, atualiza o log
e trata conclusão/erro. Botões de ação ficam `disabled` enquanto o job da
playlist está `running` (guardado em uma variável do módulo, não em
storage persistente).

**CSS novo em `public/style.css`**: `.modal`/`dialog` (usando
`::backdrop`), `.modal__log` (monoespaçado, scroll vertical), `.btn` /
`.btn--primary` — não existem botões de ação hoje, só links e pills.
Paleta e tema dark/light seguem as variáveis já definidas pelo redesign
Musik (`2026-07-08-musik-theme-redesign-design.md`).

## Tratamento de erros

- URL inválida no `POST /playlists`: `400` antes de criar job, mensagem
  exibida direto no modal sem precisar de polling.
- Credenciais do Spotify ausentes, 403, falha de rede, `yt-dlp` falhando:
  o subprocesso termina com exit code != 0; `Jobs` marca `status: 'error'`
  e o modal mostra a última linha do log.
- Processo que trava sem nunca terminar: não tratado nesta versão (sem
  timeout/kill automático) — aceitável para uso local; usuário pode
  recarregar a página.
- Concorrência entre duas abas disparando o mesmo job: cada uma cria seu
  próprio job id e roda em paralelo; não há corrupção de dados porque o
  download é idempotente (arquivos já existentes são pulados) e o retag
  apenas sobrescreve as mesmas tags.

## Testes

- `test/exportify/jobs_test.rb` (novo):
  - `start` com um comando fake (ex: `['ruby', '-e', 'puts 1; puts 2']`)
    retorna um `job_id`; `status` eventualmente reporta `done` com o log
    esperado (`Timeout.timeout` + polling no teste para aguardar).
  - Comando que sai com erro (`['ruby', '-e', 'exit 1']`): `status` acaba
    em `error`.
  - `status` com id inexistente: retorna `nil`.
- `test/exportify/cli_test.rb`: novo caso cobrindo
  `write_source_metadata`/gravação do `.exportify.json` após um download
  (usando os stubs de `Spotify`/`Downloader` já existentes no arquivo).
- `test/exportify/library_test.rb`: novo caso para `Library.source` —
  retorna o hash quando `.exportify.json` existe, `nil` quando não existe
  ou é JSON inválido.
- `test/exportify/web_server_test.rb`: casos novos para
  `POST /playlists` (URL válida cria job / URL inválida responde 400),
  `POST /playlists/:nome/retag` e `.../sync` (usando uma playlist fixture
  com `.exportify.json`), e `GET /jobs/:id` (status de um job conhecido e
  404 para id inexistente).
- Sem testes automatizados de JS/UI (o projeto não tem infraestrutura para
  isso) — validação manual no navegador rodando `bin/exportify web`.
- Lint: `bundle exec rubocop` nos arquivos novos/alterados.

## README

Atualizar a seção "Visualizar playlists baixadas (app web)" removendo a
nota "App somente leitura" e documentando as três ações disponíveis pela
interface (criar playlist, retag, sync), mantendo a menção de que o CLI
continua funcionando normalmente para quem preferir o terminal.

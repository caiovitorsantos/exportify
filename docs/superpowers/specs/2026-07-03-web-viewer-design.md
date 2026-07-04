# Design: App web para visualizar playlists e músicas baixadas

## Contexto

Hoje o `exportify` é uma CLI que baixa playlists (Spotify e, em breve,
YouTube/YouTube Music) como MP3 com tags ID3, organizados em subpastas por
playlist dentro de `Config.output_dir` (padrão `musics/`):

```
musics/
  Rock dos Anos 80/
    Queen - Bohemian Rhapsody.mp3
    David Bowie - Heroes.mp3
  Trap Brasil/
    ...
```

Não existe hoje nenhuma forma de navegar visualmente pelo que já foi
baixado — é preciso abrir a pasta no Finder/Explorer. Este design adiciona
um pequeno app web, somente leitura, para listar as playlists baixadas,
listar as faixas de cada uma e ver detalhes (tags ID3, duração, tamanho)
com um player de áudio embutido.

## Fora de escopo

- Disparar downloads de novas playlists pela interface web (continua só na
  CLI, via `bin/exportify <url>`).
- Editar ou regravar tags ID3 pela interface.
- Criar, renomear ou apagar playlists/arquivos pela web.
- Autenticação/controle de acesso — app local, para uso pessoal.
- Busca/filtro entre playlists ou faixas (fica para uma iteração futura).

## Arquitetura

- **Backend:** Ruby puro com `WEBrick` (já é dependência do projeto via
  `exportify.gemspec` — nenhuma gem nova é adicionada). Renderiza HTML
  server-side com **ERB**.
- **Frontend:** **Turbo** e **Stimulus** carregados via CDN (sem build
  step, sem npm, sem gem de asset pipeline). Turbo Drive dá navegação
  fluida entre páginas (troca só o `<body>`, sem reload completo);
  Stimulus cuida de comportamentos pequenos, como destacar a faixa atual.
- **Arquivos de áudio:** servidos diretamente por um
  `WEBrick::HTTPServlet::FileHandler` montado em `/library`, apontando
  para `Config.output_dir`. Isso dá suporte nativo a `Range` requests
  (necessário para o `<audio controls>` permitir avançar/retroceder),
  sem nenhum código manual de streaming.
- **Novo subcomando:** `bin/exportify web [--port PORTA]` (porta padrão
  `4567`) sobe o servidor.

### Módulos novos

- `lib/exportify/library.rb` — `Exportify::Library`: descobre playlists e
  faixas em disco, lê metadados via `mutagen`.
- `lib/exportify/web_server.rb` — `Exportify::WebServer`: monta as rotas
  WEBrick e renderiza os templates ERB.
- `views/layout.html.erb`, `views/index.html.erb`,
  `views/playlist.html.erb`, `views/track.html.erb` — templates.
- `public/style.css` — folha de estilo (tema claro, detalhes em azul).

## Rotas HTTP

| Rota | Descrição |
|---|---|
| `GET /` | Lista de playlists (nome + contagem de faixas) |
| `GET /playlists/:nome` | Lista de faixas da playlist (artista + título) |
| `GET /playlists/:nome/faixas/:arquivo` | Detalhes da faixa + player de áudio |
| `GET /library/*` | Arquivos `.mp3` estáticos, via `FileHandler` |
| `GET /assets/*` | CSS estático |

`:nome` e `:arquivo` são recebidos como segmentos de URL (com
`URI.decode_www_form_component`) e sempre validados contra entradas reais
do disco (ver "Segurança" abaixo) antes de qualquer acesso a arquivo.

## `Exportify::Library`

Módulo sem estado (`module_function`), seguindo o padrão de `Spotify`,
`Downloader`, `Config` e `Tagger`.

```ruby
module Exportify
  module Library
    module_function

    # Retorna [{ name: "Rock dos Anos 80", track_count: 12 }, ...]
    # ordenado alfabeticamente por nome.
    def playlists
    end

    # Retorna [{ filename: "Queen - Bohemian Rhapsody.mp3",
    #            title: "Bohemian Rhapsody", artist: "Queen" }, ...]
    # ordenado por track_number (tag TRCK); faixas sem tag ou com tag
    # inválida vão para o final, ordenadas por nome de arquivo.
    def tracks(playlist_name)
    end

    # Retorna { title:, artist:, all_artists:, album:, year:,
    #           track_number:, genre:, duration_seconds:, file_size_bytes: }
    # ou nil se a playlist/arquivo não existir.
    def track(playlist_name, filename)
    end
  end
end
```

### Leitura de tags + duração

`Library.track` lê tudo em uma única chamada a `python3 -c` (mesmo padrão
de shell-out já usado em `Tagger.tag`), retornando JSON:

```python
from mutagen.mp3 import MP3
import json

audio = MP3(filepath)
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
```

`file_size_bytes` vem de `File.size(filepath)` (Ruby puro, sem precisar do
Python). `Library.tracks` (lista) usa a mesma leitura, mas só aproveita
`title`/`artist` — para playlists grandes isso significa uma chamada
`python3` por faixa; como o app é local e de uso pessoal, o custo é
aceitável nesta primeira versão.

### Fallback quando as tags falham

Se a chamada ao `python3`/`mutagen` falhar (exit code != 0), ou os campos
`title`/`artist` vierem vazios, `Library` cai para um fallback derivado do
nome do arquivo, reaproveitando a mesma convenção `"Artista - Título.mp3"`
usada pelo `Downloader`:

```ruby
def fallback_from_filename(filename)
  base = File.basename(filename, '.mp3')
  artist, title = base.split(' - ', 2)
  { artist: artist || base, title: title || base }
end
```

Duração e tamanho ausentes (falha total de leitura) são exibidos como
`—` na tela de detalhes, nunca quebram a página.

### Segurança (path traversal)

`playlists`, `tracks` e `track` nunca interpolam o parâmetro recebido da
URL diretamente em um `File.join` sem checagem. O fluxo é:

1. Decodificar o segmento da URL.
2. Verificar se ele está contido na lista retornada por
   `Dir.children(Config.output_dir)` (para playlist) ou
   `Dir.children(playlist_dir)` (para arquivo).
3. Só então montar o caminho completo e ler o arquivo.

Se não estiver contido, o método retorna `nil` e a rota responde 404.

## `Exportify::WebServer`

```ruby
module Exportify
  module WebServer
    module_function

    def start(port: 4567)
      server = WEBrick::HTTPServer.new(Port: port, DocumentRoot: nil)

      server.mount('/library', WEBrick::HTTPServlet::FileHandler, Config.output_dir)
      server.mount('/assets', WEBrick::HTTPServlet::FileHandler, ASSETS_DIR)

      server.mount_proc('/') { |req, res| render_index(res) }
      server.mount_proc('/playlists/') { |req, res| route_playlist(req, res) }

      trap('INT') { server.shutdown }
      server.start
    end
  end
end
```

- `route_playlist` diferencia `/playlists/:nome` de
  `/playlists/:nome/faixas/:arquivo` a partir do `req.path`, chama
  `Library` e renderiza o template ERB correspondente (`playlist` ou
  `track`), ou responde 404 com uma página simples quando `Library`
  retorna `nil`.
- Templates ERB são carregados e renderizados a cada request (sem cache
  de compilação) — simples e suficiente para um app local de uso
  pessoal; não há necessidade de otimizar isso agora.

## `bin/exportify web`

`Exportify::CLI.run` passa a reconhecer o subcomando `web`:

```
exportify web [--port PORTA]
```

- Porta padrão `4567`.
- Ao subir, imprime a URL (`Servidor rodando em http://localhost:4567`).
- `Ctrl+C` encerra o servidor de forma limpa (`trap('INT')`).

## Design visual (frontend)

**Paleta:**

| Uso | Cor |
|---|---|
| Fundo | `#FAFAFA` |
| Texto principal | `#1A1A1A` |
| Texto secundário | `#6B7280` |
| Azul de destaque (links, player, item ativo) | `#2563EB` (hover `#1D4ED8`) |
| Bordas/divisores | `#E5E7EB` |

Sem gradientes nem sombras pesadas; cards com borda fina. Tipografia:
`system-ui` (sem webfonts externas).

**Tela 1 — Lista de playlists (`/`):** grid de cards responsivo (2–4
colunas). Cada card: ícone genérico de nota musical, nome da playlist,
contagem de faixas em cinza. Estado vazio (sem playlists em disco):
mensagem central com a dica `bin/exportify <url_da_playlist>`.

**Tela 2 — Lista de faixas (`/playlists/:nome`):** breadcrumb "← Playlists"
(link azul) no topo. Lista vertical (não tabela): cada linha mostra
artista + título, separadas por divisor fino, com hover em cinza bem
claro. Clique leva aos detalhes da faixa.

**Tela 3 — Detalhes da faixa:** breadcrumb "← Nome da playlist". Título
grande, artista abaixo em azul. Player `<audio controls src="/library/...">`
centralizado. Abaixo, pares label/valor (cinza/preto): álbum, ano, faixa
nº, gênero, duração (formatada `mm:ss`), tamanho do arquivo (formatado
`KB`/`MB`).

## Tratamento de erros

- `musics/` vazia ou inexistente: tela inicial com estado vazio (sem
  erro 500) — `Library.playlists` retorna `[]` se o diretório não
  existir.
- Playlist ou arquivo inexistente na URL: `WebServer` responde HTTP 404
  com página simples "Playlist/faixa não encontrada" + link para `/`.
- Tags corrompidas ou `python3`/`mutagen` indisponível: fallback baseado
  no nome do arquivo (ver seção `Library` acima).
- Parâmetro de URL que não corresponde a uma entrada real do disco: 404
  (mesma checagem que previne path traversal).

## Testes

- `test/exportify/library_test.rb` (novo):
  - `playlists` com diretório fixture contendo 2 subpastas: retorna nomes
    e contagens corretos, ordenado alfabeticamente.
  - `playlists` com `output_dir` inexistente: retorna `[]`.
  - `tracks` ordena por `track_number`; faixas sem tag vão para o fim.
  - `track` com tags válidas (stub de `Open3.capture3` retornando o JSON
    esperado): retorna hash completo incluindo `file_size_bytes`.
  - `track` com falha do `python3` (stub retornando status de erro): usa
    fallback do nome do arquivo.
  - `track`/`tracks` com nome de playlist ou arquivo que não existe no
    disco: retorna `nil` (proteção contra path traversal).
- `test/exportify/web_server_test.rb` (novo):
  - Sobe o servidor numa porta efêmera (`0` deixa o SO escolher, lida via
    `server.config[:Port]` após o bind), faz requests com `Net::HTTP`:
    - `GET /` → 200, contém nome de playlist fixture.
    - `GET /playlists/:nome` → 200, contém faixa fixture.
    - `GET /playlists/:nome/faixas/:arquivo` → 200, contém tag `<audio`.
    - `GET /playlists/inexistente` → 404.
- Lint: `bundle exec rubocop` nos novos arquivos (segue convenções já
  existentes: `frozen_string_literal`, aspas simples, 120 colunas).

## README

Atualizar a seção de uso para documentar:

```sh
bin/exportify web
bin/exportify web --port 8080
```

# Design: Análise de BPM + Key (tonalidade)

## Contexto

Hoje o `exportify` baixa playlists (Spotify / YouTube / YouTube Music) como
MP3 com tags ID3 e as exibe num app web somente leitura. As tags gravadas por
`Exportify::Tagger` são: título (`TIT2`), artistas (`TPE1`/`TPE2`), álbum
(`TALB`), ano (`TDRC`), número da faixa (`TRCK`) e gênero (`TCON`).

Falta o que é o coração do trabalho de DJ: **BPM (andamento)** e **key
(tonalidade)**. Quase toda ferramenta de DJ — mixagem harmônica, crates
inteligentes, montagem de setlist — depende dessas duas informações.

Este é o **primeiro passo** para transformar o `exportify` numa plataforma de
recursos para DJs: detectar BPM e key de cada faixa, gravar nas tags ID3 e
exibir no app web. É a fundação sobre a qual os próximos specs (mixagem
harmônica, crates inteligentes, export para software de DJ) vão se apoiar.

## Fora de escopo

- Mixagem harmônica / sugestão de faixas compatíveis (spec futuro).
- Crates inteligentes / organização automática por BPM/key (spec futuro).
- Export para Rekordbox / Serato / Traktor (spec futuro).
- Detecção de energia, danceability, waveform ou cue points.
- Disparar análise pelo app web (o app continua somente leitura; o design de
  ações no app web é tratado separadamente em `2026-07-09-web-actions-design.md`).

## Decisões de design

### Engine de análise: `keyfinder-cli` + `aubio`

Ferramentas dedicadas, com precisão de DJ real:

- **`keyfinder-cli`** (libKeyFinder) para tonalidade — mesma família de
  algoritmo do Mixed In Key / Rekordbox. Saída no formato de key musical
  padrão (ex.: `Abm`, `C`, `F#m`).
- **`aubio tempo`** para BPM.

Instaladas via `brew` (macOS) / `apt` (Linux), coerente com a dependência já
existente do `yt-dlp`. Alternativas descartadas: `librosa` (precisão de key
abaixo do padrão de DJ) e `essentia` (instalação pesada e frágil no macOS).

### Notação Camelot é derivada, não armazenada

Nas tags gravamos apenas:

- **`TBPM`**: BPM inteiro (ex.: `128`).
- **`TKEY`**: key musical padrão (ex.: `Abm`) — formato que Rekordbox e Serato
  leem nativamente.

O **código Camelot** (ex.: `1A`) usado pelos DJs para mixagem harmônica é
**derivado da key musical em Ruby puro** via uma tabela de mapeamento fixa das
24 tonalidades. Não é armazenado: evita redundância nas tags e é uma função
determinística que serve de base para o futuro motor de mixagem harmônica.

## Componentes

### `Exportify::Analyzer` (novo — `lib/exportify/analyzer.rb`)

```ruby
module Exportify
  module Analyzer
    module_function

    # Analisa um MP3 e retorna { bpm: Integer, key: String } ou nil em falha.
    def analyze(filepath)
      bpm = detect_bpm(filepath)   # aubio tempo
      key = detect_key(filepath)   # keyfinder-cli
      return nil unless bpm || key

      { bpm: bpm, key: key }
    end

    # "Abm" -> "1A". Retorna nil para keys desconhecidas.
    def camelot(key)
      CAMELOT[key]
    end

    CAMELOT = {
      # 24 tonalidades: maiores (B) e menores (A) da roda de Camelot
      'Abm' => '1A',  'B'  => '1B',
      'Ebm' => '2A',  'F#' => '2B',
      # ... (tabela completa das 24 keys)
    }.freeze
  end
end
```

- `detect_bpm` chama `aubio tempo <arquivo>` e parseia o BPM da saída
  (arredondado para inteiro).
- `detect_key` chama `keyfinder-cli <arquivo>` e retorna a string da key.
- Falha de uma das duas ferramentas não invalida a outra (grava o que
  conseguiu). Falha das duas → retorna `nil`, faixa fica sem análise.
- Comandos externos executados de forma que os testes possam mockar a saída
  (mesmo padrão de `Downloader`/`YouTube`).

### `Exportify::Tagger` (estendido)

Novo método `tag_analysis(filepath, bpm:, key:)` que grava **apenas** os frames
`TBPM` e `TKEY` num arquivo já taggeado, sem tocar nos demais frames:

```python
from mutagen.id3 import ID3, TBPM, TKEY, error
try:    tags = ID3(filepath)
except error: tags = ID3()
# grava TBPM só se bpm; TKEY só se key
tags.save(filepath)
```

Fica separado de `Tagger.tag` (metadados de título/artista/etc.) porque o
comando `analyze` roda sobre arquivos cujo hash de metadados original já não
está em mãos — ele só acrescenta BPM/key ao que existe. Se `bpm` e `key` forem
ambos `nil`, é um no-op (não invoca o Python).

### `Exportify::CLI` (estendido)

**Análise automática no download.** No loop de download de `run`, após
`Tagger.tag(filepath, track)` num download bem-sucedido, roda a análise e
regrava as tags de BPM/key — a menos que `--no-analyze` seja passado. Vale
também para o fluxo de vídeo com capítulos (`download_chaptered_video`), já que
opera arquivo a arquivo.

**Novo subcomando `analyze`.** Analisa faixas **já baixadas** operando sobre as
pastas locais (não sobre URL — resolver URL→pasta exigiria rede/credenciais só
pra descobrir o nome, o que contraria a proposta de processar o acervo local):

- `bin/exportify analyze "<nome da playlist>"` analisa uma pasta.
- `bin/exportify analyze --all` analisa todas as playlists (reaproveita
  `Library.playlists` / `Library.playlist_dir`, o mesmo modelo do app web).
- Para cada `*.mp3` da pasta, **pula** os que já têm `TBPM` **e** `TKEY`
  (idempotência, no mesmo espírito do "already exists, skipping" do download).
- `--reanalyze` força recalcular mesmo com tags presentes.
- Imprime resumo por playlist: `N analyzed, M skipped, K failed`.

**Flags novas:**

- `--no-analyze` — no fluxo de download, desliga a análise automática pontual.
- `--reanalyze` — no `analyze`, força recalcular.

Ler as tags existentes de um MP3 (pra decidir se pula) usa o mesmo caminho de
leitura ID3 já usado pela `Library` no app web.

### App web (`Library` + views)

- `Library` passa a expor `bpm` e `key` (e o Camelot derivado via
  `Analyzer.camelot`) na leitura de cada faixa.
- **Lista de faixas** (`playlist.html.erb`): badge `128 · 8A` por faixa.
- **Detalhe da faixa** (`track.html.erb`): BPM e key (musical + Camelot) junto
  das demais tags ID3.
- Badge neutro por ora; a coloração por key seguindo a roda de Camelot fica
  para o spec futuro de mixagem harmônica, que é quem realmente usa essa
  semântica visual. App continua somente leitura.

## Fluxo de dados

```
Download automático:
  download → tag (título, artista…) → analyze (aubio + keyfinder)
           → regrava TBPM/TKEY

Lote (acervo existente):
  analyze <url> → para cada *.mp3 sem BPM/key:
                    analyze → regrava TBPM/TKEY
```

## Dependências & instalação

- Novos binários: `keyfinder-cli`, `aubio`.
- `Makefile`: novo alvo `install-analysis` (brew no macOS / apt no Linux),
  incluído no `make install`. Passível de rodar isolado, como os demais.
- `README.md`: seção de requisitos e uso atualizada (`analyze`, `--no-analyze`,
  `--reanalyze`).

## Tratamento de erros

- Binário de análise ausente (`Errno::ENOENT`) → a detecção degrada para `nil`;
  no download automático segue normal (baixa e taggeia sem BPM/key, sem quebrar).
  O `README`/`Makefile` orientam a instalar via `make install-analysis`.
- Falha de análise em um arquivo específico → conta como `failed`, segue para
  o próximo (não aborta o lote).
- Saída inesperada das ferramentas → key desconhecida vira `nil` (sem Camelot),
  BPM não-parseável é ignorado.

## Testes

- `analyzer_test.rb`:
  - `analyze` mockando a saída de `aubio`/`keyfinder-cli` (sucesso, falha de
    uma ferramenta, falha das duas).
  - `camelot`: teste unitário puro cobrindo as **24 tonalidades** + key
    desconhecida → `nil`.
- `tagger_test.rb`: grava `TBPM`/`TKEY` quando presentes; não grava quando
  ausentes (retrocompatível).
- `cli_test.rb`: `analyze` pula faixas já analisadas; `--reanalyze` reprocessa;
  `--no-analyze` desliga a análise automática.
- `library_test.rb`: leitura expõe `bpm`, `key` e Camelot derivado.

## Sequência de implementação sugerida

1. `Analyzer` (detecção + tabela Camelot completa) com testes.
2. `Tagger` estendido (`TBPM`/`TKEY`) com testes.
3. Integração no download automático + flag `--no-analyze`.
4. Subcomando `analyze` + `--reanalyze` (idempotência).
5. `Library` + views (badges BPM/Camelot).
6. `Makefile` + `README` + `CHANGELOG`.

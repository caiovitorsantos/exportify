# Design: Download de vídeo único do YouTube com corte por capítulos

## Contexto

O `exportify` hoje aceita playlists (Spotify, YouTube, YouTube Music), mas
rejeita URLs de vídeo único (`youtube.com/watch?v=...`) com `Invalid
playlist URL`. Alguns vídeos do YouTube — mixes, compilações, álbuns
completos enviados como um único arquivo — usam **capítulos** (marcadores
de tempo com título) para indicar onde cada música começa e termina. Este
design adiciona suporte a baixar esse tipo de vídeo e separar
automaticamente em um arquivo MP3 por capítulo, com tags ID3 corretas por
faixa.

## Fora de escopo

- Detectar/repartir capítulos em playlists (isso já é tratado faixa a
  faixa, cada faixa é um vídeo próprio).
- Qualquer forma de detecção de música dentro do áudio (ex: silêncio,
  fingerprinting) — depende exclusivamente dos capítulos que o próprio
  vídeo já declara no YouTube.
- Vídeos privados/não listados sem capítulos declarados (fora do escopo,
  seguem o fluxo de faixa única já coberto).

## Detecção da origem

`Exportify::CLI.source_for(url)` passa a reconhecer URLs de vídeo único do
YouTube (`youtube.com/watch` com parâmetro `v=`) como uma nova origem
`:youtube_video`, além das já existentes (`:spotify`, `:youtube` para
playlists). Uma URL como
`https://www.youtube.com/watch?v=ID&list=RDxxx` (com parâmetro `list=`
apontando para um "Mix" automático do YouTube) é tratada como
`:youtube_video` — o `list=RD...` é ignorado, pois não é uma playlist real
navegável (é gerado dinamicamente pelo YouTube).

## Metadados do vídeo

Novo método `Exportify::YouTube.fetch_video(url, browser: nil)`:

1. Roda `yt-dlp -J --no-warnings <url>` (mesma chamada de metadado completo
   já usada em `fetch_playlist`, sem `--flat-playlist`).
2. Se `data['chapters']` existir e não for vazio, monta uma faixa por
   capítulo:
   - `artist`/`name`: `split_title(chapter['title'], data['uploader'] ||
     data['channel'])` (reaproveita o método já existente).
   - `raw_name`: título original do capítulo.
   - `album`: título do vídeo.
   - `year`: `data['release_year'].to_s` (mesmo campo já usado em
     `fetch_playlist`).
   - `track_number`: índice do capítulo (1-based).
   - `genre`: `''`.
   - `video_id`: id do vídeo (igual para todas as faixas).
   - `chapter_start` / `chapter_end`: `chapter['start_time']` /
     `chapter['end_time']`, usados só pelo passo de download.
3. Se não houver capítulos, monta uma única faixa a partir do vídeo inteiro
   (mesma lógica de `build_track` já usada para entradas de playlist, sem
   os campos `chapter_start`/`chapter_end`).

Retorno: `{ name:, tracks:, chaptered: true|false }`. `name` é o título do
vídeo (usado como nome da subpasta, igual ao nome da playlist hoje).

## Download e corte por capítulos

Diferente do fluxo atual (uma chamada ao `yt-dlp` por faixa), cortar por
capítulos exige baixar e processar o vídeo inteiro **de uma vez**: não é
possível baixar só um capítulo sem rebaixar o vídeo completo a cada
chamada. Por isso, o caso `chaptered: true` **não** passa pelo loop
compartilhado de "uma faixa por vez" — ganha um método dedicado,
`CLI.download_chaptered_video(data, output_dir)`, chamado antes do loop
principal:

1. Calcula os nomes de arquivo esperados (`sanitize(artist) -
   sanitize(name).mp3`) para cada faixa.
2. Se todos os arquivos esperados já existirem, pula o vídeo inteiro
   (mensagem `"(já baixado, pulando)"`) e não roda `yt-dlp` de novo.
3. Senão, roda uma única chamada:
   ```
   yt-dlp <video_url> --extract-audio --audio-format mp3 --audio-quality 0 \
     --split-chapters \
     --paths "<output_dir>" \
     --output "chapter:%(section_number)s - %(section_title)s.%(ext)s" \
     --output "%(title)s.%(ext)s" \
     --no-warnings --quiet
   ```
   usando `--paths` para direcionar a saída ao `output_dir`, sem alterar o
   diretório de trabalho do processo Ruby (evita efeitos colaterais de
   `Dir.chdir` em um processo que pode rodar outras tarefas).
4. Para cada capítulo `i` (1-based), localiza o arquivo gerado pelo yt-dlp
   por prefixo numérico (`Dir.glob("#{output_dir}/#{i} - *.mp3").first`,
   já que o título usado pelo yt-dlp no nome do arquivo pode ter sanitização
   ligeiramente diferente da nossa) e o renomeia para o padrão do projeto
   (`sanitize(artist) - sanitize(name).mp3`).
5. Aplica `Tagger.tag(filepath, track)` em cada arquivo renomeado, com os
   metadados computados no passo de metadados (artista, álbum = título do
   vídeo, número da faixa = índice do capítulo).
6. Apaga o arquivo do vídeo completo (não cortado) gerado pela chamada
   acima — mantém só as faixas separadas por capítulo.

Retorna contadores (`ok`, `skip`, `failed`) no mesmo formato usado pelo
resumo final já existente (`"Done: N downloaded, N skipped, N failed"`).

## Fluxo sem capítulos

Quando `chaptered: false`, a faixa única gerada por `fetch_video` é tratada
exatamente como qualquer faixa de playlist hoje: passa pelo loop
compartilhado existente em `CLI.run` (download via `Downloader.download`,
que já sabe baixar direto por `video_id`), incluindo suporte a
`--retag`/`--sync`. Nenhum código novo é necessário para esse caso — só a
detecção de origem e a chamada a `fetch_video` em vez de `fetch_playlist`.

## `--retag` e `--sync`

- `--retag`: no caso `chaptered: true`, itera as faixas já computadas e
  reaplica `Tagger.tag` nos arquivos existentes (mesmo padrão do fluxo
  padrão hoje) — não baixa nada de novo.
- `--sync`: remove do disco arquivos `.mp3` na subpasta que não estão na
  lista de faixas esperadas — reaproveita a lógica já existente sem
  mudanças, já que opera sobre a lista de faixas computada, independente
  da origem.

## Tratamento de erros

- `yt-dlp -J` falha (vídeo removido, privado sem cookies, URL inválida):
  aborta exibindo o `stderr`, igual ao padrão já usado em
  `fetch_playlist`.
- `yt-dlp --split-chapters` falha na etapa de download: aborta o vídeo
  inteiro (não há como recuperar parcialmente — sem o arquivo processado,
  não há capítulos pra taguear), reportando erro claro.
- Capítulo sem título (raro, mas possível): usa uma string vazia como
  título, cai no fallback de `split_title` (usa o canal como artista, nome
  vazio) — mesma tolerância já aplicada a outros campos ausentes no fluxo
  de playlist.

## Testes

- `test/exportify/youtube_test.rb`:
  - `fetch_video` com JSON de vídeo com capítulos: retorna `chaptered:
    true` e uma faixa por capítulo, com `chapter_start`/`chapter_end`
    corretos.
  - `fetch_video` com JSON de vídeo sem capítulos: retorna `chaptered:
    false` e uma única faixa.
  - Erro do yt-dlp: aborta exibindo stderr (mesmo padrão já testado para
    `fetch_playlist`).
- `test/exportify/cli_test.rb`:
  - `source_for` reconhece `youtube.com/watch?v=...` (com e sem `list=`)
    como `:youtube_video`.
  - `download_chaptered_video` (ou o nome final do método): pula o vídeo
    inteiro quando todos os arquivos esperados já existem (usando
    `Dir.mktmpdir`, sem stub de `yt-dlp` real).

## README

Nova seção documentando o uso:

```sh
exportify "https://www.youtube.com/watch?v=ID"
```

Explicando que, se o vídeo tiver capítulos, cada um vira uma faixa
separada automaticamente; senão, baixa como uma faixa única.

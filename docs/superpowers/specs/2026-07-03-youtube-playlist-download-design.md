# Design: Download de playlists do YouTube / YouTube Music

## Contexto

Hoje o `exportify` só aceita URLs de playlist do Spotify. A extração da lista
de faixas usa a API do Spotify (`Exportify::Spotify`), e o download de áudio
usa `yt-dlp` fazendo uma busca "cega" (`ytsearch1:`) por cada faixa.

Este design adiciona suporte a URLs de playlist do **YouTube** e do
**YouTube Music** como uma segunda origem, baixando as faixas como MP3 com
tags ID3 e organizando em subpastas — reaproveitando o pipeline de
download/tag/sync já existente.

## Fora de escopo

- Criar ou sincronizar playlists no YouTube a partir do Spotify (não é o que
  foi pedido).
- Autenticação OAuth com o Google/YouTube Data API.
- Suporte a playlists de outras origens além de YouTube/YouTube Music.

## Detecção da origem

`Exportify::CLI` passa a inspecionar a URL recebida como argumento para
decidir qual fluxo usar:

```ruby
def source_for(url)
  return :spotify if url.include?('open.spotify.com')
  return :youtube if url.match?(%r{(music\.)?youtube\.com/playlist})

  nil
end
```

Se `source_for` retornar `nil`, o comando aborta com `'Invalid playlist URL'`
(mesma mensagem já usada hoje).

## Listagem das faixas (YouTube)

Novo módulo `lib/exportify/youtube.rb`, responsável por obter nome da
playlist e lista de faixas em **uma única chamada** ao `yt-dlp`, sem exigir
API key nem OAuth:

```
yt-dlp --flat-playlist -J --no-warnings <url> [--cookies-from-browser <browser>]
```

- `--flat-playlist` evita que o yt-dlp resolva metadados completos de cada
  vídeo individualmente (mais rápido, evita custo extra de rede por faixa).
- `--cookies-from-browser <browser>` é opcional, usado apenas quando a flag
  `--browser` for passada na CLI, para permitir acesso a playlists privadas
  do usuário logado naquele navegador.
- A saída é um JSON com `title` (nome da playlist) e `entries` (lista de
  vídeos, cada um com `id`, `title`, `uploader`/`channel`).

`Exportify::YouTube.fetch_playlist(url, browser: nil)` retorna:

```ruby
{
  name: "Nome da Playlist",
  tracks: [
    {
      artist: "...",
      all_artists: "...",       # igual a artist (YouTube não tem multi-artista estruturado)
      name: "...",
      raw_name: "...",          # título original do vídeo, sem parsing
      album: "Nome da Playlist",
      year: '',                 # não disponível de forma confiável em modo flat
      track_number: 1,          # índice na playlist (1-based)
      genre: '',                # não disponível
      video_id: "dQw4w9WgXcQ"   # usado pelo Downloader para baixar direto, sem buscar
    },
    ...
  ]
}
```

### Separação artista/título

Como o YouTube não tem campos estruturados de artista/álbum como o Spotify,
`YouTube.split_title` tenta o padrão comum `"Artista - Título"` no título do
vídeo:

```ruby
def split_title(title, fallback_artist)
  if title =~ /\A(.+?)\s*-\s*(.+)\z/
    [Regexp.last_match(1).strip, Regexp.last_match(2).strip]
  else
    [fallback_artist.to_s, title.to_s]
  end
end
```

Se não casar o padrão, usa o nome do canal/uploader como artista e o título
completo como nome da faixa.

## Download (reaproveitando `Downloader`)

`Exportify::Downloader.download` passa a verificar se a faixa já tem um
`video_id` (origem YouTube). Se tiver, baixa o vídeo diretamente pela URL
(sem busca); senão, mantém o comportamento atual de busca via `ytsearch1:`
(origem Spotify):

```ruby
def download(track, output_dir)
  artist   = sanitize(track[:artist])
  name     = sanitize(track[:name])
  template = File.join(output_dir, "#{artist} - #{name}.%(ext)s")

  source = if track[:video_id]
             "https://www.youtube.com/watch?v=#{track[:video_id]}"
           else
             "ytsearch1:#{track[:raw_name]} #{track[:all_artists]} official audio"
           end

  system(
    'yt-dlp', source,
    '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
    '--output', template,
    '--no-playlist', '--quiet', '--no-warnings'
  )
end
```

`Exportify::Tagger.tag` não muda — já consome os mesmos campos
(`raw_name`, `all_artists`, `artist`, `album`, `year`, `track_number`,
`genre`) que a estrutura de track do YouTube também preenche (com `year` e
`genre` em branco quando não disponíveis).

## Mudanças no `Exportify::CLI`

1. **Banner** atualizado para mencionar URLs do YouTube/YouTube Music e a
   nova flag `--browser`.
2. **Nova flag** `--browser=NOME` (opcional): repassada como
   `browser:` para `YouTube.fetch_playlist`, usada só no fluxo YouTube.
3. **Refatoração do método `run`**: a etapa "obter nome + faixas da
   playlist" passa a ramificar por origem (`Spotify.playlist_name` +
   `Spotify.playlist_tracks` vs `YouTube.fetch_playlist`), mas o restante do
   pipeline (criar `output_dir`, loop de download/retag, resumo, `--sync`)
   permanece **um único bloco compartilhado**, sem duplicação entre as duas
   origens.
4. Autenticação com Spotify (`Auth.access_token`) só é acionada quando
   `source == :spotify` — o fluxo YouTube não precisa de nenhuma credencial
   por padrão.

## Tratamento de erros

- `yt-dlp` retorna exit code diferente de zero (playlist inexistente,
  privada sem cookies, URL inválida): aborta exibindo o `stderr` capturado,
  para o usuário ver a causa real reportada pelo próprio yt-dlp.
- Playlist processa mas retorna zero `entries` (ex: playlist vazia): aborta
  com mensagem `'Playlist do YouTube vazia ou inacessível.'`.
- Falha de download de uma faixa individual (vídeo removido, indisponível
  por região, etc.): mantém o comportamento atual do `Downloader.download`
  — não aborta o comando inteiro, apenas conta como falha no resumo final
  (`ok`/`skip`/`failed`), igual já acontece hoje para faixas do Spotify que
  não são encontradas no YouTube.

## Testes

- `test/exportify/youtube_test.rb` (novo):
  - `fetch_playlist` com JSON de exemplo (stub de `Open3.capture3`):
    retorna `name` e `tracks` corretos.
  - `split_title` com título no padrão `"Artista - Título"` e sem esse
    padrão (usa uploader como fallback).
  - Erro do yt-dlp (`status.success?` falso): aborta exibindo stderr.
  - Playlist com `entries` vazio: aborta com mensagem específica.
- `test/exportify/downloader_test.rb` (atualizar):
  - Track com `video_id` presente: comando `yt-dlp` é chamado com a URL
    direta do vídeo, sem `ytsearch1:`.
  - Track sem `video_id` (Spotify): comportamento atual inalterado.
- `test/exportify/cli_test.rb` (atualizar):
  - `source_for` reconhece `youtube.com/playlist?list=...` e
    `music.youtube.com/playlist?list=...` como `:youtube`.
  - URL de origem desconhecida continua abortando com `'Invalid playlist
    URL'`.

## README

Atualizar a seção de uso para documentar:

```sh
exportify https://www.youtube.com/playlist?list=<id>
exportify https://music.youtube.com/playlist?list=<id>
exportify https://www.youtube.com/playlist?list=<id> --browser=chrome  # playlists privadas
```

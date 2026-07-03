# Exportify

Downloads a Spotify playlist as MP3 files with proper ID3 tags (title, artist, album, year, track number, genre).

## Requirements

- Ruby 3.3+
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — `brew install yt-dlp`
- Python 3 + [mutagen](https://mutagen.readthedocs.io/) — `pip3 install mutagen`
- A Spotify Developer application

## Setup

1. Create an app at [developer.spotify.com](https://developer.spotify.com/dashboard).
2. Add `http://127.0.0.1:8888/callback` as a Redirect URI in the app settings.
3. Export your credentials:

```sh
export SPOTIFY_CLIENT_ID=your_client_id
export SPOTIFY_CLIENT_SECRET=your_client_secret
```

4. Install the gem dependencies:

```sh
bundle install
```

## Usage

### Definir o diretório principal

Por padrão os arquivos são salvos em `musics/` dentro do projeto. Para usar outro caminho:

```sh
bin/exportify init ~/Music
```

A configuração é salva em `~/.exportify` e vale para todos os comandos seguintes. Para voltar ao padrão:

```sh
bin/exportify init
```

### Baixar uma playlist

```sh
bin/exportify https://open.spotify.com/playlist/<playlist_id>
```

Os arquivos são organizados em subdiretórios pelo nome da playlist:

```
musics/
  Rock dos Anos 80/
    Queen - Bohemian Rhapsody.mp3
    David Bowie - Heroes.mp3
  Trap Brasil/
    ...
```

Faixas que já existem no disco são ignoradas automaticamente. Rodar o comando novamente após adicionar músicas à playlist baixa apenas as novas.

### Sincronização bidirecional

Para remover do disco as músicas que foram retiradas da playlist:

```sh
bin/exportify https://open.spotify.com/playlist/<playlist_id> --sync
```

### Regravar tags ID3

Para atualizar as tags dos arquivos já baixados sem rebaixar:

```sh
bin/exportify https://open.spotify.com/playlist/<playlist_id> --retag
```

## Notas

- O token OAuth é cacheado em `~/.exportify_token.json` e renovado automaticamente quando expira. Se a sessão for revogada, o arquivo é removido e um novo login é solicitado.
- Playlists de artistas oficiais ou gravadoras podem retornar erro 403 — isso é uma restrição da API do Spotify para apps de terceiros sem acesso estendido.

# Exportify

Downloads a Spotify playlist as MP3 files with proper ID3 tags (title, artist, album, year, track number, genre).

## Requirements

- Ruby 3.3+
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — `brew install yt-dlp`
- Python 3 + [mutagen](https://mutagen.readthedocs.io/) — `pip3 install mutagen`
- A Spotify Developer application
- Para playlists do YouTube/YouTube Music não é necessária nenhuma credencial adicional — só o `yt-dlp`.

## Setup

1. Crie um app em [developer.spotify.com](https://developer.spotify.com/dashboard).
2. Adicione `http://127.0.0.1:8888/callback` como Redirect URI nas configurações do app.
3. Instale as dependências:

```sh
make install
```

Isso verifica a versão do Ruby, instala o yt-dlp (via Homebrew no macOS ou apt no Linux), instala o mutagen (Python) e roda `bundle install`. Cada etapa pode ser rodada isoladamente (`make check-ruby`, `make install-yt-dlp`, `make install-mutagen`, `make bundle`) — veja `make help` para a lista completa. Se preferir instalar manualmente, veja a seção [Requirements](#requirements) acima.

4. Execute o setup interativo:

```sh
bin/exportify init
```

```
=== Exportify Setup ===

Diretório principal [musics]: ~/Music
Spotify Client ID: <seu client id>
Spotify Client Secret: ████████

Configuração salva em ~/.exportify
```

As credenciais e o diretório ficam salvos em `~/.exportify` (permissão `600`). Para reconfigurar qualquer campo, execute `init` novamente — Enter em branco mantém o valor atual.

> **Alternativa:** as variáveis de ambiente `SPOTIFY_CLIENT_ID` e `SPOTIFY_CLIENT_SECRET` têm prioridade sobre o arquivo de configuração, útil em ambientes de CI.

## Usage

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

## Desenvolvimento

```sh
bundle exec rake test      # testes
bundle exec rubocop        # lint
bundle exec bundler-audit check --update  # vulnerabilidades em dependências
```

O CI roda os três automaticamente a cada push.

## Release

Para publicar uma nova versão no RubyGems:

1. Atualize `lib/exportify/version.rb`
2. Crie e faça push da tag:

```sh
git tag v1.0.0
git push --tags
```

O workflow de release dispara automaticamente e publica a gem. Requer o secret `RUBYGEMS_API_KEY` configurado em Settings → Secrets → Actions do repositório.

Veja o [CHANGELOG.md](CHANGELOG.md) para o histórico de versões.

## Notas

- O token OAuth é cacheado em `~/.exportify_token.json` e renovado automaticamente quando expira. Se a sessão for revogada, o arquivo é removido e um novo login é solicitado.
- Playlists de artistas oficiais ou gravadoras podem retornar erro 403 — isso é uma restrição da API do Spotify para apps de terceiros sem acesso estendido.

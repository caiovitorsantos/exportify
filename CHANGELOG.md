# Changelog

Todas as mudanças notáveis deste projeto são documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e este projeto segue [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Added

- Suporte a download de playlists do YouTube e YouTube Music (além do
  Spotify), incluindo playlists privadas via `--browser` (cookies do
  navegador).
- Suporte a download de um vídeo único do YouTube com corte automático por
  capítulos (um MP3 por capítulo, com tags ID3 corretas); sem capítulos,
  baixa como uma faixa única.
- Detecção automática de BPM e tonalidade (key) no download, gravadas nas tags
  ID3 (`TBPM`/`TKEY`); desligável com `--no-analyze`.
- Subcomando `analyze` para detectar BPM/key de faixas já baixadas
  (`analyze "<playlist>"` ou `analyze --all`, com `--reanalyze` para recalcular).
- Exibição de BPM e tonalidade em notação Camelot no app web.

## [1.0.1] - 2026-07-03

### Added

- `Makefile` com target `install` para preparar o ambiente automaticamente
  (verifica a versão do Ruby, instala yt-dlp e mutagen, roda `bundle install`).

## [1.0.0] - 2026-07-03

### Added

- Download de playlists do Spotify como arquivos MP3 com tags ID3 completas
  (título, artista, álbum, ano, número da faixa, gênero).
- Comando `init` para configurar interativamente credenciais do Spotify e
  diretório de saída.
- Organização dos downloads em subdiretórios por nome da playlist.
- Flag `--sync` para remover do disco arquivos que saíram da playlist.
- Flag `--retag` para regravar as tags ID3 de arquivos já baixados sem
  precisar rebaixá-los.
- Cache do token OAuth com renovação automática.
- Pipeline de CI com testes, RuboCop e bundler-audit, além de workflow de
  release automatizado para publicação no RubyGems.

### Fixed

- Descarte da query string (parâmetros após `?`) da URL da playlist antes de
  extrair o ID.

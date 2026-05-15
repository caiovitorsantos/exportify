# Exportify

Downloads a Spotify playlist as MP3 files with proper ID3 tags (title, artist, album, year, track number).

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

Download all tracks from a playlist:

```sh
bin/exportify https://open.spotify.com/playlist/<playlist_id>
```

Retag all already-downloaded files without re-downloading:

```sh
bin/exportify https://open.spotify.com/playlist/<playlist_id> --retag
```

MP3 files are saved to `~/projects/exportify/musics/` as `Artist - Track.mp3`. Tracks that already exist on disk are skipped automatically.

The OAuth token is cached at `~/.exportify_token.json` and refreshed automatically when it expires.

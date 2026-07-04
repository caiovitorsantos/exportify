# frozen_string_literal: true

require 'json'
require 'open3'

module Exportify
  module YouTube
    module_function

    def fetch_playlist(url, browser: nil)
      cmd = ['yt-dlp', '--flat-playlist', '-J', '--no-warnings', url]
      cmd += ['--cookies-from-browser', browser] if browser

      stdout, stderr, status = Open3.capture3(*cmd)
      abort "Erro ao acessar playlist do YouTube: #{stderr.strip}" unless status.success?

      data    = JSON.parse(stdout)
      entries = data['entries'] || []
      abort 'Playlist do YouTube vazia ou inacessível.' if entries.empty?

      playlist_name = data['title'] || 'YouTube Playlist'

      {
        name: playlist_name,
        tracks: entries.each_with_index.map { |entry, i| build_track(entry, i, playlist_name) }
      }
    end

    def build_track(entry, index, playlist_name)
      artist, name = split_title(entry['title'].to_s, entry['uploader'] || entry['channel'])

      {
        artist: artist,
        all_artists: artist,
        name: name,
        raw_name: entry['title'].to_s,
        album: playlist_name,
        year: '',
        track_number: index + 1,
        genre: '',
        video_id: entry['id']
      }
    end

    def split_title(title, fallback_artist)
      if title =~ /\A(.+?)\s*-\s*(.+)\z/
        [Regexp.last_match(1).strip, Regexp.last_match(2).strip]
      else
        [fallback_artist.to_s, title.to_s]
      end
    end
  end
end

# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Exportify
  module Spotify
    module_function

    def playlist_name(playlist_id, token)
      uri = URI("https://api.spotify.com/v1/playlists/#{playlist_id}?fields=name")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{token}"
      res  = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      data = JSON.parse(res.body)
      handle_error!(data['error'], 'playlist')
      data['name']
    end

    def playlist_tracks(playlist_id, token)
      tracks = []
      url    = "https://api.spotify.com/v1/playlists/#{playlist_id}/items?limit=100"

      while url
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{token}"
        res  = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
        data = JSON.parse(res.body)
        handle_error!(data['error'], 'tracks')

        data['items'].each do |item|
          track = item['item']
          next if track.nil? || track['name'].nil?

          clean_name = track['name']
                       .gsub(/\s*[(\[].*?[)\]]/, '')
                       .gsub(/\s*-\s*(feat|ft)\.?.*/i, '')
                       .strip

          tracks << {
            artist: track['artists'].first['name'],
            artist_id: track['artists'].first['id'],
            all_artists: track['artists'].map { |a| a['name'] }.join(', '),
            name: clean_name,
            raw_name: track['name'],
            album: track.dig('album', 'name') || '',
            year: (track.dig('album', 'release_date') || '')[0..3],
            track_number: track['track_number'] || 0,
            genre: ''
          }
        end

        url = data['next']
      end

      tracks
    end

    def handle_error!(error, context)
      return unless error

      status  = error['status']
      message = error['message']

      case status
      when 401
        abort "Erro #{status}: token inválido ou expirado. Apague ~/.exportify_token.json e tente novamente."
      when 403
        abort "Erro 403 ao buscar #{context}: acesso negado pelo Spotify.\n" \
              "Isso ocorre em playlists de artistas ou gravadoras com conteúdo protegido.\n" \
              'Tente com uma playlist pessoal ou pública de outro usuário.'
      when 404
        abort 'Erro 404: playlist não encontrada. Verifique se o link está correto.'
      else
        abort "Erro da API Spotify (#{status}): #{message}"
      end
    end

    def enrich_with_genres(tracks, token)
      artist_ids = tracks.map { |t| t[:artist_id] }.uniq.compact
      genres_by_id = {}

      artist_ids.each do |artist_id|
        uri = URI("https://api.spotify.com/v1/artists/#{artist_id}")
        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{token}"
        res  = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
        data = JSON.parse(res.body)
        handle_error!(data['error'], 'artistas')
        genres_by_id[data['id']] = (data['genres'] || []).first || ''
      end

      tracks.map { |t| t.merge(genre: genres_by_id[t[:artist_id]] || '') }
    end
  end
end

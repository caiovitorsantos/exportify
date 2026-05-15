# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Exportify
  module Spotify
    module_function

    def playlist_tracks(playlist_id, token)
      tracks = []
      url    = "https://api.spotify.com/v1/playlists/#{playlist_id}/items?limit=100"

      while url
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{token}"
        res  = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
        data = JSON.parse(res.body)
        abort "Erro da API Spotify: #{data['error']}" if data['error']

        data['items'].each do |item|
          track = item['item']
          next if track.nil? || track['name'].nil?

          clean_name = track['name']
            .gsub(/\s*[\(\[].*?[\)\]]/, '')
            .gsub(/\s*-\s*(feat|ft)\.?.*/i, '')
            .strip

          tracks << {
            artist:       track['artists'].first['name'],
            all_artists:  track['artists'].map { |a| a['name'] }.join(', '),
            name:         clean_name,
            raw_name:     track['name'],
            album:        track.dig('album', 'name') || '',
            year:         (track.dig('album', 'release_date') || '')[0..3],
            track_number: track['track_number'] || 0
          }
        end

        url = data['next']
      end

      tracks
    end
  end
end

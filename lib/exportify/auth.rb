# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'base64'
require 'webrick'

module Exportify
  module Auth
    TOKEN_FILE   = File.expand_path('~/.exportify_token.json')
    REDIRECT_URI = 'http://127.0.0.1:8888/callback'
    SCOPES       = 'playlist-read-private playlist-read-collaborative'

    module_function

    def save_token(data)
      data['expires_at'] = Time.now.to_i + data['expires_in'].to_i
      File.write(TOKEN_FILE, JSON.generate(data))
      data
    end

    def load_token
      return nil unless File.exist?(TOKEN_FILE)

      JSON.parse(File.read(TOKEN_FILE))
    end

    def refresh_token(token_data)
      uri = URI('https://accounts.spotify.com/api/token')
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = 'Basic ' + Base64.strict_encode64("#{client_id}:#{client_secret}")
      req.set_form_data(
        'grant_type'    => 'refresh_token',
        'refresh_token' => token_data['refresh_token']
      )
      res  = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      data = JSON.parse(res.body)
      data['refresh_token'] ||= token_data['refresh_token']
      save_token(data)
    end

    def exchange_code(code)
      uri = URI('https://accounts.spotify.com/api/token')
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = 'Basic ' + Base64.strict_encode64("#{client_id}:#{client_secret}")
      req.set_form_data(
        'grant_type'   => 'authorization_code',
        'code'         => code,
        'redirect_uri' => REDIRECT_URI
      )
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      save_token(JSON.parse(res.body))
    end

    def authorize!
      params = URI.encode_www_form(
        client_id:     client_id,
        response_type: 'code',
        redirect_uri:  REDIRECT_URI,
        scope:         SCOPES
      )
      url = "https://accounts.spotify.com/authorize?#{params}"

      puts "\nAbrindo navegador para login no Spotify..."
      puts "Se não abrir automaticamente, acesse:\n#{url}\n"
      system("open '#{url}'")

      code   = nil
      server = WEBrick::HTTPServer.new(
        Port:        8888,
        BindAddress: '127.0.0.1',
        Logger:      WEBrick::Log.new(File::NULL),
        AccessLog:   []
      )
      server.mount_proc('/callback') do |req, res|
        code          = req.query['code']
        res.body      = '<html><body><h2>Login realizado! Pode fechar esta aba.</h2></body></html>'
        res['Content-Type'] = 'text/html'
        server.shutdown
      end
      server.start

      abort 'Login cancelado' unless code
      exchange_code(code)
    end

    def access_token
      token = load_token
      if token.nil?
        token = authorize!
      elsif Time.now.to_i >= token['expires_at'].to_i - 60
        token = refresh_token(token)
      end
      token['access_token']
    end

    def client_id
      ENV['SPOTIFY_CLIENT_ID']
    end

    def client_secret
      ENV['SPOTIFY_CLIENT_SECRET']
    end
  end
end

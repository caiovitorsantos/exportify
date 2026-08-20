# frozen_string_literal: true

require 'webrick'
require 'erb'
require 'uri'
require 'json'
require 'rbconfig'
require_relative 'library'
require_relative 'config'
require_relative 'cover'
require_relative 'jobs'
require_relative 'cli'

module Exportify
  module WebServer # rubocop:disable Metrics/ModuleLength
    ROOT_DIR   = File.expand_path('../..', __dir__)
    VIEWS_DIR  = File.join(ROOT_DIR, 'views')
    PUBLIC_DIR = File.join(ROOT_DIR, 'public')
    EXPORTIFY_BIN = File.join(ROOT_DIR, 'bin', 'exportify')

    module_function

    def start(port: 4567)
      server = build_server(port)

      trap('INT') { server.shutdown }
      puts "Servidor rodando em http://localhost:#{server.config[:Port]}"
      server.start
    end

    def build_server(port)
      server = WEBrick::HTTPServer.new(Port: port, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])

      server.mount('/library', WEBrick::HTTPServlet::FileHandler, File.expand_path(Config.output_dir))
      server.mount('/assets', WEBrick::HTTPServlet::FileHandler, PUBLIC_DIR)
      server.mount_proc('/') { |req, res| handle_request(req, res) }

      server
    end

    def handle_request(req, res)
      return handle_post(req, res) if req.request_method == 'POST'

      case req.path
      when '/'
        render_index(res)
      when %r{\A/jobs/([^/]+)\z}
        render_job_status(res, Regexp.last_match(1))
      when %r{\A/playlists/([^/]+)/faixas/([^/]+)\z}
        render_track(
          res,
          URI.decode_www_form_component(Regexp.last_match(1)),
          URI.decode_www_form_component(Regexp.last_match(2))
        )
      when %r{\A/playlists/([^/]+)\z}
        render_playlist(res, URI.decode_www_form_component(Regexp.last_match(1)))
      else
        render_not_found(res)
      end
    end

    def handle_post(req, res)
      case req.path
      when '/playlists'
        create_playlist(req, res)
      when %r{\A/playlists/([^/]+)/retag\z}
        run_playlist_action(req, res, URI.decode_www_form_component(Regexp.last_match(1)), '--retag')
      when %r{\A/playlists/([^/]+)/sync\z}
        run_playlist_action(req, res, URI.decode_www_form_component(Regexp.last_match(1)), '--sync')
      else
        render_not_found(res)
      end
    end

    def create_playlist(req, res)
      url = req.query['url'].to_s.strip

      return render_json(res, 400, error: 'URL inválida. Use um link de playlist do Spotify ou YouTube.') \
        unless CLI.source_for(url)

      return render_json(res, 400, error: 'URL inválida.') if url.start_with?('-')

      browser = Library.presence(req.query['browser'])
      cmd = [RbConfig.ruby, EXPORTIFY_BIN, url]
      cmd << "--browser=#{browser}" if browser

      render_json(res, 202, job_id: Jobs.start(cmd))
    end

    def run_playlist_action(req, res, playlist_name, flag)
      return render_json(res, 404, error: 'Playlist não encontrada.') unless Library.playlist_dir(playlist_name)

      source = PlaylistMeta.read(playlist_name)
      url = source ? source[:url] : Library.presence(req.query['url'])

      return render_json(res, 422, error: 'Informe a URL de origem desta playlist.') unless url
      return render_json(res, 400, error: 'URL inválida.') if url.start_with?('-')

      browser = source ? source[:browser] : nil
      cmd = [RbConfig.ruby, EXPORTIFY_BIN, url, flag]
      cmd << "--browser=#{browser}" if browser

      render_json(res, 202, job_id: Jobs.start(cmd))
    end

    def render_job_status(res, job_id)
      status = Jobs.status(job_id)
      return render_json(res, 404, error: 'Job não encontrado.') unless status

      render_json(res, 200, status)
    end

    def render_json(res, code, payload)
      res.status = code
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate(payload)
    end

    def render_index(res)
      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template('index', playlists: Library.playlists)
    end

    def render_playlist(res, name)
      tracks = Library.tracks(name)
      return render_not_found(res, 'Playlist não encontrada.') unless tracks

      res['Content-Type'] = 'text/html; charset=utf-8'
      genres = tracks.filter_map { |track| track[:genre] }.uniq.sort
      res.body = render_template(
        'playlist',
        playlist_name: name, tracks: tracks, genres: genres, source: PlaylistMeta.read(name)
      )
    end

    def render_track(res, playlist_name, filename)
      track = Library.track(playlist_name, filename)
      return render_not_found(res, 'Faixa não encontrada.') unless track

      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template(
        'track',
        playlist_name: playlist_name,
        filename: filename,
        track: track,
        duration: format_duration(track[:duration_seconds]),
        file_size: format_file_size(track[:file_size_bytes])
      )
    end

    def format_duration(seconds)
      return '—' unless seconds

      total = seconds.round
      format('%<minute>d:%<second>02d', minute: total / 60, second: total % 60)
    end

    def format_file_size(bytes)
      return '—' unless bytes

      if bytes >= 1_048_576
        format('%.1f MB', bytes / 1_048_576.0)
      else
        format('%.1f KB', bytes / 1024.0)
      end
    end

    def render_not_found(res, message = 'Página não encontrada.')
      res.status = 404
      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template('not_found', message: message)
    end

    def render_template(name, locals)
      content = render_erb("#{name}.html.erb", locals)
      render_erb('layout.html.erb', locals.merge(content: content))
    end

    def render_erb(filename, locals)
      path    = File.join(VIEWS_DIR, filename)
      context = TemplateContext.new(locals)
      ERB.new(File.read(path), trim_mode: '-').result(context.template_binding)
    end

    class TemplateContext
      def initialize(locals)
        @locals = locals
        locals.each_key do |key|
          instance_variable_set(:"@#{key}", locals[key])
          define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        end
      end

      def template_binding
        binding
      end

      def render_partial(name)
        WebServer.render_erb("_#{name}.html.erb", @locals)
      end
    end
  end
end

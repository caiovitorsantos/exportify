# frozen_string_literal: true

require 'webrick'
require 'erb'
require 'uri'
require_relative 'library'
require_relative 'config'

module Exportify
  module WebServer
    ROOT_DIR   = File.expand_path('../..', __dir__)
    VIEWS_DIR  = File.join(ROOT_DIR, 'views')
    PUBLIC_DIR = File.join(ROOT_DIR, 'public')

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
      case req.path
      when '/'
        render_index(res)
      else
        render_not_found(res)
      end
    end

    def render_index(res)
      res['Content-Type'] = 'text/html; charset=utf-8'
      res.body = render_template('index', playlists: Library.playlists)
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
        locals.each_key do |key|
          instance_variable_set(:"@#{key}", locals[key])
          define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        end
      end

      def template_binding
        binding
      end
    end
  end
end

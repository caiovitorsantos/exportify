# frozen_string_literal: true

require_relative 'lib/exportify/version'

Gem::Specification.new do |spec|
  spec.name        = 'exportify'
  spec.version     = Exportify::VERSION
  spec.authors     = ['Caio Santos']
  spec.email       = ['caiovitor.santos@gmail.com']

  spec.summary     = 'Download Spotify playlists as MP3 files with proper ID3 tags'
  spec.description = 'Exportify authenticates with Spotify via OAuth, fetches all tracks ' \
                     'from a playlist, downloads each one as an MP3 using yt-dlp, and ' \
                     'writes accurate ID3 tags (title, artist, album, year, track number) ' \
                     'via mutagen.'

  spec.required_ruby_version = '>= 3.0'

  spec.files         = Dir['lib/**/*.rb', 'bin/*', 'README.md', 'exportify.gemspec']
  spec.bindir        = 'bin'
  spec.executables   = ['exportify']
  spec.require_paths = ['lib']

  spec.add_dependency 'webrick', '~> 1.9'
  spec.add_dependency 'base64',  '~> 0.2'
end

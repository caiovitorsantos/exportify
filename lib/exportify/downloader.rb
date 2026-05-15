# frozen_string_literal: true

module Exportify
  module Downloader
    module_function

    def download(track, output_dir)
      artist   = sanitize(track[:artist])
      name     = sanitize(track[:name])
      query    = "#{track[:raw_name]} #{track[:all_artists]} official audio"
      template = File.join(output_dir, "#{artist} - #{name}.%(ext)s")

      system(
        'yt-dlp', "ytsearch1:#{query}",
        '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
        '--output', template,
        '--no-playlist', '--quiet', '--no-warnings'
      )
    end

    def sanitize(str)
      str.gsub(/[\/\\:*?"<>|]/, '').strip
    end
  end
end

# frozen_string_literal: true

module Exportify
  module Downloader
    module_function

    def download(track, output_dir, browser: nil)
      artist   = sanitize(track[:artist])
      name     = sanitize(track[:name])
      template = File.join(output_dir, "#{artist} - #{name}.%(ext)s")

      source = if track[:video_id]
                 "https://www.youtube.com/watch?v=#{track[:video_id]}"
               else
                 query = "#{track[:raw_name]} #{track[:all_artists]} official audio"
                 "ytsearch1:#{query}"
               end

      cmd = [
        'yt-dlp', source,
        '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
        '--output', template,
        '--no-playlist', '--quiet', '--no-warnings'
      ]
      cmd += ['--cookies-from-browser', browser] if browser

      system(*cmd)
    end

    def sanitize(str)
      str.gsub(%r{[/\\:*?"<>|]}, '').strip
    end
  end
end

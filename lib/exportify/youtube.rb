# frozen_string_literal: true

module Exportify
  module YouTube
    module_function

    def split_title(title, fallback_artist)
      if title =~ /\A(.+?)\s*-\s*(.+)\z/
        [Regexp.last_match(1).strip, Regexp.last_match(2).strip]
      else
        [fallback_artist.to_s, title.to_s]
      end
    end
  end
end

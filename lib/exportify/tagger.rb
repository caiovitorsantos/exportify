# frozen_string_literal: true

module Exportify
  module Tagger
    module_function

    def tag(filepath, track)
      python = <<~PY
        from mutagen.id3 import ID3, TIT2, TPE1, TALB, TDRC, TRCK, TPE2, TCON, error
        from mutagen.mp3 import MP3
        try:
          tags = ID3(#{filepath.inspect})
        except error:
          tags = ID3()
        tags['TIT2'] = TIT2(encoding=3, text=#{track[:raw_name].inspect})
        tags['TPE1'] = TPE1(encoding=3, text=#{track[:all_artists].inspect})
        tags['TPE2'] = TPE2(encoding=3, text=#{track[:artist].inspect})
        tags['TALB'] = TALB(encoding=3, text=#{track[:album].inspect})
        tags['TDRC'] = TDRC(encoding=3, text=#{track[:year].inspect})
        tags['TRCK'] = TRCK(encoding=3, text=#{track[:track_number].to_s.inspect})
        tags['TCON'] = TCON(encoding=3, text=#{track[:genre].to_s.inspect})
        tags.save(#{filepath.inspect})
      PY
      system('python3', '-c', python)
    end
  end
end

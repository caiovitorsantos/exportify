# frozen_string_literal: true

require 'digest'

module Exportify
  module Cover
    module_function

    PALETTE = [
      %w[#F97316 #FACC15],
      %w[#EC4899 #8B5CF6],
      %w[#06B6D4 #3B82F6],
      %w[#10B981 #A3E635],
      %w[#EF4444 #F97316],
      %w[#8B5CF6 #6366F1],
      %w[#F43F5E #FB923C],
      %w[#14B8A6 #22D3EE]
    ].freeze

    def for(text)
      key = text.to_s
      hash = Digest::MD5.hexdigest(key).to_i(16)
      from, to = PALETTE[hash % PALETTE.size]
      { from: from, to: to, initial: initial_for(key) }
    end

    def initial_for(text)
      letter = text.strip[0]
      letter ? letter.upcase : '♪'
    end
  end
end

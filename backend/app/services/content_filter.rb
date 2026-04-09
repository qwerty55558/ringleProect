class ContentFilter
  EN_WORDS = %w[
    fuck shit bitch cunt dick pussy asshole nigger nigga faggot
  ].freeze

  KO_WORDS = %w[
    씨발 시발 좆 존나 개새끼 보지 자지
  ].freeze

  def self.clean?(text)
    flagged(text).empty?
  end

  def self.flagged(text)
    return [] if text.nil? || text.empty?

    haystack = normalize(text)
    en = EN_WORDS.select { |w| haystack.match?(/\b#{Regexp.escape(w)}\w*/) }
    ko = KO_WORDS.select { |w| haystack.include?(w) }
    en + ko
  end

  def self.normalize(text)
    text.to_s.downcase.gsub(/\s+/, " ").strip
  end
end

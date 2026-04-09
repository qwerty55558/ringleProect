class GoogleTranslateClient
  Error = Class.new(StandardError)

  URL = "https://translate.googleapis.com/translate_a/single".freeze

  def initialize
    @conn = Faraday.new(url: URL) do |f|
      f.response :json
      f.adapter :net_http
    end
  end

  def translate(text, target: "ko", source: "en")
    resp = @conn.get("", {
      client: "gtx",
      sl: source,
      tl: target,
      dt: "t",
      q: text
    })

    raise Error, "Google Translate error (#{resp.status})" unless resp.success?

    sentences = resp.body
    raise Error, "unexpected response shape" unless sentences.is_a?(Array) && sentences[0].is_a?(Array)

    sentences[0].map { |s| s[0] }.compact.join
  end
end

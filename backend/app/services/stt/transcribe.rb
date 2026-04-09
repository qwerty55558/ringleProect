module Stt
  # Looks up — or fills — the per-(audio_bytes) STT cache.
  #
  # On a hit we return the stored transcription without touching Gemini.
  # On a miss we transcribe once, persist the blob via Active Storage,
  # and return the resulting text. This is the only place that calls
  # GeminiClient#transcribe so the cache is impossible to bypass.
  #
  # Why hash the raw bytes (and not just the size or filename)? Because
  # the demo fixtures we ship with the app are byte-deterministic WAV
  # blobs — the frontend will upload the EXACT same bytes for "예문 1"
  # every time, so the SHA256 always lines up with the seeded row.
  class Transcribe
    Result = Struct.new(:text, :artifact, :cache_hit, keyword_init: true)

    def self.call(audio_bytes:, mime_type:, client: GeminiClient.new)
      raise ArgumentError, "audio_bytes blank" if audio_bytes.to_s.bytesize.zero?

      hash = SttArtifact.hash_for(audio_bytes)
      cached = SttArtifact.find_by(audio_hash: hash)
      if cached
        return Result.new(text: cached.text, artifact: cached, cache_hit: true)
      end

      text = client.transcribe(audio_bytes: audio_bytes, mime_type: mime_type)
      artifact = SttArtifact.new(
        audio_hash: hash,
        text: text,
        mime_type: mime_type,
        byte_size: audio_bytes.bytesize
      )
      artifact.save!
      artifact.audio.attach(
        io: StringIO.new(audio_bytes),
        filename: "#{hash[0..15]}.bin",
        content_type: mime_type
      )

      Result.new(text: text, artifact: artifact, cache_hit: false)
    end
  end
end

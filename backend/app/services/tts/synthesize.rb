module Tts
  # Looks up — or fills — the per-(text, voice, model) TtsArtifact cache.
  #
  # On a hit we return the stored MP3 bytes without touching ElevenLabs.
  # On a miss we synthesise once, persist the blob via Active Storage, and
  # then return the bytes. This is the only place that calls
  # ElevenLabsClient#synthesize so the cache is impossible to bypass.
  class Synthesize
    Result = Struct.new(:bytes, :artifact, :cache_hit, keyword_init: true)

    def self.call(text:, client: ElevenLabsClient.new)
      normalised = text.to_s.strip
      raise ArgumentError, "text blank" if normalised.empty?

      voice_id = client.voice_id
      model_id = client.instance_variable_get(:@model_id) || ElevenLabsClient::DEFAULT_MODEL_ID
      content_hash = TtsArtifact.hash_for(normalised)

      artifact = TtsArtifact.find_by(content_hash: content_hash, voice_id: voice_id, model_id: model_id)
      if artifact && artifact.audio.attached?
        return Result.new(bytes: artifact.audio.download, artifact: artifact, cache_hit: true)
      end

      bytes = client.synthesize(text: normalised)
      artifact ||= TtsArtifact.new(content_hash: content_hash, voice_id: voice_id, model_id: model_id)
      artifact.save! unless artifact.persisted?
      artifact.audio.attach(
        io: StringIO.new(bytes),
        filename: "#{content_hash[0..15]}.mp3",
        content_type: "audio/mpeg"
      )

      Result.new(bytes: bytes, artifact: artifact, cache_hit: false)
    end
  end
end

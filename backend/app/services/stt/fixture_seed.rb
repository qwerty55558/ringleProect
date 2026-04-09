module Stt
  # Idempotently materialises the FixtureLibrary into the stt_artifacts
  # table. Run from db/seeds.rb so the demo fixtures are guaranteed to
  # be cache-hit on first boot — the recruiter never has to "warm up"
  # a fixture by waiting for an actual Gemini transcription.
  class FixtureSeed
    def self.call
      FixtureLibrary.all.each do |fixture|
        bytes = fixture[:audio_bytes]
        hash = SttArtifact.hash_for(bytes)

        artifact = SttArtifact.find_or_initialize_by(audio_hash: hash)
        artifact.assign_attributes(
          slug: fixture[:slug],
          label: fixture[:label],
          text: fixture[:text],
          mime_type: "audio/wav",
          byte_size: bytes.bytesize
        )
        artifact.save!

        unless artifact.audio.attached?
          artifact.audio.attach(
            io: StringIO.new(bytes),
            filename: "#{fixture[:slug]}.wav",
            content_type: "audio/wav"
          )
        end
      end
      SttArtifact.fixtures.count
    end
  end
end

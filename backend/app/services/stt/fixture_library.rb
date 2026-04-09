module Stt
  # Demo fixtures the frontend can pick instead of using the microphone.
  #
  # Each entry pairs a deterministic WAV blob (silence + a marker tone so
  # the bytes vary across fixtures and produce distinct hashes) with the
  # transcription it should resolve to. The blob is byte-stable so the
  # hash we seed into the database always matches what the frontend will
  # upload, which means the recruiter sees a `X-Stt-Cache: hit` on every
  # fixture playback — no Gemini billing, no surprise misses.
  #
  # Why ship audio bytes at all instead of bypassing the endpoint? So the
  # demo exercises the SAME code path as a live mic recording: multipart
  # POST → SttTranscribe → SttArtifact lookup → text. The only thing the
  # fixture replaces is the microphone capture step.
  class FixtureLibrary
    SAMPLE_RATE = 16_000

    FIXTURES = [
      { slug: "intro-self",      label: "자기소개",        text: "Hi, I'm Danny. I work as a backend engineer at Ringle.",                                     tone_hz: 220.0, duration_ms: 1500 },
      { slug: "order-coffee",    label: "카페 주문",       text: "Can I get a grande iced latte with oat milk, please?",                                        tone_hz: 330.0, duration_ms: 1500 },
      { slug: "weekend-plan",    label: "주말 계획",       text: "I'm thinking of going hiking on Saturday. Any recommendations?",                               tone_hz: 440.0, duration_ms: 1700 },
      { slug: "ask-direction",   label: "길 물어보기",     text: "Excuse me, could you tell me how to get to the nearest subway station?",                       tone_hz: 494.0, duration_ms: 1800 },
      { slug: "hotel-checkin",   label: "호텔 체크인",     text: "I have a reservation under the name Danny Kim for two nights.",                                 tone_hz: 523.0, duration_ms: 1600 },
      { slug: "japan-trip",      label: "여행 계획",       text: "I'm thinking of going to Japan next month. What should I prepare?",                             tone_hz: 587.0, duration_ms: 1700 },
      { slug: "japan-followup",  label: "여행 후속 (연계)", text: "What's the best area to stay in Tokyo for first-time visitors?",                                tone_hz: 659.0, duration_ms: 1800 },
      { slug: "meeting-reschedule", label: "회의 일정 변경", text: "Something came up. Could we move our meeting to Thursday afternoon instead?",                 tone_hz: 698.0, duration_ms: 1900 },
    ].freeze

    def self.all
      FIXTURES.map { |f| f.merge(audio_bytes: synth_wav(tone_hz: f[:tone_hz], duration_ms: f[:duration_ms])) }
    end

    # Build a 16kHz mono 16-bit PCM WAV containing a sine tone of the
    # requested frequency. The bytes are pure functions of (frequency,
    # duration_ms, sample_rate) so the same args always produce the same
    # blob — and therefore the same SHA256 — across machines.
    def self.synth_wav(tone_hz:, duration_ms:, sample_rate: SAMPLE_RATE)
      sample_count = (sample_rate * duration_ms / 1000.0).to_i
      data = String.new(capacity: sample_count * 2, encoding: Encoding::ASCII_8BIT)
      amplitude = 0.18 * 32_767 # leave headroom; this is "soft speech" loud
      sample_count.times do |i|
        sample = (Math.sin(2.0 * Math::PI * tone_hz * i / sample_rate) * amplitude).round
        data << [sample].pack("s<")
      end
      data_size = data.bytesize

      header = String.new(encoding: Encoding::ASCII_8BIT)
      header << "RIFF"
      header << [36 + data_size].pack("V")
      header << "WAVE"
      header << "fmt "
      header << [16].pack("V")               # PCM chunk size
      header << [1].pack("v")                # audio format = PCM
      header << [1].pack("v")                # channels = 1
      header << [sample_rate].pack("V")
      header << [sample_rate * 2].pack("V")  # byte rate
      header << [2].pack("v")                # block align
      header << [16].pack("v")               # bits per sample
      header << "data"
      header << [data_size].pack("V")
      header << data
      header
    end
  end
end

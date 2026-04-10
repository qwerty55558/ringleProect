module StudyMaterials
  # Generates a single new study material via Gemini and persists it.
  #
  # The seeded curriculum (StudyMaterials::CurriculumSeed) gives us a
  # working baseline with no API key, but the spec asks for AI dummy
  # data. This service is the bridge: an admin / dev can call it from
  # the conversation feature to extend the curriculum on demand. The
  # generated row is cached forever in the study_materials table, so
  # the same topic only ever burns Gemini quota once.
  #
  # Usage:
  #   StudyMaterials::Generate.call(topic: "negotiating a salary")
  #
  # The generated row gets `ai_generated: true` so the UI can flag it
  # to learners ("✨ AI-generated topic").
  class Generate
    class Error < StandardError; end
    class GenerationLimitReached < Error; end
    class InappropriateContent < Error; end

    MAX_PER_USER = 3
    PROFANITY_PENALTY_INTERVAL = 3

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You generate short English tutoring scenarios for Korean learners. Always
      reply with STRICT JSON matching this shape, no markdown, no commentary:
      {
        "slug": "kebab-case-slug",
        "title": "Short English title",
        "level": "novice|beginner|intermediate|advanced",
        "category": "daily|business|travel|hobby|academic|conversation",
        "description": "한국어로 1-2문장 학습 자료 설명",
        "scenario_prompt": "System prompt that primes the AI tutor for THIS topic.",
        "key_expressions": ["sentence with ___ blanks", "another ___ sentence", "third ___ sentence"],
        "example_dialogue": [
          {"role":"assistant","text":"한국어 설명 + 핵심 영어 표현 인라인"},
          {"role":"user","text":"English practice sentence"},
          {"role":"assistant","text":"한국어 피드백 + 다음 영어 표현"}
        ]
      }

      Rules for key_expressions:
      - Exactly 3 items.
      - Each must be a FULL English sentence with ___ blanks where the learner fills in, e.g. "I'd like to ___ , please." or "Could you tell me how to get to ___ ?"
      - Never single words or short phrases.

      Rules for example_dialogue:
      - Assistant lines must be in Korean but embed the target English key expressions verbatim.
      - User lines must be in English (the learner is practicing producing English).
    PROMPT

    def self.call(topic:, user:, client: GeminiClient.new)
      raise ArgumentError, "topic blank" if topic.to_s.strip.empty?
      raise ArgumentError, "user required" if user.nil?

      if user.study_generations_used >= MAX_PER_USER
        raise GenerationLimitReached,
              "user has used all #{MAX_PER_USER} study generation slots"
      end

      flagged = ContentFilter.flagged(topic)
      if flagged.any?
        record_profanity_offense!(user)
        raise InappropriateContent, "topic flagged: #{flagged.join(', ')}"
      end

      raw = +""
      last_error = nil
      GeminiClient::MODEL_CHAIN.each do |model|
        begin
          raw = +""
          client.stream_chat(
            messages: [{ role: "user", text: "Generate a study scenario for: #{topic}" }],
            system_instruction: SYSTEM_PROMPT,
            model: model
          ) { |delta| raw << delta }
          last_error = nil
          break
        rescue GeminiClient::Error => e
          last_error = e
          Rails.logger.warn("[study/generate] #{model} failed: #{e.message}, trying next")
          next
        end
      end
      raise last_error if last_error

      payload = parse_json!(raw)
      attrs = build_attrs(payload).merge(ai_generated: true)

      output_flagged = ContentFilter.flagged(serializable_text_blob(attrs))
      if output_flagged.any?
        raise InappropriateContent, "generated content flagged: #{output_flagged.join(', ')}"
      end

      material = ActiveRecord::Base.transaction do
        m = StudyMaterial.find_or_initialize_by(slug: attrs[:slug])
        m.assign_attributes(attrs)
        m.save!
        # increment after save so gemini/parse failures don't burn the slot
        user.update!(study_generations_used: user.study_generations_used + 1)
        m
      end

      Study::Bus.publish

      material
    rescue ActiveRecord::RecordInvalid => e
      raise Error, "validation failed: #{e.record.errors.full_messages.join('; ')}"
    rescue GeminiClient::SafetyBlocked => e
      raise InappropriateContent, "Gemini safety filter: #{e.message}"
    end

    def self.record_profanity_offense!(user)
      ActiveRecord::Base.transaction do
        new_count = user.study_profanity_offenses + 1
        attrs = { study_profanity_offenses: new_count }
        if (new_count % PROFANITY_PENALTY_INTERVAL).zero?
          attrs[:study_generations_used] = [user.study_generations_used + 1, MAX_PER_USER].min
        end
        user.update!(attrs)
      end
      Me::Bus.publish(user.id)
    end

    def self.serializable_text_blob(attrs)
      [
        attrs[:title],
        attrs[:description],
        attrs[:scenario_prompt],
        Array(attrs[:key_expressions]).join(" "),
        Array(attrs[:example_dialogue]).map { |line| line.is_a?(Hash) ? line["text"] || line[:text] : line }.join(" ")
      ].compact.join(" ")
    end

    def self.parse_json!(raw)
      cleaned = raw.strip.sub(/\A```json\s*/, "").sub(/```\s*\z/, "")
      JSON.parse(cleaned)
    rescue JSON::ParserError => e
      raise Error, "model returned non-JSON: #{e.message}"
    end

    def self.build_attrs(payload)
      {
        slug: payload.fetch("slug"),
        title: payload.fetch("title"),
        level: payload.fetch("level"),
        category: payload.fetch("category"),
        description: payload.fetch("description"),
        scenario_prompt: payload.fetch("scenario_prompt"),
        key_expressions: Array(payload["key_expressions"]),
        example_dialogue: Array(payload["example_dialogue"])
      }
    end
  end
end

module Conversations
  class Analyze
    SYSTEM_PROMPT = <<~PROMPT.freeze
      당신은 한국인 영어 학습자를 위한 전문 영어 평가 전문가입니다.
      아래 학습자(user)와 AI 튜터(model) 간의 대화를 분석하세요.

      반드시 아래 JSON 스키마에 맞는 단일 JSON 객체로 응답하세요:
      {
        "overall_level": "novice" | "beginner" | "intermediate" | "advanced",
        "grammar": {
          "score": <0-100>,
          "mistakes": [{ "original": "...", "corrected": "...", "explanation": "한국어로 설명" }]
        },
        "vocabulary": {
          "score": <0-100>,
          "frequent_words": ["..."],
          "alternatives": [{ "used": "...", "suggestions": ["..."] }]
        },
        "fluency": {
          "score": <0-100>,
          "comment": "한국어로 작성"
        },
        "topic_relevance": {
          "score": <0-100>,
          "comment": "한국어로 작성"
        },
        "key_expressions": {
          "used": ["..."],
          "missed": ["..."],
          "comment": "한국어로 작성"
        },
        "suggestions": ["한국어로 작성", "한국어로 작성", "한국어로 작성"]
      }

      규칙:
      - 학습자(user)의 메시지만 평가 대상입니다.
      - 핵심 표현 컨텍스트가 없으면 key_expressions를 null로 설정하세요.
      - 설명은 한국어로 간결하게 (1문장).
      - 점수 기준: 0-39 부족, 40-59 발전중, 60-79 양호, 80-100 우수.
      - JSON 객체만 응답하세요. 마크다운 펜스나 추가 텍스트 없이.
    PROMPT

    COOLDOWN = 30.seconds

    # 분석 요청 시작. pending 레코드를 만들고 반환.
    # 실제 분석은 run! 에서 수행.
    def self.request!(conversation:)
      latest = Analysis.latest_for(conversation)

      if latest&.pending?
        return latest
      end

      if latest && latest.analyzed_at > COOLDOWN.ago
        remaining = ((latest.analyzed_at + COOLDOWN - Time.current)).ceil
        raise ArgumentError, "#{remaining}초 후에 다시 분석할 수 있어요."
      end

      messages = conversation.messages.order(:position).to_a
      raise ArgumentError, "분석할 메시지가 부족해요." if messages.count { |m| m.role == "user" } < 1

      conversation.analyses.create!(
        status: "pending",
        analyzed_at: Time.current
      )
    end

    # 실제 Gemini 호출. SSE 스트리밍 지원.
    def self.run!(analysis:, client: GeminiClient.new, &block)
      conversation = analysis.conversation
      messages = conversation.messages.order(:position).to_a
      transcript = messages.map { |m| "#{m.role}: #{m.text}" }.join("\n")
      system = build_system_instruction(conversation)
      user_input = [{ role: "user", text: transcript }]

      accumulated = +""
      last_error = nil
      GeminiClient::MODEL_CHAIN.each do |model|
        begin
          accumulated = +""
          if block_given?
            client.stream_chat(messages: user_input, system_instruction: system, model: model) do |delta|
              accumulated << delta
              block.call(delta)
            end
          else
            accumulated = client.chat(messages: user_input, system_instruction: system, model: model)
          end
          Rails.logger.info("[analysis] ok: #{model}")
          last_error = nil
          break
        rescue GeminiClient::Error => e
          last_error = e
          Rails.logger.warn("[analysis] #{model} failed: #{e.message}, trying next")
          next
        end
      end

      if last_error
        analysis.update!(status: "failed", result: last_error.message)
        AnalysisBus.publish(conversation.user_id)
        raise last_error
      end

      analysis.update!(status: "completed", result: accumulated.strip, analyzed_at: Time.current)
      AnalysisBus.publish(conversation.user_id)
    end

    def self.build_system_instruction(conversation)
      parts = [SYSTEM_PROMPT]
      if conversation.context_summary.present?
        parts << "대화 컨텍스트: #{conversation.context_summary}"
      end
      parts.join("\n\n")
    end

    private_class_method :build_system_instruction
  end
end

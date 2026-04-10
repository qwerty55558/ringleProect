module Conversations
  class Summarize
    RECENT_KEEP = 4
    COMPRESS_THRESHOLD = 6

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a conversation summarizer for an English tutoring app.
      Given the conversation history, produce a SHORT summary (2-3 sentences max)
      in English that captures: the learner's current topic, key mistakes corrected,
      and where the conversation left off.
      Reply with ONLY the summary text, nothing else.
    PROMPT

    def self.call(conversation:, client: GeminiClient.new)
      messages = conversation.messages.order(:position).to_a
      return if messages.size < COMPRESS_THRESHOLD

      old_messages = messages[0...-RECENT_KEEP]
      text_to_summarize = old_messages.map { |m| "#{m.role}: #{m.text}" }.join("\n")

      existing = conversation.context_summary
      if existing.present?
        text_to_summarize = "Previous context: #{existing}\n\n#{text_to_summarize}"
      end

      summary = client.chat(
        messages: [{ role: "user", text: text_to_summarize }],
        system_instruction: SYSTEM_PROMPT
      )

      conversation.update!(context_summary: summary.strip)
      summary.strip
    end
  end
end

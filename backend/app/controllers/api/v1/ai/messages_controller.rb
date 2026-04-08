module Api
  module V1
    module Ai
      # Streams an AI tutor reply as Server-Sent Events. We require an active
      # `talk` feature on the caller before invoking the LLM so we don't burn
      # quota for non-paying users.
      class MessagesController < ApplicationController
        include ActionController::Live

        SYSTEM_PROMPT = <<~PROMPT.freeze
          You are Ringle, a friendly English-speaking tutor helping a Korean
          learner practice business English. Keep replies short (1-3 sentences),
          ask one follow-up question, and stay on the conversation topic the
          learner introduces. If the learner makes a grammar mistake, gently
          rephrase the correct version inside your reply. Reply only in English.
        PROMPT

        before_action :require_user!
        before_action :require_talk_feature!

        def create
          messages = params.require(:messages).map do |m|
            { role: m[:role] == "assistant" ? "model" : "user", text: m[:text].to_s }
          end

          response.headers["Content-Type"]      = "text/event-stream"
          response.headers["Cache-Control"]     = "no-cache"
          response.headers["X-Accel-Buffering"] = "no"
          sse = SSE.new(response.stream, retry: 300, event: "message")

          begin
            gemini_client.stream_chat(
              messages: messages,
              system_instruction: SYSTEM_PROMPT
            ) do |delta|
              sse.write({ delta: delta })
            end
            sse.write({ done: true }, event: "done")
          rescue GeminiClient::Error => e
            Rails.logger.error("[ai/messages] gemini error: #{e.message}")
            sse.write({ error: "ai_failed", message: e.message }, event: "error")
          ensure
            sse.close
          end
        end

        private

        def require_talk_feature!
          return if current_user.has_feature?("talk")

          render status: :forbidden, json: { error: "membership_required", feature: "talk" }
        end

        def gemini_client
          @gemini_client ||= GeminiClient.new
        end
      end
    end
  end
end

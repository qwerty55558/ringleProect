module Api
  module V1
    module Ai
      # Streams an AI tutor reply as Server-Sent Events. We require an active
      # `talk` feature on the caller before invoking the LLM so we don't burn
      # quota for non-paying users.
      class MessagesController < ApplicationController
        include ActionController::Live

        DEFAULT_SYSTEM_PROMPT = <<~PROMPT.freeze
          You are Ringle, a friendly English-speaking tutor helping a Korean
          learner practice business English. Keep replies short (1-3 sentences),
          ask one follow-up question, and stay on the conversation topic the
          learner introduces. If the learner makes a grammar mistake, gently
          rephrase the correct version inside your reply. Reply only in English.
        PROMPT

        CHAT_MODEL_CHAIN = GeminiClient::MODEL_CHAIN

        before_action :require_user!
        before_action :require_talk_feature!

        def create
          messages = params.require(:messages).map do |m|
            { role: m[:role] == "assistant" ? "model" : "user", text: m[:text].to_s }
          end

          if params[:conversation_id].present?
            conv = current_user.conversations.find_by(id: params[:conversation_id])
            if conv
              begin
                Conversations::Summarize.call(conversation: conv, client: gemini_client)
              rescue => e
                Rails.logger.warn("[ai/messages] summarize failed conv=#{conv.id}: #{e.message}")
              end
            end
          end

          response.headers["Content-Type"]      = "text/event-stream"
          response.headers["Cache-Control"]     = "no-cache"
          response.headers["X-Accel-Buffering"] = "no"
          sse = SSE.new(response.stream, retry: 300, event: "message")

          begin
            stream_with_fallback(messages: messages, system_instruction: build_system_instruction) do |delta|
              sse.write({ delta: delta })
            end
            sse.write({ done: true }, event: "done")
          rescue GeminiClient::Error => e
            Rails.logger.error("[ai/messages] all chat models failed: #{e.message}")
            sse.write({ error: "ai_failed", message: e.message }, event: "error")
          ensure
            sse.close
          end
        end

        private

        def build_system_instruction
          parts = [DEFAULT_SYSTEM_PROMPT]

          conv = params[:conversation_id].present? ?
            current_user.conversations.find_by(id: params[:conversation_id]) : nil
          material_id = params[:study_material_id].presence || conv&.study_material_id
          if material_id.present?
            material = StudyMaterial.find_by(id: material_id)
            if material
              curriculum = "Today's curriculum:\n#{material.scenario_prompt}"
              if material.key_expressions.present?
                curriculum += "\n\nKey expressions the learner should practice:\n"
                curriculum += material.key_expressions.map { |e| "- #{e}" }.join("\n")
              end
              if material.example_dialogue.present?
                curriculum += "\n\nExample dialogue flow:\n"
                material.example_dialogue.each do |turn|
                  curriculum += "#{turn['role']}: #{turn['text']}\n"
                end
              end
              parts << curriculum
            end
          end

          if conv
            if conv.context_summary.present?
              parts << "Previous conversation context:\n#{conv.context_summary}"
            end
          end

          parts.join("\n\n")
        end

        def require_talk_feature!
          return if current_user.has_feature?("talk")

          render status: :forbidden, json: { error: "membership_required", feature: "talk" }
        end

        def stream_with_fallback(messages:, system_instruction:, &block)
          last_error = nil
          CHAT_MODEL_CHAIN.each do |model|
            begin
              gemini_client.stream_chat(
                messages: messages,
                system_instruction: system_instruction,
                model: model,
                &block
              )
              Rails.logger.info("[ai/messages] chat ok: #{model}")
              return
            rescue GeminiClient::Error => e
              last_error = e
              Rails.logger.warn("[ai/messages] #{model} failed: #{e.message}, trying next")
              next
            end
          end
          raise last_error
        end

        def gemini_client
          @gemini_client ||= GeminiClient.new
        end
      end
    end
  end
end

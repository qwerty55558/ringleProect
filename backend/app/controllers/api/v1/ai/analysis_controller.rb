module Api
  module V1
    module Ai
      class AnalysisController < ApplicationController
        before_action :require_user!
        before_action :require_analysis_feature!

        # GET /api/v1/ai/analysis?conversation_id=X
        def show
          conversation = current_user.conversations.find(params.require(:conversation_id))
          latest = Analysis.latest_for(conversation)
          if latest
            render json: {
              id: latest.id,
              status: latest.status,
              result: latest.completed? ? latest.result : nil,
              analyzed_at: latest.analyzed_at.iso8601,
              cooldown_remaining: cooldown_remaining(latest)
            }
          else
            render json: { status: "none", result: nil, cooldown_remaining: 0 }
          end
        end

        # POST /api/v1/ai/analysis
        def create
          conversation = current_user.conversations.find(params.require(:conversation_id))

          begin
            analysis = Conversations::Analyze.request!(conversation: conversation)
          rescue ArgumentError => e
            render status: :unprocessable_entity, json: { error: e.message }
            return
          end

          if analysis.pending?
            user_id = current_user.id
            analysis_id = analysis.id
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                a = Analysis.find(analysis_id)
                Conversations::Analyze.run!(analysis: a)
              end
            rescue => e
              Rails.logger.error("[ai/analysis] background failed: #{e.message}")
              ActiveRecord::Base.connection_pool.with_connection do
                Analysis.find_by(id: analysis_id)&.update(status: "failed", result: e.message)
                AnalysisBus.publish(user_id)
              end
            end
          end

          render status: :accepted, json: { id: analysis.id, status: analysis.status }
        end

        private

        def require_analysis_feature!
          return if current_user.has_feature?("analysis")
          render status: :forbidden, json: { error: "membership_required", feature: "analysis" }
        end

        def cooldown_remaining(analysis)
          return 0 unless analysis.completed?
          elapsed = Time.current - analysis.analyzed_at
          remaining = (Conversations::Analyze::COOLDOWN - elapsed).to_i
          [remaining, 0].max
        end
      end
    end
  end
end

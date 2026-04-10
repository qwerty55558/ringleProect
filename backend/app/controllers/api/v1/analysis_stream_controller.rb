module Api
  module V1
    class AnalysisStreamController < ApplicationController
      include ActionController::Live

      HEARTBEAT_INTERVAL = 30.0
      MAX_DURATION = 5.minutes

      before_action :promote_query_user_id_to_header
      before_action :require_user!

      def show
        response.headers["Content-Type"]      = "text/event-stream"
        response.headers["Cache-Control"]     = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        sse = SSE.new(response.stream, retry: 3000)
        user_id = current_user.id
        queue = AnalysisBus.subscribe(user_id)
        deadline = Time.current + MAX_DURATION

        sse.write({ ready: true }, event: "ready")

        while Time.current < deadline
          break if response.stream.closed?
          event = queue.pop(timeout: HEARTBEAT_INTERVAL)
          break if response.stream.closed?

          if event
            sse.write({ changed: true }, event: "changed")
          else
            sse.write({ ts: Time.current.to_i }, event: "heartbeat")
          end
        end
      rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
      ensure
        AnalysisBus.unsubscribe(user_id, queue) if queue
        sse.close if defined?(sse)
      end

      private

      def promote_query_user_id_to_header
        return if request.headers["X-User-Id"].present?
        return unless params[:user_id].present?
        request.headers["X-User-Id"] = params[:user_id].to_s
      end
    end
  end
end

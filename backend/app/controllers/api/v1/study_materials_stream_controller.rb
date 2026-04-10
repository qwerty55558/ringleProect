module Api
  module V1
    # SSE channel that fans out study curriculum changes to every
    # open /study tab. Same shape as `Api::V1::Admin::MembershipStreamController`:
    # the bus push is content-free, the SSE frame is content-free
    # (`event: changed`), and the frontend reacts by invalidating its
    # study materials React Query so the canonical REST endpoint is
    # refetched.
    #
    # Triggers that wake the loop:
    #   - `StudyMaterials::Generate` after a successful generation
    #   - `StudyMaterials::Reset` (admin "리셋" button) after the
    #     curriculum has been wiped + reseeded
    #
    # Like the other SSE controllers, this is gated by a soft heartbeat
    # (30s) and a hard MAX_DURATION (5min) cap. Falcon's event loop
    # detects closed sockets in microseconds so leaked fibers cost
    # nothing.
    class StudyMaterialsStreamController < ApplicationController
      include ActionController::Live

      HEARTBEAT_INTERVAL = 30.0
      MAX_DURATION       = 5.minutes

      before_action :promote_query_user_id_to_header
      before_action :require_user!
      before_action :require_study_feature!

      def show
        response.headers["Content-Type"]      = "text/event-stream"
        response.headers["Cache-Control"]     = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        sse = SSE.new(response.stream, retry: 3000)
        queue = ::Study::Bus.subscribe
        deadline = Time.current + MAX_DURATION

        sse.write({ ts: Time.current.to_i }, event: "ready")

        while Time.current < deadline
          break if response.stream.closed?
          event = queue.pop(timeout: HEARTBEAT_INTERVAL)
          break if response.stream.closed?

          if event
            sse.write({ ts: Time.current.to_i }, event: "changed")
          else
            sse.write({ ts: Time.current.to_i }, event: "heartbeat")
          end
        end
      rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
        # Browser tab closed — normal.
      ensure
        ::Study::Bus.unsubscribe(queue) if queue
        sse.close if defined?(sse)
      end

      private

      def require_study_feature!
        return if current_user.has_feature?("study")

        # before_action gates run BEFORE we open the SSE handshake,
        # so a plain JSON 403 is the right shape. The frontend
        # `useStudyMaterialsStream` hook checks `EventSource.onerror`
        # and just stops trying.
        render status: :forbidden, json: { error: "membership_required", feature: "study" }
      end

      def promote_query_user_id_to_header
        return if request.headers["X-User-Id"].present?
        return unless params[:user_id].present?

        request.headers["X-User-Id"] = params[:user_id].to_s
      end
    end
  end
end

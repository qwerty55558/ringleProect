module Api
  module V1
    # Server-Sent Events channel that pushes the current `/me` payload
    # to the browser whenever it changes — replaces the 4-second `/me`
    # poll the conversation page used to run.
    #
    # The loop is *event-driven*, not tick-based:
    #
    #   1. On connect we send one initial snapshot.
    #   2. We then block on `Queue#pop(timeout: …)`.
    #   3. The timeout is the smaller of (next membership expiry) and
    #      (heartbeat interval). Idle subscribers consume zero DB
    #      connections and zero CPU between events.
    #   4. The pop unblocks for one of three reasons:
    #        a) `Me::Bus#publish(user_id)` was called from a Membership
    #           after_commit hook (purchase, admin grant, revoke,
    #           wipe-all). We push a fresh snapshot.
    #        b) The pop timed out and we crossed an `expires_at`. We
    #           push a fresh snapshot — the expired plan now reports
    #           state="expired" and the feature drops out.
    #        c) The pop timed out before any expiry deadline. We send a
    #           heartbeat so proxies/browsers don't kill the idle conn.
    #
    # Why SSE and not WebSockets? One-way, JSON-shaped, tiny — and SSE
    # gives us automatic reconnect for free.
    #
    # Auth: EventSource cannot set custom headers, so this controller
    # accepts the user id via `?user_id=` in addition to `X-User-Id`.
    # Real auth is out of scope per the assignment.
    class MeStreamController < ApplicationController
      include ActionController::Live

      # Heartbeat exists purely to keep proxies / browsers from killing
      # the idle connection — NOT for cleanup. Falcon detects closed
      # sockets in the event loop in microseconds (a leaked fiber
      # would be a few hundred bytes anyway), so we can afford a
      # comfortable 30s heartbeat instead of the 2s panic interval
      # the old Puma-era code needed.
      HEARTBEAT_INTERVAL = 30.0
      MAX_DURATION       = 5.minutes  # hard cap; Falcon would happily hold idle fibers forever otherwise

      before_action :promote_query_user_id_to_header
      before_action :require_user!

      def show
        response.headers["Content-Type"]      = "text/event-stream"
        response.headers["Cache-Control"]     = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        sse = SSE.new(response.stream, retry: 3000)
        user_id = current_user.id
        begin
          queue = Me::Bus.subscribe(user_id)
        rescue Me::Bus::TooManySubscribersError => e
          Rails.logger.warn("[me/stream] #{e.message}")
          sse.write({ error: "too_many_connections" }, event: "error")
          return
        end
        deadline = Time.current + MAX_DURATION

        # (1) Initial snapshot — the client is waiting for it.
        push_snapshot(sse, user_id)

        # (2) Event loop. Idle here costs zero DB. Each iteration
        # checks if the client tore down the socket BEFORE we block
        # on Queue#pop again, so a refresh storm doesn't keep this
        # thread parked for the full heartbeat interval.
        while Time.current < deadline
          break if response.stream.closed?

          timeout = wait_timeout(user_id, deadline)
          event = queue.pop(timeout: timeout)

          break if response.stream.closed?

          if event
            # Bus push — membership row changed. Refresh.
            push_snapshot(sse, user_id)
          elsif crossed_expiry?(user_id)
            # Pop timed out exactly because a membership just expired.
            push_snapshot(sse, user_id)
          else
            sse.write({ ts: Time.current.to_i }, event: "heartbeat")
          end
        end
      rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
        # Browser tab closed / navigated away — totally normal.
      ensure
        Me::Bus.unsubscribe(user_id, queue) if queue
        sse.close if defined?(sse)
      end

      private

      # Compute the next wakeup time. We pick the *smaller* of:
      #   - seconds until the soonest active membership's expires_at
      #   - the heartbeat interval
      #   - the hard duration cap
      # …so a soon-to-expire 30s test plan wakes us up at exactly the
      # right instant without any polling in between.
      def wait_timeout(user_id, deadline)
        next_expiry = soonest_active_expiry(user_id)
        candidates = [HEARTBEAT_INTERVAL, deadline - Time.current]
        if next_expiry
          delta = next_expiry - Time.current
          candidates << delta if delta.positive?
        end
        candidates.min
      end

      def soonest_active_expiry(user_id)
        ActiveRecord::Base.connection_pool.with_connection do
          Membership.where(user_id: user_id, status: "active")
                    .where("expires_at > ?", Time.current)
                    .minimum(:expires_at)
        end
      end

      # Did the soonest expiry move into the past since our last
      # snapshot? If so, the timeout fire was an expiry — push.
      def crossed_expiry?(user_id)
        ActiveRecord::Base.connection_pool.with_connection do
          Membership.where(user_id: user_id, status: "active")
                    .where("expires_at <= ?", Time.current)
                    .exists?
        end
      end

      def push_snapshot(sse, user_id)
        ActiveRecord::Base.connection_pool.with_connection do
          user = User.find_by(id: user_id)
          unless user
            sse.write({ error: "user_gone" }, event: "error")
            return
          end
          sse.write(Me::Snapshot.call(user), event: "snapshot")
        end
      end

      # EventSource has no way to attach custom request headers, so we
      # let the client pass `?user_id=…` and forge it back into the
      # X-User-Id header that ApplicationController#current_user reads.
      # Safe because real auth is out of scope per the spec.
      def promote_query_user_id_to_header
        return if request.headers["X-User-Id"].present?
        return unless params[:user_id].present?

        request.headers["X-User-Id"] = params[:user_id].to_s
      end
    end
  end
end

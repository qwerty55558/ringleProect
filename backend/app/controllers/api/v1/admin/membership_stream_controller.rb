module Api
  module V1
    module Admin
      # Global SSE channel for the admin dashboard. Anyone watching
      # /admin gets notified the instant ANY user's membership changes
      # — purchase, admin grant, revoke, wipe-all, or time-based expiry
      # — and refetches the canonical /admin/users snapshot.
      #
      # Counterpart to /api/v1/me/stream, which is per-user. The two
      # channels share the same Membership after_commit fan-out:
      # one hook publishes to Me::Bus (the owning user's queue) AND
      # Admin::MembershipBus (every admin watcher).
      #
      # Payload shape: we deliberately push a content-free `event:
      # changed` frame instead of mirroring the full /admin/users
      # serialisation. The frontend reacts by invalidating its
      # adminUsers React Query, which triggers a normal REST refetch
      # against the existing controller. That keeps SSE simple and
      # avoids serialising the same payload in two places.
      class MembershipStreamController < ApplicationController
        include ActionController::Live

        # See MeStreamController. Falcon's event loop handles socket
        # close detection itself, so heartbeat is purely about keeping
        # proxies/browsers happy.
        HEARTBEAT_INTERVAL = 30.0
        MAX_DURATION       = 5.minutes

        before_action :promote_query_user_id_to_header
        before_action :require_admin!

        def show
          response.headers["Content-Type"]      = "text/event-stream"
          response.headers["Cache-Control"]     = "no-cache"
          response.headers["X-Accel-Buffering"] = "no"

          sse = SSE.new(response.stream, retry: 3000)
          queue = ::Admin::MembershipBus.subscribe
          deadline = Time.current + MAX_DURATION

          # Initial "ready" frame so the client knows the channel is
          # live and can show its connected indicator.
          sse.write({ ts: Time.current.to_i }, event: "ready")

          while Time.current < deadline
            break if response.stream.closed?

            timeout = wait_timeout(deadline)
            event = queue.pop(timeout: timeout)

            break if response.stream.closed?

            if event
              sse.write({ ts: Time.current.to_i }, event: "changed")
            elsif crossed_global_expiry?
              sse.write({ ts: Time.current.to_i }, event: "changed")
            else
              sse.write({ ts: Time.current.to_i }, event: "heartbeat")
            end
          end
        rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
          # browser tab closed — normal
        ensure
          ::Admin::MembershipBus.unsubscribe(queue) if queue
          sse.close if defined?(sse)
        end

        private

        # Wake at the soonest of: next global membership expiry,
        # heartbeat tick, hard duration cap. Same idea as
        # MeStreamController#wait_timeout but the expiry query scans
        # ALL active memberships across the database, not just one
        # user's.
        def wait_timeout(deadline)
          next_expiry = soonest_global_expiry
          candidates = [HEARTBEAT_INTERVAL, deadline - Time.current]
          if next_expiry
            delta = next_expiry - Time.current
            candidates << delta if delta.positive?
          end
          candidates.min
        end

        def soonest_global_expiry
          ActiveRecord::Base.connection_pool.with_connection do
            Membership.where(status: "active")
                      .where("expires_at > ?", Time.current)
                      .minimum(:expires_at)
          end
        end

        def crossed_global_expiry?
          ActiveRecord::Base.connection_pool.with_connection do
            Membership.where(status: "active")
                      .where("expires_at <= ?", Time.current)
                      .exists?
          end
        end

        # EventSource has no way to attach custom request headers, so
        # we let the client pass `?user_id=…` and forge it into the
        # X-User-Id header that ApplicationController#current_user
        # reads. Real auth is out of scope per the spec.
        def promote_query_user_id_to_header
          return if request.headers["X-User-Id"].present?
          return unless params[:user_id].present?

          request.headers["X-User-Id"] = params[:user_id].to_s
        end
      end
    end
  end
end

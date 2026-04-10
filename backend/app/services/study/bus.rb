require "concurrent"

module Study
  # Global broadcast channel for /study curriculum changes. Same shape
  # as `Admin::MembershipBus` — content-free `:changed` signals fan
  # out to every queue, and the SSE controller turns each signal into
  # an `event: changed` frame so the frontend can invalidate its
  # study materials React Query cache.
  #
  # Two triggers publish here:
  #   - `StudyMaterials::Generate` after a successful generation
  #   - `StudyMaterials::Reset` after the admin nukes & reseeds the
  #     curriculum from the dev panel
  #
  # In-process for now (single Falcon worker). Swap to Redis pub/sub
  # when we go multi-process — the public surface is identical.
  module Bus
    @subscribers = Concurrent::Array.new

    class << self
      def subscribe
        queue = Thread::Queue.new
        @subscribers << queue
        queue
      end

      def unsubscribe(queue)
        @subscribers.delete(queue)
      end

      def publish
        @subscribers.each do |q|
          q << :changed
        rescue ClosedQueueError
          # subscriber tore down between publish and write
        end
      end

      def reset!
        @subscribers = Concurrent::Array.new
      end
    end
  end
end

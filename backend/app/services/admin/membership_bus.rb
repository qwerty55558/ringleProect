require "concurrent"

module Admin
  module MembershipBus
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
        end
      end

      def reset!
        @subscribers = Concurrent::Array.new
      end
    end
  end
end

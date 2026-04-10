require "concurrent"

module Me
  module Bus
    MAX_PER_USER = 8

    class TooManySubscribersError < StandardError; end

    @subscribers = Concurrent::Map.new

    class << self
      def subscribe(user_id)
        queue = Thread::Queue.new
        @subscribers.compute(user_id) do |existing|
          list = existing || []
          if list.size >= MAX_PER_USER
            raise TooManySubscribersError, "user #{user_id} has #{list.size} active subscribers"
          end

          list + [queue]
        end
        queue
      end

      def unsubscribe(user_id, queue)
        @subscribers.compute(user_id) do |existing|
          remaining = (existing || []).reject { |q| q.equal?(queue) }
          remaining.empty? ? nil : remaining
        end
      end

      def publish(user_id)
        queues = @subscribers[user_id]
        return if queues.nil?

        queues.each do |q|
          q << :changed
        rescue ClosedQueueError
        end
      end

      def reset!
        @subscribers = Concurrent::Map.new
      end
    end
  end
end

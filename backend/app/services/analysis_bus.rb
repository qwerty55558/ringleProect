require "concurrent"

module AnalysisBus
  MAX_PER_USER = 4

  @subscribers = Concurrent::Map.new

  class << self
    def subscribe(user_id)
      queue = Thread::Queue.new
      @subscribers.compute(user_id) do |existing|
        list = existing || []
        list = list.reject { |q| q.closed? }
        list + [queue]
      end
      queue
    end

    def unsubscribe(user_id, queue)
      @subscribers.compute(user_id) do |existing|
        remaining = (existing || []).reject { |q| q.equal?(queue) || q.closed? }
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

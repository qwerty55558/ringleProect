require "rails_helper"

# Verifies the two layers of refresh-storm defense for SSE endpoints:
#
#   1. Rack::Attack throttle on SSE *opens* (per user, per IP). Stops
#      a malicious client from cycling fresh connections faster than
#      we can clean them up.
#
#   2. Me::Bus per-user concurrent-subscriber cap. Even if a client
#      slips past the request rate limit, the bus refuses to register
#      more than MAX_PER_USER active subscribers and the SSE
#      controller surfaces an `event: error` immediately.
#
# These two together bound how many open SSE fibers a single user can
# accumulate inside MAX_DURATION, regardless of how fast they refresh.
RSpec.describe "SSE refresh-storm defense", type: :request do
  let(:user) { create(:user) }

  describe "Rack::Attack throttle on /api/v1/me/stream opens" do
    around do |example|
      previous_store = Rack::Attack.cache.store
      previous_enabled = Rack::Attack.enabled
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.enabled = true
      Rack::Attack.reset!
      example.run
    ensure
      Rack::Attack.enabled = previous_enabled
      Rack::Attack.cache.store = previous_store
      Rack::Attack.cache.store&.clear if Rack::Attack.cache.store.respond_to?(:clear)
    end

    # Keep each SSE controller invocation tiny so the test suite isn't
    # waiting for fibers to drain. The throttle decision happens in
    # the rack middleware *before* the controller runs, so cap doesn't
    # affect what we're measuring.
    before do
      stub_const("Api::V1::MeStreamController::MAX_DURATION", 0.05)
      stub_const("Api::V1::MeStreamController::HEARTBEAT_INTERVAL", 0.02)
      Me::Bus.reset!
    end

    it "429s the 31st open within a minute (per-user cap = 30)" do
      30.times do
        get "/api/v1/me/stream", headers: { "X-User-Id" => user.id.to_s }
        expect(response.status).to eq(200), "expected 200, got #{response.status} on iteration"
      end

      get "/api/v1/me/stream", headers: { "X-User-Id" => user.id.to_s }
      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("rate_limited")
      expect(response.headers["Retry-After"]).to be_present
    end
  end

  describe "Me::Bus.MAX_PER_USER concurrent-subscriber cap" do
    before { Me::Bus.reset! }

    it "raises TooManySubscribersError beyond MAX_PER_USER" do
      Me::Bus::MAX_PER_USER.times { Me::Bus.subscribe(user.id) }

      expect { Me::Bus.subscribe(user.id) }
        .to raise_error(Me::Bus::TooManySubscribersError, /#{user.id}/)
    end

    it "lets a freed slot be reused" do
      queues = Array.new(Me::Bus::MAX_PER_USER) { Me::Bus.subscribe(user.id) }
      Me::Bus.unsubscribe(user.id, queues.last)

      expect { Me::Bus.subscribe(user.id) }.not_to raise_error
    end

    it "the SSE controller catches the cap and writes an `event: error` frame" do
      Me::Bus::MAX_PER_USER.times { Me::Bus.subscribe(user.id) }
      stub_const("Api::V1::MeStreamController::MAX_DURATION", 0.05)
      stub_const("Api::V1::MeStreamController::HEARTBEAT_INTERVAL", 0.02)

      get "/api/v1/me/stream", headers: { "X-User-Id" => user.id.to_s }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("event: error")
      expect(response.body).to include("too_many_connections")
    end
  end
end

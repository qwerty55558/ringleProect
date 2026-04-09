require "rails_helper"

RSpec.describe "GET /api/v1/me/stream", type: :request do
  let(:user) { create(:user) }

  before do
    Me::Bus.reset!
    # Cap how long any example can sit in the SSE loop. Each test sets
    # MAX_DURATION small so the loop drains and returns control to the
    # test runner instead of blocking the whole suite.
    stub_const("Api::V1::MeStreamController::MAX_DURATION", 0.15)
    stub_const("Api::V1::MeStreamController::HEARTBEAT_INTERVAL", 0.05)
  end

  it "401s without any user identifier" do
    get "/api/v1/me/stream"
    expect(response).to have_http_status(:unauthorized)
  end

  it "pushes an initial snapshot on connect (X-User-Id header auth)" do
    create(:membership, user: user, membership_plan: create(:premium_plan))

    get "/api/v1/me/stream", headers: { "X-User-Id" => user.id.to_s }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to start_with("text/event-stream")
    expect(response.body).to include("event: snapshot")
    expect(response.body).to include('"features":["study","talk","analysis"]')
  end

  it "pushes via the ?user_id= query param when no header is set (EventSource)" do
    create(:membership, user: user, membership_plan: create(:basic_plan))

    get "/api/v1/me/stream", params: { user_id: user.id }

    expect(response).to have_http_status(:ok)
    snapshot = first_snapshot_payload(response.body)
    expect(snapshot["user"]["id"]).to eq(user.id)
    expect(snapshot["features"]).to eq(["study"])
  end

  it "wakes the loop and pushes a fresh snapshot when Me::Bus is published mid-stream" do
    plan = create(:premium_plan)
    membership = create(:membership, user: user, membership_plan: plan)

    # Hold the loop open longer than the publisher's first sleep so
    # the bus signal lands while we're parked on Queue#pop.
    stub_const("Api::V1::MeStreamController::MAX_DURATION", 0.3)

    publisher = Thread.new do
      sleep 0.05
      membership.update!(status: "revoked") # → after_commit → Me::Bus.publish
    end

    get "/api/v1/me/stream", headers: { "X-User-Id" => user.id.to_s }
    publisher.join

    snapshots = all_snapshot_payloads(response.body)
    expect(snapshots.length).to be >= 2
    expect(snapshots.first["features"]).to include("talk")
    expect(snapshots.last["features"]).not_to include("talk")
  end

  it "wakes the loop on the membership's expires_at deadline without any explicit publish" do
    plan = create(:premium_plan)
    # Membership that expires ~80ms into the loop. The controller's
    # Queue#pop(timeout:) is computed from expires_at, so it will
    # unblock at exactly this moment with no polling in between.
    create(:membership, user: user, membership_plan: plan,
                        started_at: 1.minute.ago, expires_at: Time.current + 0.08)

    stub_const("Api::V1::MeStreamController::MAX_DURATION", 0.3)
    stub_const("Api::V1::MeStreamController::HEARTBEAT_INTERVAL", 5.0) # don't let heartbeat hide it

    get "/api/v1/me/stream", headers: { "X-User-Id" => user.id.to_s }

    snapshots = all_snapshot_payloads(response.body)
    expect(snapshots.length).to be >= 2
    expect(snapshots.first["memberships"].first["state"]).to eq("active")
    expect(snapshots.last["memberships"].first["state"]).to eq("expired")
  end

  it "sends a heartbeat when nothing changes between ticks" do
    create(:membership, user: user, membership_plan: create(:basic_plan))

    stub_const("Api::V1::MeStreamController::MAX_DURATION", 0.12)
    stub_const("Api::V1::MeStreamController::HEARTBEAT_INTERVAL", 0.04)

    get "/api/v1/me/stream", headers: { "X-User-Id" => user.id.to_s }

    expect(response.body).to include("event: heartbeat")
  end

  def first_snapshot_payload(body)
    all_snapshot_payloads(body).first
  end

  # Walks the SSE body and returns the parsed JSON of every "snapshot"
  # event in order. We track the previous line so we know which `data:`
  # belongs to which `event:`.
  def all_snapshot_payloads(body)
    out = []
    current_event = nil
    body.each_line do |line|
      line = line.chomp
      if line.start_with?("event:")
        current_event = line.sub(/^event:\s*/, "")
      elsif line.start_with?("data:") && current_event == "snapshot"
        out << JSON.parse(line.sub(/^data:\s*/, ""))
      elsif line.empty?
        current_event = nil
      end
    end
    out
  end
end

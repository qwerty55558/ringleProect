require "rails_helper"

RSpec.describe "GET /api/v1/admin/memberships/stream", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:user)  { create(:user) }

  before do
    Admin::MembershipBus.reset!
    stub_const("Api::V1::Admin::MembershipStreamController::MAX_DURATION", 0.15)
    stub_const("Api::V1::Admin::MembershipStreamController::HEARTBEAT_INTERVAL", 0.05)
  end

  it "401s without any user identifier" do
    get "/api/v1/admin/memberships/stream"
    expect(response).to have_http_status(:unauthorized)
  end

  it "403s for a non-admin caller" do
    get "/api/v1/admin/memberships/stream", headers: { "X-User-Id" => user.id.to_s }
    expect(response).to have_http_status(:forbidden)
  end

  it "emits a `ready` frame on connect for an admin caller (header auth)" do
    get "/api/v1/admin/memberships/stream", headers: { "X-User-Id" => admin.id.to_s }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to start_with("text/event-stream")
    expect(response.body).to include("event: ready")
  end

  it "accepts the user via the ?user_id= query param (EventSource has no headers)" do
    get "/api/v1/admin/memberships/stream", params: { user_id: admin.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("event: ready")
  end

  it "pushes a `changed` frame when ANY user's membership row mutates" do
    stub_const("Api::V1::Admin::MembershipStreamController::MAX_DURATION", 0.3)

    publisher = Thread.new do
      sleep 0.05
      create(:membership, user: user, membership_plan: create(:premium_plan))
    end

    get "/api/v1/admin/memberships/stream", headers: { "X-User-Id" => admin.id.to_s }
    publisher.join

    expect(response.body).to include("event: changed")
  end

  it "pushes a `changed` frame when a membership crosses its expires_at deadline" do
    plan = create(:premium_plan)
    create(:membership, user: user, membership_plan: plan,
                        started_at: 1.minute.ago, expires_at: Time.current + 0.08)

    stub_const("Api::V1::Admin::MembershipStreamController::MAX_DURATION", 0.3)
    stub_const("Api::V1::Admin::MembershipStreamController::HEARTBEAT_INTERVAL", 5.0)

    get "/api/v1/admin/memberships/stream", headers: { "X-User-Id" => admin.id.to_s }

    expect(response.body).to include("event: changed")
  end
end

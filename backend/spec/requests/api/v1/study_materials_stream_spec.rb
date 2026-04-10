require "rails_helper"

RSpec.describe "GET /api/v1/study_materials/stream", type: :request do
  let(:user) { create(:user) }

  before do
    create(:membership, user: user, membership_plan: create(:basic_plan))
    Study::Bus.reset!
    stub_const("Api::V1::StudyMaterialsStreamController::MAX_DURATION", 0.15)
    stub_const("Api::V1::StudyMaterialsStreamController::HEARTBEAT_INTERVAL", 0.05)
  end

  it "401s without any user identifier" do
    get "/api/v1/study_materials/stream"
    expect(response).to have_http_status(:unauthorized)
  end

  it "403s when the caller has no study feature" do
    no_study = create(:user)
    get "/api/v1/study_materials/stream", headers: { "X-User-Id" => no_study.id.to_s }
    expect(response).to have_http_status(:forbidden)
  end

  it "emits a `ready` frame on connect for a study learner" do
    get "/api/v1/study_materials/stream", headers: { "X-User-Id" => user.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to start_with("text/event-stream")
    expect(response.body).to include("event: ready")
  end

  it "pushes a `changed` frame when Study::Bus is published mid-stream" do
    stub_const("Api::V1::StudyMaterialsStreamController::MAX_DURATION", 0.3)

    publisher = Thread.new do
      sleep 0.05
      Study::Bus.publish
    end

    get "/api/v1/study_materials/stream", headers: { "X-User-Id" => user.id.to_s }
    publisher.join

    expect(response.body).to include("event: changed")
  end
end

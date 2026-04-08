require "rails_helper"

RSpec.describe "GET /api/v1/me", type: :request do
  let(:user) { create(:user) }

  it "401s without X-User-Id" do
    get "/api/v1/me"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns the user, memberships, and union of features" do
    plan = create(:premium_plan)
    create(:membership, user: user, membership_plan: plan)

    get "/api/v1/me", headers: { "X-User-Id" => user.id.to_s }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["user"]["email"]).to eq(user.email)
    expect(body["memberships"].length).to eq(1)
    expect(body["memberships"].first["state"]).to eq("active")
    expect(body["features"]).to match_array(%w[study talk analysis])
  end

  it "marks expired memberships as expired in the response" do
    plan = create(:basic_plan)
    create(:membership, :expired, user: user, membership_plan: plan)

    get "/api/v1/me", headers: { "X-User-Id" => user.id.to_s }

    expect(JSON.parse(response.body)["memberships"].first["state"]).to eq("expired")
    expect(JSON.parse(response.body)["features"]).to eq([])
  end
end

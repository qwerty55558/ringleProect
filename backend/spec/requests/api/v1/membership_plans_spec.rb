require "rails_helper"

RSpec.describe "GET /api/v1/membership_plans", type: :request do
  it "returns only active plans, ordered by price" do
    cheap = create(:basic_plan, price_cents: 1000)
    pricey = create(:premium_plan, price_cents: 5000)
    create(:membership_plan, name: "Hidden", active: false)

    get "/api/v1/membership_plans"

    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).map { |p| p["id"] }
    expect(ids).to eq([cheap.id, pricey.id])
  end
end

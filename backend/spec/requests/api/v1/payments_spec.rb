require "rails_helper"

RSpec.describe "POST /api/v1/payments", type: :request do
  let(:user) { create(:user) }
  let(:plan) { create(:premium_plan) }
  let(:headers) { { "X-User-Id" => user.id.to_s } }

  it "creates a payment and a matching active membership when given a success token" do
    expect {
      post "/api/v1/payments",
           params: { membership_plan_id: plan.id, payment_method: { card_token: "tok_visa" } },
           headers: headers
    }.to change(Payment, :count).by(1).and change(Membership, :count).by(1)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["payment"]["status"]).to eq("succeeded")
    expect(body["payment"]["pg_transaction_id"]).to be_present
    expect(body["payment"]["card_brand"]).to eq("Visa")
    expect(body["membership"]["state"]).to eq("active")

    membership = Membership.find(body["membership"]["id"])
    expect(membership.source).to eq("purchase")
    expect(membership.user).to eq(user)
  end

  it "defaults to a successful card when payment_method is omitted" do
    expect {
      post "/api/v1/payments", params: { membership_plan_id: plan.id }, headers: headers
    }.to change(Payment, :count).by(1)
  end

  it "rolls back and returns 402 for a declined token" do
    expect {
      post "/api/v1/payments",
           params: { membership_plan_id: plan.id, payment_method: { card_token: "tok_visa_declined" } },
           headers: headers
    }.not_to change(Membership, :count)

    expect(response).to have_http_status(:payment_required)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("payment_declined")
    expect(body["reason"]).to eq("card_declined")
  end

  it "rolls back and returns 502 for a processing error token" do
    expect {
      post "/api/v1/payments",
           params: { membership_plan_id: plan.id, payment_method: { card_token: "tok_processing_error" } },
           headers: headers
    }.not_to change(Membership, :count)

    expect(response).to have_http_status(:bad_gateway)
    expect(JSON.parse(response.body)["error"]).to eq("payment_processing_error")
  end

  it "401s without a user header" do
    post "/api/v1/payments", params: { membership_plan_id: plan.id }
    expect(response).to have_http_status(:unauthorized)
  end
end

RSpec.describe "GET /api/v1/payments/test_cards", type: :request do
  let(:user) { create(:user) }

  it "lists every registered test card" do
    get "/api/v1/payments/test_cards", headers: { "X-User-Id" => user.id.to_s }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    tokens = body.map { |c| c["token"] }
    expect(tokens).to include("tok_visa", "tok_visa_declined")
  end
end

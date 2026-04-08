require "rails_helper"

RSpec.describe "POST /api/v1/payments", type: :request do
  let(:user) { create(:user) }
  let(:plan) { create(:premium_plan) }

  it "creates a payment and a matching active membership" do
    expect {
      post "/api/v1/payments",
           params: { membership_plan_id: plan.id },
           headers: { "X-User-Id" => user.id.to_s }
    }.to change(Payment, :count).by(1).and change(Membership, :count).by(1)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["payment"]["status"]).to eq("succeeded")
    expect(body["payment"]["pg_transaction_id"]).to be_present
    expect(body["membership"]["state"]).to eq("active")

    membership = Membership.find(body["membership"]["id"])
    expect(membership.source).to eq("purchase")
    expect(membership.user).to eq(user)
  end

  it "rolls back when the gateway raises" do
    allow(PaymentGateway).to receive(:charge!).and_raise(PaymentGateway::DeclinedError, "declined")

    expect {
      post "/api/v1/payments",
           params: { membership_plan_id: plan.id },
           headers: { "X-User-Id" => user.id.to_s }
    }.not_to change(Membership, :count)

    expect(response).to have_http_status(:payment_required)
    expect(JSON.parse(response.body)["error"]).to eq("payment_failed")
  end

  it "401s without a user header" do
    post "/api/v1/payments", params: { membership_plan_id: plan.id }
    expect(response).to have_http_status(:unauthorized)
  end
end

require "rails_helper"

RSpec.describe PaymentGateway do
  let(:user) { create(:user) }

  it "returns a result with a deterministic id when an idempotency key is given" do
    res = described_class.charge!(user: user, amount_cents: 1000, idempotency_key: "abc")
    expect(res.transaction_id).to eq("abc")
    expect(res.amount_cents).to eq(1000)
  end

  it "generates a transaction id when no idempotency key is given" do
    res = described_class.charge!(user: user, amount_cents: 1000)
    expect(res.transaction_id).to start_with("mock_pg_")
  end

  it "raises on non-positive amount" do
    expect { described_class.charge!(user: user, amount_cents: 0) }.to raise_error(ArgumentError)
  end
end

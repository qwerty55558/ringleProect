require "rails_helper"

RSpec.describe PaymentGateway do
  let(:user) { create(:user) }

  describe ".charge!" do
    it "returns a result with a deterministic id when an idempotency key is given" do
      res = described_class.charge!(user: user, amount_cents: 1000, idempotency_key: "abc")
      expect(res.transaction_id).to eq("abc")
      expect(res.amount_cents).to eq(1000)
      expect(res.card_brand).to eq("Visa")
    end

    it "generates a transaction id when no idempotency key is given" do
      res = described_class.charge!(user: user, amount_cents: 1000)
      expect(res.transaction_id).to start_with("mock_pg_")
    end

    it "raises on non-positive amount" do
      expect { described_class.charge!(user: user, amount_cents: 0) }.to raise_error(ArgumentError)
    end

    it "honours an explicit success token" do
      res = described_class.charge!(user: user, amount_cents: 500, card_token: "tok_mastercard")
      expect(res.card_brand).to eq("Mastercard")
    end

    it "raises DeclinedError for tok_visa_declined" do
      expect {
        described_class.charge!(user: user, amount_cents: 500, card_token: "tok_visa_declined")
      }.to raise_error(PaymentGateway::DeclinedError, /card_declined/)
    end

    it "raises DeclinedError for tok_insufficient" do
      expect {
        described_class.charge!(user: user, amount_cents: 500, card_token: "tok_insufficient")
      }.to raise_error(PaymentGateway::DeclinedError, /insufficient_funds/)
    end

    it "raises ProcessingError for tok_processing_error" do
      expect {
        described_class.charge!(user: user, amount_cents: 500, card_token: "tok_processing_error")
      }.to raise_error(PaymentGateway::ProcessingError, /processing_error/)
    end

    it "treats unknown tokens as declined (never silently succeed)" do
      expect {
        described_class.charge!(user: user, amount_cents: 500, card_token: "tok_garbage")
      }.to raise_error(PaymentGateway::DeclinedError, /unknown_card/)
    end
  end

  describe ".test_cards" do
    it "exposes every registered token to the frontend picker" do
      tokens = described_class.test_cards.map { |c| c[:token] }
      expect(tokens).to include("tok_visa", "tok_visa_declined", "tok_insufficient", "tok_processing_error")
    end

    it "includes dummy display fields for the mock checkout modal" do
      visa = described_class.test_cards.find { |c| c[:token] == "tok_visa" }
      expect(visa).to include(
        brand:  "Visa",
        number: a_string_matching(/\A\d{4} \d{4} \d{4} \d{4}\z/),
        expiry: a_string_matching(%r{\A\d{2}/\d{2}\z}),
        cvc:    a_string_matching(/\A\d{3}\z/),
        holder: a_kind_of(String)
      )
    end
  end
end

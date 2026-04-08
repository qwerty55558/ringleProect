# Mock Payment Gateway. The real engagement with a PG provider is out of
# scope per the spec, so we simulate a successful charge and return a fake
# transaction id. Failure modes are exposed via raise so callers can wrap
# the call in a transaction and roll back the membership creation.
class PaymentGateway
  Result = Struct.new(:transaction_id, :amount_cents, keyword_init: true)

  class Error < StandardError; end
  class DeclinedError < Error; end

  def self.charge!(user:, amount_cents:, idempotency_key: nil)
    # In a real integration we'd POST to the PG API here. The spec asks us
    # to assume PG success, so we synthesize a transaction id deterministically.
    raise ArgumentError, "amount must be > 0" if amount_cents.to_i <= 0

    Result.new(
      transaction_id: idempotency_key.presence || "mock_pg_#{SecureRandom.hex(8)}",
      amount_cents: amount_cents
    )
  end
end

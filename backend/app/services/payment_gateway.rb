# Mock Payment Gateway.
#
# The spec excludes integrating with a real PG, but it explicitly asks us to
# call a mock object so the rest of the purchase flow can be exercised end
# to end. Rather than always-succeed (which is what the v1 stub did), this
# mock branches on a `card_token` so:
#
#   - The frontend can offer a "test cards" picker and the recruiter can
#     drive every payment failure path during the demo.
#   - Specs can drive declines / processing errors without stubbing the
#     class itself — they just pass the failing token.
#
# The token vocabulary intentionally mirrors how Stripe / TossPayments
# expose their test fixtures so the abstraction would survive a real PG
# integration: swap PaymentGateway.charge! for the real client and the
# Memberships::Purchase service is unchanged.
class PaymentGateway
  Result = Struct.new(:transaction_id, :amount_cents, :card_brand, keyword_init: true)

  class Error          < StandardError; end
  class DeclinedError  < Error; end
  class ProcessingError < Error; end

  # Token registry. Each entry describes one simulated card the demo /
  # tests can submit. New scenarios are added in one place. The display
  # fields (number/expiry/cvc/holder) are pure fixtures used by the
  # frontend's mock checkout modal so the recruiter can "fill in" a card
  # without typing anything — the real PG handshake stays token-based.
  TEST_CARDS = {
    "tok_visa" => {
      brand: "Visa", outcome: :success, label: "정상 카드 (Visa)",
      number: "4242 4242 4242 4242", expiry: "12/29", cvc: "123", holder: "RINGLE DEMO"
    },
    "tok_mastercard" => {
      brand: "Mastercard", outcome: :success, label: "정상 카드 (Mastercard)",
      number: "5555 5555 5555 4444", expiry: "11/28", cvc: "321", holder: "RINGLE DEMO"
    },
    "tok_visa_declined" => {
      brand: "Visa", outcome: :declined, label: "거절된 카드", reason: "card_declined",
      number: "4000 0000 0000 0002", expiry: "10/27", cvc: "234", holder: "DECLINED CARD"
    },
    "tok_insufficient" => {
      brand: "Visa", outcome: :declined, label: "한도 초과", reason: "insufficient_funds",
      number: "4000 0000 0000 9995", expiry: "09/27", cvc: "345", holder: "LOW BALANCE"
    },
    "tok_processing_error" => {
      brand: "Visa", outcome: :processing, label: "PG 일시 오류", reason: "processing_error",
      number: "4000 0000 0000 0119", expiry: "08/27", cvc: "456", holder: "PG TIMEOUT"
    }
  }.freeze

  DEFAULT_TOKEN = "tok_visa".freeze

  def self.test_cards
    TEST_CARDS.map do |token, data|
      {
        token:   token,
        label:   data[:label],
        outcome: data[:outcome],
        brand:   data[:brand],
        number:  data[:number],
        expiry:  data[:expiry],
        cvc:     data[:cvc],
        holder:  data[:holder]
      }
    end
  end

  def self.charge!(user:, amount_cents:, card_token: DEFAULT_TOKEN, idempotency_key: nil)
    raise ArgumentError, "amount must be > 0" if amount_cents.to_i <= 0

    card = TEST_CARDS[card_token.to_s.presence || DEFAULT_TOKEN]
    raise DeclinedError, "unknown_card" unless card

    case card[:outcome]
    when :declined
      raise DeclinedError, card[:reason]
    when :processing
      raise ProcessingError, card[:reason]
    end

    Result.new(
      transaction_id: idempotency_key.presence || "mock_pg_#{SecureRandom.hex(8)}",
      amount_cents: amount_cents,
      card_brand: card[:brand]
    )
  end
end

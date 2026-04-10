require "rails_helper"

RSpec.describe GoogleTranslateClient do
  def make_client(status:, body:)
    conn = Faraday.new do |b|
      b.response :json
      b.adapter :test do |s|
        s.get("") { [status, { "Content-Type" => "application/json" }, body.to_json] }
      end
    end
    client = described_class.new
    client.instance_variable_set(:@conn, conn)
    client
  end

  it "returns translated text on success" do
    body = [[["안녕하세요", "Hello", nil, nil, nil, nil, nil, []], [nil, nil, "annyeonghaseyo"]], nil, "en"]
    client = make_client(status: 200, body: body)

    expect(client.translate("Hello")).to eq("안녕하세요")
  end

  it "raises Error on non-200 response" do
    client = make_client(status: 503, body: { error: "unavailable" })

    expect { client.translate("Hello") }
      .to raise_error(GoogleTranslateClient::Error, /503/)
  end

  it "raises Error on unexpected response shape" do
    client = make_client(status: 200, body: "not an array")

    expect { client.translate("Hello") }
      .to raise_error(GoogleTranslateClient::Error, /unexpected/)
  end
end

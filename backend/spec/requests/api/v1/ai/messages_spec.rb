require "rails_helper"

RSpec.describe "POST /api/v1/ai/messages", type: :request do
  let(:user) { create(:user) }
  let(:plan) { create(:premium_plan) }

  before { create(:membership, user: user, membership_plan: plan) }

  it "403s when the user lacks the talk feature" do
    other = create(:user)
    create(:membership, user: other, membership_plan: create(:basic_plan))

    post "/api/v1/ai/messages",
         params: { messages: [{ role: "user", text: "hello" }] }.to_json,
         headers: { "X-User-Id" => other.id.to_s, "Content-Type" => "application/json" }

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)["error"]).to eq("membership_required")
  end

  it "401s without an X-User-Id header" do
    post "/api/v1/ai/messages",
         params: { messages: [{ role: "user", text: "hello" }] }.to_json,
         headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "streams Gemini deltas as SSE events" do
    fake_client = instance_double(GeminiClient)
    allow(GeminiClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:stream_chat) do |**, &block|
      block.call("Hello ")
      block.call("there!")
    end

    post "/api/v1/ai/messages",
         params: { messages: [{ role: "user", text: "hi" }] }.to_json,
         headers: { "X-User-Id" => user.id.to_s, "Content-Type" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('"delta":"Hello "')
    expect(response.body).to include('"delta":"there!"')
    expect(response.body).to include("event: done")
  end

  it "falls back to the next model when the first model fails" do
    call_count = 0
    fake_client = instance_double(GeminiClient)
    allow(GeminiClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:stream_chat) do |model:, **kwargs, &block|
      call_count += 1
      if model == "gemini-2.5-flash"
        raise GeminiClient::Error, "429 quota exceeded"
      end
      block.call("fallback ok")
    end

    post "/api/v1/ai/messages",
         params: { messages: [{ role: "user", text: "hi" }] }.to_json,
         headers: { "X-User-Id" => user.id.to_s, "Content-Type" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('"delta":"fallback ok"')
    expect(response.body).to include("event: done")
    expect(call_count).to be >= 2
  end

  it "sends error event only when all models are exhausted" do
    fake_client = instance_double(GeminiClient)
    allow(GeminiClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:stream_chat).and_raise(GeminiClient::Error, "all failed")

    post "/api/v1/ai/messages",
         params: { messages: [{ role: "user", text: "hi" }] }.to_json,
         headers: { "X-User-Id" => user.id.to_s, "Content-Type" => "application/json" }

    expect(response.body).to include("event: error")
    expect(response.body).to include("ai_failed")
  end
end

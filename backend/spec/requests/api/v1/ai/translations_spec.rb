require "rails_helper"

RSpec.describe "POST /api/v1/ai/translations", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "X-User-Id" => user.id.to_s } }

  it "returns translated text" do
    allow_any_instance_of(GoogleTranslateClient)
      .to receive(:translate).and_return("안녕하세요")

    post "/api/v1/ai/translations",
         params: { text: "Hello" }.to_json,
         headers: headers.merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["translation"]).to eq("안녕하세요")
    expect(body["cache"]).to eq("miss")
  end

  it "serves from cache on the second identical request" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    fake = instance_double(GoogleTranslateClient, translate: "캐시됨")
    allow(GoogleTranslateClient).to receive(:new).and_return(fake)

    2.times do
      post "/api/v1/ai/translations",
           params: { text: "cached text" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
    end

    body = JSON.parse(response.body)
    expect(body["cache"]).to eq("hit")
    expect(fake).to have_received(:translate).once
  end

  it "rejects blank text" do
    post "/api/v1/ai/translations",
         params: { text: "  " }.to_json,
         headers: headers.merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:bad_request)
  end

  it "502s when Google Translate raises" do
    allow_any_instance_of(GoogleTranslateClient)
      .to receive(:translate).and_raise(GoogleTranslateClient::Error, "boom")

    post "/api/v1/ai/translations",
         params: { text: "Hello" }.to_json,
         headers: headers.merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:bad_gateway)
  end

  it "401s without auth header" do
    post "/api/v1/ai/translations",
         params: { text: "Hello" }.to_json,
         headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end
end

require "rails_helper"

RSpec.describe "Messages API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "X-User-Id" => user.id.to_s } }

  before do
    create(:membership, user: user, membership_plan: create(:premium_plan))
  end

  let(:conversation) { create(:conversation, user: user) }

  describe "POST /api/v1/conversations/:conversation_id/messages" do
    it "creates a user message" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { role: "user", text: "Hello there" },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["role"]).to eq("user")
      expect(body["text"]).to eq("Hello there")
    end

    it "creates a message with audio attachment" do
      audio = Rack::Test::UploadedFile.new(
        StringIO.new("fake-wav-bytes"), "audio/wav", original_filename: "speech.wav"
      )

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { role: "user", text: "With audio", audio: audio },
           headers: headers

      expect(response).to have_http_status(:created)
      msg = conversation.messages.last
      expect(msg.audio).to be_attached
    end

    it "403s when user lacks talk feature" do
      other = create(:user)
      create(:membership, user: other, membership_plan: create(:basic_plan))
      conv = create(:conversation, user: other)

      post "/api/v1/conversations/#{conv.id}/messages",
           params: { role: "user", text: "Hi" },
           headers: { "X-User-Id" => other.id.to_s }

      expect(response).to have_http_status(:forbidden)
    end

    it "404s when conversation belongs to another user" do
      other = create(:user)
      create(:membership, user: other, membership_plan: create(:premium_plan))
      other_conv = create(:conversation, user: other)

      post "/api/v1/conversations/#{other_conv.id}/messages",
           params: { role: "user", text: "sneaky" },
           headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/conversations/:conversation_id/messages/:id/audio" do
    it "streams attached audio" do
      msg = conversation.append_message!(
        role: "user", text: "test",
        audio: Rack::Test::UploadedFile.new(
          StringIO.new("audio-data"), "audio/wav", original_filename: "test.wav"
        ),
        content_hash: "test-hash"
      )

      get "/api/v1/conversations/#{conversation.id}/messages/#{msg.id}/audio",
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("audio-data")
    end

    it "404s when audio not attached" do
      msg = conversation.append_message!(
        role: "user", text: "no audio", content_hash: "no-audio"
      )

      get "/api/v1/conversations/#{conversation.id}/messages/#{msg.id}/audio",
          headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end

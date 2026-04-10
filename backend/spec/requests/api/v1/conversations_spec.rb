require "rails_helper"

RSpec.describe "Api::V1::Conversations", type: :request do
  let(:user) { create(:user) }
  let(:plan) { create(:premium_plan) }
  let(:headers) { { "X-User-Id" => user.id.to_s } }

  before do
    # talk feature gate is enforced on create
    user.memberships.create!(
      membership_plan: plan,
      started_at: 1.day.ago,
      expires_at: 30.days.from_now,
      status: "active",
      source: "admin_grant"
    )
  end

  describe "POST /api/v1/conversations" do
    it "creates a conversation owned by the caller" do
      expect {
        post "/api/v1/conversations", headers: headers
      }.to change(Conversation, :count).by(1)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["id"]).to be_present
      expect(body["messages"]).to eq([])
    end

    it "403s when the user has no talk feature" do
      user.memberships.destroy_all
      post "/api/v1/conversations", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/conversations/:id" do
    it "returns the messages in position order with audio_url for attached blobs" do
      conversation = user.conversations.create!
      file = Rack::Test::UploadedFile.new(StringIO.new("wavbytes"), "audio/wav", original_filename: "u.wav")
      conversation.append_message!(role: "user",      text: "hi",   audio: file)
      conversation.append_message!(role: "assistant", text: "back")

      get "/api/v1/conversations/#{conversation.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["messages"].length).to eq(2)
      expect(body["messages"][0]["audio_url"]).to be_present
      expect(body["messages"][1]["audio_url"]).to be_nil
    end

    it "404s when the conversation belongs to another user" do
      other = create(:user)
      foreign = other.conversations.create!
      get "/api/v1/conversations/#{foreign.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/conversations/:id" do
    it "removes the conversation, its messages, and their audio attachments" do
      conversation = user.conversations.create!
      file = Rack::Test::UploadedFile.new(StringIO.new("wavbytes"), "audio/wav", original_filename: "u.wav")
      conversation.append_message!(role: "user", text: "hi", audio: file)

      expect {
        delete "/api/v1/conversations/#{conversation.id}", headers: headers
      }.to change(Conversation, :count).by(-1).and change(Message, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end

RSpec.describe "Api::V1::Messages", type: :request do
  let(:user) { create(:user) }
  let(:plan) { create(:premium_plan) }
  let(:headers) { { "X-User-Id" => user.id.to_s } }
  let(:conversation) { user.conversations.create! }

  before do
    user.memberships.create!(
      membership_plan: plan,
      started_at: 1.day.ago,
      expires_at: 30.days.from_now,
      status: "active",
      source: "admin_grant"
    )
  end

  describe "POST /api/v1/conversations/:id/messages" do
    it "persists a user message with its audio blob and assigns the next position" do
      file = Rack::Test::UploadedFile.new(StringIO.new("wavbytes"), "audio/wav", original_filename: "u.wav")
      expect {
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { role: "user", text: "Hello there", audio: file },
             headers: headers
      }.to change(Message, :count).by(1)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["role"]).to eq("user")
      expect(body["text"]).to eq("Hello there")
      expect(body["position"]).to eq(0)
      expect(body["audio_url"]).to be_present
    end

    it "persists assistant messages without audio" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { role: "assistant", text: "Hi back" },
           headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["audio_url"]).to be_nil
    end
  end

  describe "GET /api/v1/conversations/:id/messages/:id/audio" do
    it "streams the attached blob" do
      file = Rack::Test::UploadedFile.new(StringIO.new("wavbytes"), "audio/wav", original_filename: "u.wav")
      message = conversation.append_message!(role: "user", text: "hi", audio: file)
      get "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/audio", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("wavbytes")
    end

    it "404s when no audio is attached" do
      message = conversation.append_message!(role: "assistant", text: "no audio")
      get "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/audio", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end

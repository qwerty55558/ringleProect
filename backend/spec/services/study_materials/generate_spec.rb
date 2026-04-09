require "rails_helper"

RSpec.describe StudyMaterials::Generate do
  let(:user) { create(:user) }

  let(:fake_payload) do
    {
      "slug" => "test-topic",
      "title" => "Test Topic",
      "level" => "beginner",
      "category" => "daily",
      "description" => "테스트용",
      "scenario_prompt" => "stay on topic",
      "key_expressions" => ["one", "two"],
      "example_dialogue" => [{ "role" => "assistant", "text" => "hi" }]
    }
  end

  let(:fake_client) do
    instance_double(GeminiClient).tap do |c|
      allow(c).to receive(:stream_chat) do |**, &block|
        block.call(fake_payload.to_json)
      end
    end
  end

  describe ".call" do
    it "persists a new ai_generated row and increments the user counter" do
      expect {
        described_class.call(topic: "negotiating salary", user: user, client: fake_client)
      }.to change(StudyMaterial, :count).by(1)
        .and change { user.reload.study_generations_used }.from(0).to(1)

      expect(StudyMaterial.last.ai_generated).to be(true)
    end

    it "is idempotent on slug — re-running the same prompt updates instead of duplicating" do
      described_class.call(topic: "x", user: user, client: fake_client)
      other = create(:user)

      expect {
        described_class.call(topic: "x", user: other, client: fake_client)
      }.to change(StudyMaterial, :count).by(0)
        .and change { other.reload.study_generations_used }.from(0).to(1)
    end
  end

  describe "per-user generation cap" do
    it "raises GenerationLimitReached at the cap and does NOT touch Gemini" do
      user.update!(study_generations_used: described_class::MAX_PER_USER)

      expect(fake_client).not_to receive(:stream_chat)
      expect {
        described_class.call(topic: "x", user: user, client: fake_client)
      }.to raise_error(described_class::GenerationLimitReached, /#{described_class::MAX_PER_USER}/)
    end

    it "allows exactly MAX_PER_USER successful generations" do
      described_class::MAX_PER_USER.times do |i|
        described_class.call(topic: "topic-#{i}", user: user, client: fake_client_for(i))
      end
      expect(user.reload.study_generations_used).to eq(described_class::MAX_PER_USER)

      expect {
        described_class.call(topic: "one too many", user: user, client: fake_client)
      }.to raise_error(described_class::GenerationLimitReached)
    end

    it "does NOT increment the counter when Gemini fails (no slot burnt on error)" do
      bad_client = instance_double(GeminiClient)
      allow(bad_client).to receive(:stream_chat).and_raise(GeminiClient::Error, "boom")

      expect {
        described_class.call(topic: "x", user: user, client: bad_client)
      }.to raise_error(GeminiClient::Error)

      expect(user.reload.study_generations_used).to eq(0)
    end
  end

  describe "profanity filter" do
    it "rejects a banned word in the input topic before touching Gemini" do
      expect(fake_client).not_to receive(:stream_chat)
      expect {
        described_class.call(topic: "fuck this", user: user, client: fake_client)
      }.to raise_error(described_class::InappropriateContent, /fuck/)
      expect(user.reload.study_generations_used).to eq(0)
    end

    it "rejects Korean profanity in the input topic" do
      expect {
        described_class.call(topic: "씨발 영어 알려줘", user: user, client: fake_client)
      }.to raise_error(described_class::InappropriateContent, /씨발/)
    end

    it "rejects a banned word that appears in the AI-generated output" do
      dirty_payload = fake_payload.merge("title" => "What the fuck", "slug" => "wtf-topic")
      dirty_client = instance_double(GeminiClient).tap do |c|
        allow(c).to receive(:stream_chat) { |**, &block| block.call(dirty_payload.to_json) }
      end

      expect {
        described_class.call(topic: "totally clean topic", user: user, client: dirty_client)
      }.to raise_error(described_class::InappropriateContent, /fuck/)

      expect(StudyMaterial.where(slug: "wtf-topic")).not_to exist
      expect(user.reload.study_generations_used).to eq(0)
    end

    it "converts GeminiClient::SafetyBlocked into InappropriateContent" do
      blocked_client = instance_double(GeminiClient)
      allow(blocked_client).to receive(:stream_chat).and_raise(GeminiClient::SafetyBlocked, "response blocked: SAFETY")

      expect {
        described_class.call(topic: "totally clean", user: user, client: blocked_client)
      }.to raise_error(described_class::InappropriateContent, /safety filter/)

      expect(user.reload.study_generations_used).to eq(0)
    end
  end

  describe "profanity offense counter + slot penalty" do
    it "increments study_profanity_offenses on each flagged input" do
      expect {
        described_class.call(topic: "fuck this", user: user, client: fake_client) rescue nil
      }.to change { user.reload.study_profanity_offenses }.from(0).to(1)
    end

    it "deducts one generation slot every PROFANITY_PENALTY_INTERVAL offenses" do
      2.times do
        described_class.call(topic: "fuck", user: user, client: fake_client) rescue nil
      end
      expect(user.reload.study_generations_used).to eq(0)

      described_class.call(topic: "fuck", user: user, client: fake_client) rescue nil
      expect(user.reload.study_profanity_offenses).to eq(3)
      expect(user.reload.study_generations_used).to eq(1)
    end

    it "deducts again at the next interval (6th offense)" do
      6.times do
        described_class.call(topic: "fuck", user: user, client: fake_client) rescue nil
      end
      user.reload
      expect(user.study_profanity_offenses).to eq(6)
      expect(user.study_generations_used).to eq(2)
    end

    it "caps the deduction at MAX_PER_USER (no negative remaining)" do
      9.times do
        described_class.call(topic: "fuck", user: user, client: fake_client) rescue nil
      end
      expect(user.reload.study_generations_used).to eq(described_class::MAX_PER_USER)
    end
  end

  def fake_client_for(i)
    payload = fake_payload.merge("slug" => "test-topic-#{i}", "title" => "Test #{i}")
    instance_double(GeminiClient).tap do |c|
      allow(c).to receive(:stream_chat) do |**, &block|
        block.call(payload.to_json)
      end
    end
  end
end

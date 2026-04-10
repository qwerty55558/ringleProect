require "rails_helper"

RSpec.describe Conversations::Summarize do
  let(:user) { create(:user) }
  let(:conversation) { create(:conversation, user: user) }

  def add_messages(count)
    count.times do |i|
      create(:message,
        conversation: conversation,
        role: i.even? ? "user" : "assistant",
        text: "Message #{i + 1}",
        position: i
      )
    end
  end

  def fake_client(response: "Summary of the conversation.")
    instance_double(GeminiClient, chat: response)
  end

  describe ".call" do
    it "skips summarization when fewer than COMPRESS_THRESHOLD messages" do
      add_messages(5)
      client = fake_client
      result = described_class.call(conversation: conversation, client: client)

      expect(result).to be_nil
      expect(client).not_to have_received(:chat)
    end

    it "summarizes when message count reaches COMPRESS_THRESHOLD" do
      add_messages(6)
      client = fake_client(response: "  Learner discussed greetings.  ")

      result = described_class.call(conversation: conversation, client: client)

      expect(result).to eq("Learner discussed greetings.")
      expect(conversation.reload.context_summary).to eq("Learner discussed greetings.")
      expect(client).to have_received(:chat).once
    end

    it "sends only old messages (excluding RECENT_KEEP) to the LLM" do
      add_messages(8)
      client = fake_client

      described_class.call(conversation: conversation, client: client)

      call_args = client.as_null_object
      expect(client).to have_received(:chat) do |args|
        user_text = args[:messages].first[:text]
        expect(user_text).to include("Message 1")
        expect(user_text).to include("Message 4")
        expect(user_text).not_to include("Message 5")
        expect(user_text).not_to include("Message 8")
      end
    end

    it "chains previous context_summary into the new summarization" do
      conversation.update!(context_summary: "Previously discussed weather.")
      add_messages(6)
      client = fake_client

      described_class.call(conversation: conversation, client: client)

      expect(client).to have_received(:chat) do |args|
        user_text = args[:messages].first[:text]
        expect(user_text).to include("Previous context: Previously discussed weather.")
      end
    end

    it "uses the correct system instruction" do
      add_messages(6)
      client = fake_client

      described_class.call(conversation: conversation, client: client)

      expect(client).to have_received(:chat) do |args|
        expect(args[:system_instruction]).to include("conversation summarizer")
      end
    end
  end
end

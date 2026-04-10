require "rails_helper"

RSpec.describe Conversation, type: :model do
  let(:conversation) { create(:conversation) }

  describe "#append_message!" do
    it "auto-increments the position per turn" do
      m1 = conversation.append_message!(role: "user", text: "first")
      m2 = conversation.append_message!(role: "assistant", text: "second")
      expect(m1.position).to eq(0)
      expect(m2.position).to eq(1)
    end

    it "stores the content_hash so dedup queries can join on text" do
      m = conversation.append_message!(role: "assistant", text: "Hello", content_hash: TtsArtifact.hash_for("Hello"))
      expect(m.content_hash).to eq(TtsArtifact.hash_for("Hello"))
    end

    it "attaches the audio blob when one is supplied" do
      file = Rack::Test::UploadedFile.new(StringIO.new("RIFFfakewavdata"), "audio/wav", original_filename: "in.wav")
      m = conversation.append_message!(role: "user", text: "hi", audio: file)
      expect(m.audio).to be_attached
    end
  end

  it "destroys messages and their audio when the conversation is deleted" do
    file = Rack::Test::UploadedFile.new(StringIO.new("RIFFfakewavdata"), "audio/wav", original_filename: "in.wav")
    conversation.append_message!(role: "user", text: "hi", audio: file)
    expect { conversation.destroy! }.to change(Message, :count).by(-1)
  end
end

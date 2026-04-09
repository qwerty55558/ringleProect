require "rails_helper"

RSpec.describe Message, type: :model do
  let(:conversation) { create(:conversation) }

  it "is valid with required attributes" do
    msg = build(:message, conversation: conversation)
    expect(msg).to be_valid
  end

  it "validates role inclusion" do
    msg = build(:message, conversation: conversation, role: "system")
    expect(msg).not_to be_valid
    expect(msg.errors[:role]).to be_present
  end

  it "validates text presence" do
    msg = build(:message, conversation: conversation, text: "")
    expect(msg).not_to be_valid
    expect(msg.errors[:text]).to be_present
  end

  it "delegates user to conversation" do
    msg = build(:message, conversation: conversation)
    expect(msg.user).to eq(conversation.user)
  end

  it "reports audio? correctly" do
    msg = create(:message, conversation: conversation)
    expect(msg.audio?).to be false
  end
end

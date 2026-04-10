require "rails_helper"

RSpec.describe ContentFilter do
  describe ".clean?" do
    it "passes ordinary text" do
      expect(described_class.clean?("Hello, how are you?")).to be(true)
      expect(described_class.clean?("커피 주문하는 법 알려줘")).to be(true)
      expect(described_class.clean?("")).to be(true)
      expect(described_class.clean?(nil)).to be(true)
    end

    it "flags English profanity (case-insensitive, word-boundary)" do
      expect(described_class.clean?("this is fucking great")).to be(false)
      expect(described_class.clean?("FUCK this")).to be(false)
      expect(described_class.clean?("what an asshole")).to be(false)
    end

    it "does NOT flag legitimate words that contain a banned substring" do
      expect(described_class.clean?("Scunthorpe is a place")).to be(true)
      expect(described_class.clean?("classification of bass")).to be(true)
    end

    it "flags Korean profanity even without word boundaries" do
      expect(described_class.clean?("씨발 진짜")).to be(false)
      expect(described_class.clean?("존나 좋다")).to be(false)
      expect(described_class.clean?("이 개새끼야")).to be(false)
    end

    it "lets borderline insults through (denylist is explicit-only)" do
      expect(described_class.clean?("이 미친놈")).to be(true)
      expect(described_class.clean?("야 닥쳐")).to be(true)
      expect(described_class.clean?("그 새끼 진짜")).to be(true)
    end
  end

  describe ".flagged" do
    it "returns the list of matched words for diagnostics" do
      expect(described_class.flagged("fuck this 씨발")).to contain_exactly("fuck", "씨발")
    end
  end
end

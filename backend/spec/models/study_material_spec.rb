require "rails_helper"

RSpec.describe StudyMaterial, type: :model do
  subject {
    described_class.new(
      slug: "test-slug",
      title: "Test Material",
      description: "A test study material",
      scenario_prompt: "You are in a coffee shop...",
      level: "intermediate",
      category: "business",
      key_expressions: ["Could you elaborate?"],
      example_dialogue: [{ role: "assistant", text: "Hello!" }]
    )
  }

  it { is_expected.to be_valid }

  it "validates required fields" do
    blank = described_class.new
    blank.valid?
    expect(blank.errors[:slug]).to be_present
    expect(blank.errors[:title]).to be_present
    expect(blank.errors[:description]).to be_present
    expect(blank.errors[:scenario_prompt]).to be_present
  end

  it "validates level inclusion" do
    subject.level = "expert"
    expect(subject).not_to be_valid
    expect(subject.errors[:level]).to be_present
  end

  it "validates category inclusion" do
    subject.category = "cooking"
    expect(subject).not_to be_valid
    expect(subject.errors[:category]).to be_present
  end

  it "validates slug uniqueness" do
    subject.save!
    dup = described_class.new(subject.attributes.except("id"))
    expect(dup).not_to be_valid
    expect(dup.errors[:slug]).to be_present
  end

  it "defaults key_expressions to empty array" do
    m = described_class.new
    expect(m.key_expressions).to eq([])
  end

  it "defaults example_dialogue to empty array" do
    m = described_class.new
    expect(m.example_dialogue).to eq([])
  end
end

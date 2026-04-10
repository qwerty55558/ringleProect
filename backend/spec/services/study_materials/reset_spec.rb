require "rails_helper"

RSpec.describe StudyMaterials::Reset do
  # let! eagerly creates the user BEFORE the test body so the reset
  # actually has a row to wipe — plain `let` is lazy and would only
  # materialise on first reference, *after* Reset.call had already run.
  let!(:user) { create(:user, study_generations_used: 2) }

  before do
    StudyMaterials::CurriculumSeed.call
    create(:study_material, ai_generated: true, slug: "ai-leftover", level: "advanced")
  end

  it "wipes AI-generated rows" do
    expect { described_class.call }.to change { StudyMaterial.where(ai_generated: true).count }.to(0)
  end

  it "resets every user's study_generations_used counter" do
    described_class.call
    expect(user.reload.study_generations_used).to eq(0)
  end

  it "re-runs the CurriculumSeed so the seeded rows are still present afterwards" do
    seeded_count = StudyMaterial.where(ai_generated: false).count
    described_class.call
    expect(StudyMaterial.where(ai_generated: false).count).to eq(seeded_count)
  end

  it "publishes a content-free :changed signal on Study::Bus" do
    queue = Study::Bus.subscribe
    described_class.call
    expect(queue.pop(timeout: 0.1)).to eq(:changed)
    Study::Bus.unsubscribe(queue)
  end

  it "returns a counts hash so the controller can echo it to the dev panel" do
    counts = described_class.call
    expect(counts).to include(:deleted_ai_rows, :user_counters_reset, :seeded)
    expect(counts[:deleted_ai_rows]).to be >= 1
  end
end

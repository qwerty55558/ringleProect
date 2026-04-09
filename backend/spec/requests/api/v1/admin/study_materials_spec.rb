require "rails_helper"

RSpec.describe "POST /api/v1/admin/study_materials/reset", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:user)  { create(:user) }

  before do
    StudyMaterials::CurriculumSeed.call
    create(:study_material, ai_generated: true, slug: "ai-leftover", level: "advanced")
  end

  it "401s without a user identifier" do
    post "/api/v1/admin/study_materials/reset"
    expect(response).to have_http_status(:unauthorized)
  end

  it "works for non-admin callers (devtools, no RBAC)" do
    post "/api/v1/admin/study_materials/reset", headers: { "X-User-Id" => user.id.to_s }
    expect(response).to have_http_status(:ok)
  end

  it "wipes the AI-generated rows and reseeds for an admin caller" do
    expect {
      post "/api/v1/admin/study_materials/reset", headers: { "X-User-Id" => admin.id.to_s }
    }.to change { StudyMaterial.where(ai_generated: true).count }.to(0)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["ok"]).to be(true)
    expect(body["deleted_ai_rows"]).to be >= 1
  end
end

RSpec.describe "DELETE /api/v1/admin/study_materials/ai_generated", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:user)  { create(:user, study_generations_used: 2) }

  before do
    StudyMaterials::CurriculumSeed.call
    create(:study_material, ai_generated: true, slug: "ai-leftover-1", level: "advanced")
    create(:study_material, ai_generated: true, slug: "ai-leftover-2", level: "intermediate")
    Study::Bus.reset!
  end

  it "401s without a user identifier" do
    delete "/api/v1/admin/study_materials/ai_generated"
    expect(response).to have_http_status(:unauthorized)
  end

  it "works for non-admin callers (devtools, no RBAC)" do
    delete "/api/v1/admin/study_materials/ai_generated", headers: { "X-User-Id" => user.id.to_s }
    expect(response).to have_http_status(:ok)
  end

  it "wipes only AI-generated rows for an admin caller" do
    seeded_before = StudyMaterial.where(ai_generated: false).count

    expect {
      delete "/api/v1/admin/study_materials/ai_generated", headers: { "X-User-Id" => admin.id.to_s }
    }.to change { StudyMaterial.where(ai_generated: true).count }.to(0)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["ok"]).to be(true)
    expect(body["deleted"]).to eq(2)

    # Seeded rows are untouched.
    expect(StudyMaterial.where(ai_generated: false).count).to eq(seeded_before)
  end

  it "does NOT reset per-user generation counters (the targeted delete is non-destructive that way)" do
    user # eager-create
    delete "/api/v1/admin/study_materials/ai_generated", headers: { "X-User-Id" => admin.id.to_s }
    expect(user.reload.study_generations_used).to eq(2)
  end

  it "publishes a Study::Bus signal so subscribers refetch" do
    queue = Study::Bus.subscribe
    delete "/api/v1/admin/study_materials/ai_generated", headers: { "X-User-Id" => admin.id.to_s }
    expect(queue.pop(timeout: 0.1)).to eq(:changed)
    Study::Bus.unsubscribe(queue)
  end
end

RSpec.describe "POST /api/v1/admin/study_materials/reset_generation_counters", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let!(:dirty_user) { create(:user, study_generations_used: 2, study_profanity_offenses: 4) }
  let!(:clean_user) { create(:user) }

  it "401s without a user identifier" do
    post "/api/v1/admin/study_materials/reset_generation_counters"
    expect(response).to have_http_status(:unauthorized)
  end

  it "works for non-admin callers (devtools, no RBAC)" do
    post "/api/v1/admin/study_materials/reset_generation_counters",
         headers: { "X-User-Id" => dirty_user.id.to_s }
    expect(response).to have_http_status(:ok)
  end

  it "zeroes both counters for users that had any non-zero value" do
    post "/api/v1/admin/study_materials/reset_generation_counters",
         headers: { "X-User-Id" => admin.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["users_reset"]).to eq(1)

    expect(dirty_user.reload.study_generations_used).to eq(0)
    expect(dirty_user.reload.study_profanity_offenses).to eq(0)
  end

  it "publishes Me::Bus for each affected user so their /me/stream picks up the new quota" do
    Me::Bus.reset!
    queue = Me::Bus.subscribe(dirty_user.id)
    post "/api/v1/admin/study_materials/reset_generation_counters",
         headers: { "X-User-Id" => admin.id.to_s }
    expect(queue.pop(timeout: 0.1)).to eq(:changed)
    Me::Bus.unsubscribe(dirty_user.id, queue)
  end
end

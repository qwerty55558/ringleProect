require "rails_helper"

RSpec.describe "Api::V1::StudyMaterials", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "X-User-Id" => user.id.to_s } }

  before do
    create(:membership, user: user, membership_plan: create(:premium_plan))
    StudyMaterials::CurriculumSeed.call
  end

  describe "GET /api/v1/study_materials" do
    it "returns the curriculum split into seeded and ai_generated buckets" do
      get "/api/v1/study_materials", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.keys).to contain_exactly("seeded", "ai_generated")
      expect(body["seeded"]).to be_an(Array)
      expect(body["ai_generated"]).to be_an(Array)
      expect(body["seeded"].first.keys).to include("title", "scenario_prompt", "key_expressions", "ai_generated")
    end

    it "samples exactly 2 seeded rows per difficulty level" do
      get "/api/v1/study_materials", headers: headers
      seeded = JSON.parse(response.body)["seeded"]
      grouped = seeded.group_by { |m| m["level"] }
      StudyMaterial::LEVELS.each do |level|
        expect((grouped[level] || []).length).to eq(2), "expected 2 for #{level}"
      end
    end

    it "leaves the AI section empty (no novice fallback) when no AI-generated curriculum exists" do
      StudyMaterial.where(ai_generated: true).delete_all

      get "/api/v1/study_materials", headers: headers
      body = JSON.parse(response.body)
      expect(body["ai_generated"]).to eq([])

      novices = body["seeded"].count { |m| m["level"] == "novice" }
      expect(novices).to eq(2)
    end

    it "returns up to 2 AI-generated rows when they exist" do
      StudyMaterial.where(ai_generated: true).delete_all
      create(:study_material, ai_generated: true, slug: "ai-a", level: "intermediate")

      get "/api/v1/study_materials", headers: headers
      expect(JSON.parse(response.body)["ai_generated"].length).to eq(1)
    end

    it "bumps view_count for every row it surfaces (round-robin rotation)" do
      StudyMaterial.update_all(view_count: 0)

      get "/api/v1/study_materials", headers: headers
      first_body = JSON.parse(response.body)
      first_picked_ids = (first_body["seeded"] + first_body["ai_generated"]).map { |m| m["id"] }

      # Each picked row should now have view_count = 1.
      StudyMaterial.where(id: first_picked_ids).each do |m|
        expect(m.view_count).to eq(1)
      end
    end

    it "403s when the caller has no study feature" do
      no_study = create(:user)
      get "/api/v1/study_materials", headers: { "X-User-Id" => no_study.id.to_s }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/study_materials/:id" do
    it "returns the requested material" do
      material = StudyMaterial.first
      get "/api/v1/study_materials/#{material.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["slug"]).to eq(material.slug)
    end
  end

  describe "POST /api/v1/study_materials/generate" do
    it "delegates to the Generate service and persists the AI-flagged row" do
      stub_material = build(:membership) # any AR object will do; we stub the call
      fake = StudyMaterial.create!(
        slug: "ai-generated-test",
        title: "AI Generated",
        level: "beginner",
        category: "daily",
        description: "AI 가 생성한 시나리오",
        scenario_prompt: "stay on topic",
        key_expressions: ["expr"],
        example_dialogue: [{ "role" => "assistant", "text" => "hi" }],
        ai_generated: true
      )
      allow(StudyMaterials::Generate).to receive(:call).and_return(fake)

      post "/api/v1/study_materials/generate",
           params: { topic: "negotiating salary" },
           headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["ai_generated"]).to be(true)
      expect(body["slug"]).to eq("ai-generated-test")
    end

    it "503s with a typed error when Gemini fails" do
      allow(StudyMaterials::Generate).to receive(:call)
        .and_raise(StudyMaterials::Generate::Error, "model returned non-JSON")

      post "/api/v1/study_materials/generate",
           params: { topic: "x" },
           headers: headers
      expect(response).to have_http_status(:bad_gateway)
      expect(JSON.parse(response.body)["error"]).to eq("generation_failed")
    end

    it "422s with limit info when the user has hit the per-user generation cap" do
      user.update!(study_generations_used: StudyMaterials::Generate::MAX_PER_USER)

      post "/api/v1/study_materials/generate",
           params: { topic: "another one" },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("generation_limit_reached")
      expect(body["limit"]).to eq(StudyMaterials::Generate::MAX_PER_USER)
      expect(body["used"]).to eq(StudyMaterials::Generate::MAX_PER_USER)
    end

    it "passes the current_user through so the service can enforce + increment the cap" do
      received = nil
      allow(StudyMaterials::Generate).to receive(:call) do |topic:, user:, **|
        received = user
        StudyMaterial.first
      end

      post "/api/v1/study_materials/generate",
           params: { topic: "x" },
           headers: headers
      expect(received).to eq(user)
    end

    it "422s with inappropriate_content when the topic is profane" do
      post "/api/v1/study_materials/generate",
           params: { topic: "씨발 영어 알려줘" },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("inappropriate_content")
    end
  end
end

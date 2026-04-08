require "rails_helper"

RSpec.describe "Admin memberships", type: :request do
  let(:admin)   { create(:admin) }
  let(:learner) { create(:user) }
  let(:plan)    { create(:premium_plan) }

  describe "POST /api/v1/admin/memberships" do
    it "grants a membership without a payment" do
      expect {
        post "/api/v1/admin/memberships",
             params: { user_id: learner.id, membership_plan_id: plan.id },
             headers: { "X-User-Id" => admin.id.to_s }
      }.to change(Membership, :count).by(1).and change(Payment, :count).by(0)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["source"]).to eq("admin_grant")
    end

    it "honors a custom duration_days override" do
      post "/api/v1/admin/memberships",
           params: { user_id: learner.id, membership_plan_id: plan.id, duration_days: 7 },
           headers: { "X-User-Id" => admin.id.to_s }

      m = Membership.last
      expect((m.expires_at - m.started_at).to_i).to be_within(5).of(7.days.to_i)
    end

    it "403s for non-admin callers" do
      post "/api/v1/admin/memberships",
           params: { user_id: learner.id, membership_plan_id: plan.id },
           headers: { "X-User-Id" => learner.id.to_s }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/admin/memberships/:id" do
    it "revokes a membership" do
      m = create(:membership, user: learner, membership_plan: plan)
      delete "/api/v1/admin/memberships/#{m.id}",
             headers: { "X-User-Id" => admin.id.to_s }
      expect(response).to have_http_status(:no_content)
      expect(m.reload.status).to eq("revoked")
    end

    it "401s with no user header" do
      m = create(:membership, user: learner, membership_plan: plan)
      delete "/api/v1/admin/memberships/#{m.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/admin/memberships (destroy_all)" do
    it "hard-deletes every membership row" do
      create(:membership, user: learner, membership_plan: plan)
      create(:membership, user: create(:user), membership_plan: plan)

      expect {
        delete "/api/v1/admin/memberships",
               headers: { "X-User-Id" => admin.id.to_s }
      }.to change(Membership, :count).from(2).to(0)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["deleted"]).to eq(2)
    end

    it "403s for non-admin callers" do
      delete "/api/v1/admin/memberships",
             headers: { "X-User-Id" => learner.id.to_s }
      expect(response).to have_http_status(:forbidden)
    end
  end
end

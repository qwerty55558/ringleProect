Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get  "me",               to: "me#show"
      # SSE channel that pushes the same /me payload whenever it changes,
      # so the conversation page can react to expiry without polling.
      get  "me/stream",        to: "me_stream#show"
      get  "membership_plans", to: "membership_plans#index"

      resources :memberships, only: [:index]
      resources :payments,    only: [:create] do
        collection { get :test_cards }
      end

      # Conversation persistence — see ConversationsController for the
      # rationale (replay across reloads, explicit deletion, etc.).
      delete "conversations/all", to: "conversations#destroy_all"
      resources :conversations, only: %i[index create show destroy] do
        resources :messages, only: %i[create], controller: "messages" do
          member { get :audio }
        end
      end

      # Cached AI curriculum (study tab). The Generate endpoint extends
      # the cache by calling Gemini once and persisting the result.
      # The /stream endpoint pushes `event: changed` whenever the
      # curriculum table mutates (generate or admin reset).
      resources :study_materials, only: %i[index show] do
        collection do
          post :generate
          get  :stream, to: "study_materials_stream#show"
        end
      end

      namespace :admin do
        resources :users, only: [:index]
        delete "memberships", to: "memberships#destroy_all"
        resources :memberships, only: [:create, :destroy]
        # Global SSE — every admin tab gets notified when ANY user's
        # membership state changes (purchase, grant, revoke, expiry).
        get "memberships/stream", to: "membership_stream#show"
        delete "conversations", to: "conversations#destroy_all"
        delete "analyses", to: "analyses#destroy_all"

        # Admin-only nuke-and-reseed for the study curriculum (DevPanel
        # button). Wipes AI rows, resets per-user generation counters,
        # re-runs CurriculumSeed, and broadcasts via Study::Bus.
        post "study_materials/reset", to: "study_materials#reset"
        # Targeted delete — wipes ONLY AI-generated curriculum rows.
        # Doesn't touch seeded rows or per-user counters.
        delete "study_materials/ai_generated", to: "study_materials#destroy_ai_generated"
        # Reset every user's AI generation counter (used + offenses).
        post "study_materials/reset_generation_counters", to: "study_materials#reset_generation_counters"
      end

      get "analysis/stream", to: "analysis_stream#show"

      namespace :ai do
        post "messages",       to: "messages#create"
        post "transcriptions", to: "transcriptions#create"
        post "speech",         to: "speech#create"
        post "translations",   to: "translations#create"
        get  "analysis",       to: "analysis#show"
        post "analysis",       to: "analysis#create"
      end

      # STT demo fixtures (office-mode replacement for the microphone).
      resources :stt_fixtures, only: %i[index], param: :slug do
        member { get :audio }
      end
    end
  end
end

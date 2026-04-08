Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get  "me",               to: "me#show"
      get  "membership_plans", to: "membership_plans#index"

      resources :memberships, only: [:index]
      resources :payments,    only: [:create]

      namespace :admin do
        resources :users, only: [:index]
        delete "memberships", to: "memberships#destroy_all"
        resources :memberships, only: [:create, :destroy]
      end

      namespace :ai do
        post "messages",       to: "messages#create"
        post "transcriptions", to: "transcriptions#create"
        post "speech",         to: "speech#create"
      end
    end
  end
end

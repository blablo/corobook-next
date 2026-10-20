Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"

  get  "login"  => "sessions#new",     as: :login
  post "login"  => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  resources :songs
  resources :text_slides do
    post "preview", on: :collection
  end

  get   "operator/:id"         => "operator#show",    as: :operator
  patch "operator/:id/advance" => "operator#advance", as: :operator_advance
  patch "operator/:id/back"    => "operator#back",    as: :operator_back
  patch "operator/:id/goto"    => "operator#goto",    as: :operator_goto
  patch "operator/:id/blank"   => "operator#blank",   as: :operator_blank
  patch "operator/:id/font"    => "operator#font",    as: :operator_font
  delete "operator/:id"        => "operator#end_session", as: :operator_end

  get   "p/:token"         => "projector#show",    as: :projector
  patch "p/:token/advance" => "projector#advance", as: :projector_advance
  patch "p/:token/back"    => "projector#back",    as: :projector_back
  get "m/:token" => "musician#show",  as: :musician

  get "reports/usage" => "reports#usage", as: :usage_report

  # Team management (admin): members + pending invitations.
  resource  :team, only: [ :show ], controller: "team"
  resources :members, only: [ :update, :destroy ]
  resources :invitations, only: [ :create, :destroy ] do
    member { post :resend }
  end

  # Public invitation accept flow — tenancy is resolved by the token, no session required.
  get  "invitations/:token/accept" => "invitation_acceptances#show",   as: :accept_invitation
  post "invitations/:token/accept" => "invitation_acceptances#create"

  resources :service_sets, path: "sets", as: :service_sets do
    member do
      post "items", to: "service_sets#add_item", as: :add_item
      patch "reorder"
      delete "items/:item_id", to: "service_sets#remove_item", as: :remove_item
      post "launch", to: "live_sessions#create", as: :launch
      get "library", to: "service_sets#library", as: :library
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end

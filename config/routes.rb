Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get  "login"  => "sessions#new",     as: :login
  post "login"  => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  resources :songs
  resources :text_slides

  get   "operator/:id"         => "operator#show",    as: :operator
  patch "operator/:id/advance" => "operator#advance", as: :operator_advance
  patch "operator/:id/back"    => "operator#back",    as: :operator_back
  patch "operator/:id/goto"    => "operator#goto",    as: :operator_goto
  patch "operator/:id/blank"   => "operator#blank",   as: :operator_blank
  patch "operator/:id/font"    => "operator#font",    as: :operator_font
  delete "operator/:id"        => "operator#end_session", as: :operator_end

  get "p/:token" => "projector#show", as: :projector
  get "m/:token" => "musician#show",  as: :musician

  get "reports/usage" => "reports#usage", as: :usage_report

  resources :service_sets, path: "sets", as: :service_sets do
    member do
      post "items", to: "service_sets#add_item", as: :add_item
      patch "reorder"
      delete "items/:item_id", to: "service_sets#remove_item", as: :remove_item
      post "launch", to: "live_sessions#create", as: :launch
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end

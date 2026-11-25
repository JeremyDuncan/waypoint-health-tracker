Rails.application.routes.draw do
  resource :session, only: [:new, :create, :destroy]
  root "dashboard#index"
  get "calendar", to: "calendars#show", as: :calendar
  resources :injections, only: :index
  resource :chart_preferences, only: [:update, :destroy], path: "charts/:page/preferences"
  resource :review, only: :show
  resource :goal, only: [:show, :update, :destroy]
  resource :report, only: :show
  get "up", to: "health#show"
  get "manifest", to: "rails/pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service-worker", to: "rails/pwa#service_worker", as: :pwa_service_worker
  resources :entries, only: [:new, :create, :edit, :update, :destroy]
  get "journal/:date", to: "journal#show", as: :journal
  put "journal/:date", to: "journal#update"
  delete "journal/:date", to: "journal#destroy"
  resource :settings, only: [:show, :update]
  patch "settings/password", to: "settings#change_password", as: :settings_password
  delete "settings/history", to: "settings#clear_history", as: :settings_history
  get "settings/export/:kind", to: "settings#export", as: :export
  resources :imports, only: [:create, :show] do
    post :preview, on: :member
    post :commit, on: :member
  end
end

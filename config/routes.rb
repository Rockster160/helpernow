Rails.application.routes.draw do
  root to: 'index#index'

  get :form_redirect, controller: :application
  get :flash_message, controller: :application
  get :"terms-of-service", controller: :static_pages
  get :"privacy-policy", controller: :static_pages
  get :faq, controller: :static_pages
  get :donate, controller: :static_pages
  post :donate, controller: :static_pages, action: :one_time_donation
  get :emoji, controller: :static_pages
  get :chat, controller: :chat
  get :chat_list, controller: :chat
  get "chat/remove_message/:id" => "chat#remove_message", as: :remove_message
  get "chat/revoke_access/:id" => "chat#revoke_access", as: :revoke_access

  resource :feedback, path: "feedback", only: [:show, :create] do
    get ":id/edit", action: :edit, as: :edit
    post ":id/complete", action: :complete, as: :complete
    get :all, action: :index
    post :all, action: :redirect_all
  end

  devise_for :users, path: :account, path_names: { sign_in: "login", sign_out: "logout" }, controllers: {
    confirmations: "devise/user/confirmations",
    # omniauth_callbacks: "devise/user/omniauth_callbacks",
    passwords: "devise/user/passwords",
    registrations: "devise/user/registrations",
    sessions: "devise/user/sessions",
    unlocks: "devise/user/unlocks"
  }

  get "tags/:tags" => "tags#show", as: :tag
  resources :tags, only: [ :index ] do
    post :redirect, on: :collection
  end

  post "history" => "posts#history_redirect", as: :history_redirect
  get "history(((((/:claimed_status)/:reply_count)/:user_status)/:tags)/:page)" => "posts#history", as: :history

  get "url" => "replies#meta", as: :get_meta
  get "preview" => "replies#preview"
  get "posts/:id.csv" => "posts#show", format: :csv
  resources :posts, except: [ :destroy ] do
    member do
      get :vote
      get :subscribe
      post :mod
    end
    resources :replies, only: [ :create, :update ] do
      post :mod
      get :favorite
      get :unfavorite
    end
  end

  resources :replies, only: [ :index ] do
  end

  resource :mod, only: [:show] do
    get :queue, on: :member

    resource :bans, only: [:show] do
      resources :banned_users, path: :users
      resources :banned_ips, path: :ip
      resources :chat_bans, path: :chat
    end
    resources :audit, only: [ :index, :show ] do
      post :search, on: :collection
    end
  end

  resource :admin, only: [] do
    resources :email_blobs, path: :emails do
      post :search, on: :collection
    end
  end

  resource :account, only: [ :index, :edit, :update ] do
    get :confirm
    patch :confirm, action: :set_confirmation
    get :avatar
    post :avatar, action: :update_avatar
    get :notifications

    resources :subscriptions, only: [ :index ] do
      collection do
        post :subscribe
        delete :subscribe, action: :unsubscribe
      end
    end
    resources :friends, only: [ :index, :update, :destroy ]
    resources :profile, only: [ :index ] do
      post :update, on: :collection
    end
    resources :settings, only: [ :index ] do
      post :update, on: :collection
    end
    resources :notices, only: [ :index ] do
      post :mark_all_read, on: :collection
    end
    resources :invites, only: [ :index ] do
      post :mark_all_read, on: :collection
    end
  end

  post "update_user_search" => "users#update_user_search", as: :update_user_search
  resources :users, except: [ :destroy ] do
    member do
      put :add_friend
      put :remove_friend
      post :moderate
      get :spy
    end
    get "shoutbox" => "shouts#index", as: :shouts
    post "shoutbox" => "shouts#create"
    get "shout-trail/:other_user_id" => "shouts#shouttrail", as: :shouttrail
    resources :posts, only: [ :index ]
    resources :replies, only: [ :index ]
  end
  resources :shouts, only: [:show, :update, :destroy]

  resources :webhooks, only: [] do
    collection do
      post :email
    end
  end

  require 'sidekiq/web'
  authenticate :user, ->(u) { u.admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end
  mount ActionCable.server => '/cable'

end

defmodule SonaCommsWeb.Router do
  use SonaCommsWeb, :router

  import SonaCommsWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SonaCommsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Enable LiveDashboard, Swoosh mailbox preview and the user switcher in
  # development (and test). Never compiled into prod.
  if Application.compile_env(:sona_comms, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SonaCommsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      # the switcher is the dev login mechanism, so it can't require auth (ADR 0007)
      get "/switch-user", SonaCommsWeb.DevSessionController, :index
      post "/switch-user/:user_id", SonaCommsWeb.DevSessionController, :create
    end
  end

  ## Authentication routes

  scope "/", SonaCommsWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{SonaCommsWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # member-gated: on_mount {SonaCommsWeb.OrgAuth, :require_member} inside the module
      live "/", ChatLive, :index
      live "/c/:id", ChatLive, :show
      live "/c/:id/announce", ChatLive, :announce
      live "/c/:id/announcements/:message_id", ChatLive, :receipts
      live "/announcements", ChatLive, :announcements
      live "/new/dm", ChatLive, :new_dm
      live "/new/group", ChatLive, :new_group

      # admin-gated: on_mount {SonaCommsWeb.OrgAuth, :require_admin} inside the module
      live "/org", OrgLive.Index, :index
      live "/org/venues/new", OrgLive.Index, :new_venue
      live "/org/venues/:venue_id/teams/new", OrgLive.Index, :new_team
      live "/org/members", OrgLive.Members, :index
      live "/org/members/new", OrgLive.Members, :new

      # authenticated only: where users without an active membership land
      live "/no-access", NoAccessLive, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", SonaCommsWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{SonaCommsWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end

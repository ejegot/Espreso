defmodule EspresoWeb.Router do
  use EspresoWeb, :router

  import EspresoWeb.StaffAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EspresoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EspresoWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/menu", MenuLive
    live "/order/:number", OrderLive
    live "/about", AboutLive
    live "/contact", ContactLive
  end

  scope "/", EspresoWeb do
    pipe_through [:browser, :redirect_if_staff_is_authenticated]

    live_session :redirect_if_authenticated,
      on_mount: [{EspresoWeb.StaffAuth, :redirect_if_authenticated}] do
      live "/login", StaffLoginLive, :new
      live "/register", StaffRegisterLive, :new
    end
  end

  scope "/", EspresoWeb do
    pipe_through :browser

    post "/session", UserSessionController, :create
    delete "/logout", UserSessionController, :delete
  end

  scope "/", EspresoWeb do
    pipe_through [:browser, :require_authenticated_staff]

    live_session :dashboard,
      on_mount: [{EspresoWeb.StaffAuth, {:ensure_permission, :dashboard}}] do
      live "/dashboard", DashboardLive
    end

    live_session :staff,
      on_mount: [{EspresoWeb.StaffAuth, :ensure_staff}] do
      live "/staff", StaffHomeLive
      live "/orders", StaffOrdersLive
      live "/pos", StaffPosLive
    end
  end

  scope "/", EspresoWeb do
    pipe_through [:browser, :require_authenticated_staff, :require_owner]

    live_session :owner,
      on_mount: [{EspresoWeb.StaffAuth, :ensure_owner}] do
      live "/admin/users", AdminUsersLive
    end
  end

  scope "/", EspresoWeb do
    pipe_through [:browser, :require_authenticated_staff]

    live_session :business_settings,
      on_mount: [{EspresoWeb.StaffAuth, {:ensure_permission, :business_settings}}] do
      live "/admin/settings", AdminSettingsLive
    end

    live_session :product_availability,
      on_mount: [{EspresoWeb.StaffAuth, {:ensure_permission, :product_availability}}] do
      live "/admin/availability", AdminAvailabilityLive
    end
  end

  if Application.compile_env(:espreso, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EspresoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

defmodule EspresoWeb.StaffLoginLive do
  use EspresoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Staff login")
     |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user)), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-login-page">
      <main class="staff-login-main">
        <section class="staff-auth-card">
          <p class="staff-orders-brand">CoffeeSpot</p>
          <h1 class="staff-orders-title">Staff login</h1>
          <p class="staff-auth-lede">Baristas, managers, and owners — sign in to continue.</p>

          <.form for={@form} action={~p"/session"} method="post" class="staff-auth-form" id="staff-login-form">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

            <div>
              <label class="menu-checkout-label" for="staff-email">Email</label>
              <input
                id="staff-email"
                type="email"
                name="user[email]"
                value={@form[:email].value}
                class="menu-checkout-input"
                autocomplete="username"
                required
              />
            </div>

            <div>
              <label class="menu-checkout-label" for="staff-password">Password</label>
              <input
                id="staff-password"
                type="password"
                name="user[password]"
                class="menu-checkout-input"
                autocomplete="current-password"
                required
              />
            </div>

            <button type="submit" class="menu-basket-checkout">Log in</button>
          </.form>

          <p class="staff-login-back">
            <.link navigate={~p"/"} class="brune-visit-link">← Back to site</.link>
          </p>
        </section>
      </main>
    </div>
    """
  end
end

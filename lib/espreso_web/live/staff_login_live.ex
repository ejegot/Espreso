defmodule EspresoWeb.StaffLoginLive do
  use EspresoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Welcome back")
     |> assign(:show_password?, false)
     |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user)), layout: false}
  end

  @impl true
  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, :show_password?, !socket.assigns.show_password?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="staff-auth-page">
      <aside class="staff-auth-visual" aria-hidden="true">
        <img src={~p"/images/coffeespot/cold-signature-01.jpg"} alt="" class="staff-auth-visual-img" />
        <div class="staff-auth-visual-shade"></div>
        <figure class="staff-auth-quote">
          <blockquote>
            “Not just great coffee, but a great experience.”
          </blockquote>
          <figcaption>CoffeeSpot · Lilac Marikina</figcaption>
        </figure>
      </aside>

      <main class="staff-auth-panel">
        <div class="staff-auth-panel-inner">
          <header class="staff-auth-brand">
            <span class="staff-auth-mark" aria-hidden="true">☕</span>
            <p class="staff-auth-brand-name">coffeespot</p>
          </header>

          <h1 class="staff-auth-title">Hello, welcome back!</h1>
          <p class="staff-auth-subtitle">Start your day with the perfect brew.</p>

          <p :if={msg = Phoenix.Flash.get(@flash, :error)} class="staff-auth-error" role="alert">
            {msg}
          </p>
          <p :if={msg = Phoenix.Flash.get(@flash, :info)} class="staff-auth-info" role="status">
            {msg}
          </p>

          <.form
            for={@form}
            action={~p"/session"}
            method="post"
            class="staff-auth-form-v2"
            id="staff-login-form"
          >
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

            <label class="staff-auth-field">
              <span>Email</span>
              <input
                id="staff-email"
                type="email"
                name="user[email]"
                value={@form[:email].value}
                placeholder="you@coffeespot.local"
                autocomplete="username"
                required
              />
            </label>

            <label class="staff-auth-field">
              <span>Password</span>
              <div class="staff-auth-password-wrap">
                <input
                  id="staff-password"
                  type={if @show_password?, do: "text", else: "password"}
                  name="user[password]"
                  placeholder="Password"
                  autocomplete="current-password"
                  required
                />
                <button
                  type="button"
                  class="staff-auth-eye"
                  phx-click="toggle_password"
                  aria-label={if @show_password?, do: "Hide password", else: "Show password"}
                >
                  {if @show_password?, do: "Hide", else: "Show"}
                </button>
              </div>
            </label>

            <div class="staff-auth-row">
              <label class="staff-auth-check">
                <input type="checkbox" name="user[remember_me]" value="true" />
                <span>Remember me</span>
              </label>
              <span class="staff-auth-muted-link">Forgot password? Ask the owner</span>
            </div>

            <button type="submit" class="staff-auth-submit">Let's brew!</button>
          </.form>

          <p class="staff-auth-switch">
            Don’t have an account? <.link navigate={~p"/register"}>Sign Up</.link>
          </p>

          <p class="staff-auth-site-link">
            <.link navigate={~p"/"}>← Back to CoffeeSpot</.link>
          </p>
        </div>
      </main>
    </div>
    """
  end
end

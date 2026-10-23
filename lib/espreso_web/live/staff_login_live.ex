defmodule EspresoWeb.StaffLoginLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts
  alias Espreso.Tenancy

  @pin_max 6
  @pin_display 6

  @impl true
  def mount(%{"tenant_slug" => slug}, _session, socket) do
    case Tenancy.put_guest_tenant(slug) do
      {:ok, tenant} ->
        mount_login(socket, tenant)

      {:error, :not_found} ->
        {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  def mount(_params, _session, socket) do
    Tenancy.put_lilac_context()
    mount_login(socket, nil)
  end

  defp mount_login(socket, tenant) do
    pin_login_available? = Accounts.any_staff_pin_configured?()

    if is_nil(tenant) and not pin_login_available? and Accounts.needs_initial_owner_setup?() do
      {:ok, push_navigate(socket, to: ~p"/setup")}
    else
      {:ok,
       socket
       |> assign(:page_title, login_page_title(tenant))
       |> assign(:login_mode, :pin)
       |> assign(:pin_login_available?, pin_login_available?)
       |> assign(:pin_max, @pin_max)
       |> assign(:pin_display, @pin_display)
       |> assign(:show_password?, false)
       |> assign(:tenant_slug, tenant && tenant.slug)
       |> assign(:tenant_name, tenant && tenant.guest_brand_name)
       |> assign(:notice, Phoenix.Flash.get(socket.assigns.flash, :info))
       |> assign(:alert, Phoenix.Flash.get(socket.assigns.flash, :error))
       |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user)), layout: false}
    end
  end

  @impl true
  def handle_event("show_pin_login", _params, socket) do
    {:noreply, assign(socket, :login_mode, :pin)}
  end

  def handle_event("show_email_login", _params, socket) do
    {:noreply, assign(socket, :login_mode, :email)}
  end

  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, :show_password?, !socket.assigns.show_password?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={[
      "staff-auth-page staff-auth-page--approved staff-auth-page--float staff-auth-page--lock",
      @login_mode == :pin && "staff-auth-page--pin",
      @login_mode == :email && "staff-auth-page--recovery"
    ]}>
      <div class="staff-auth-stage">
        <div class="staff-auth-backdrop" aria-hidden="true">
          <picture class="staff-auth-backdrop-picture">
            <source srcset={~p"/images/elilai-kafe/login-kalachuchi.webp"} type="image/webp" />
            <img
              src={~p"/images/elilai-kafe/login-kalachuchi.jpg"}
              alt=""
              class="staff-auth-backdrop-img"
              width="1024"
              height="640"
              decoding="async"
              fetchpriority="high"
            />
          </picture>
        </div>

        <main class="staff-auth-panel">
          <div class="staff-auth-panel-inner staff-auth-panel-inner--login">
            <header class="staff-auth-brand">
              <picture class="staff-auth-logo-picture">
                <source
                  srcset={~p"/images/elilai-kafe/elilai-kafe-mark-login.webp"}
                  type="image/webp"
                />
                <img
                  src={~p"/images/elilai-kafe/elilai-kafe-mark-login.png"}
                  alt=""
                  class="staff-auth-logo staff-auth-logo--mark"
                  width="512"
                  height="512"
                  decoding="async"
                  fetchpriority="low"
                />
              </picture>
              <p class="staff-auth-wordmark">ELILAI KAFE</p>
            </header>

            <h1 class={["staff-auth-title", @login_mode == :pin && "sr-only"]}>
              {login_title(@login_mode)}
            </h1>
            <p class="staff-auth-subtitle">
              {cond do
                @login_mode == :email -> login_subtitle(:email)
                is_binary(@tenant_name) and @tenant_name != "" -> "#{@tenant_name} · Elilai"
                true -> "CoffeeSpot · Elilai"
              end}
            </p>

            <p :if={@alert} class="staff-auth-error" role="alert">
              {@alert}
            </p>
            <p :if={@notice} class="staff-auth-info" id="staff-auth-notice" role="status">
              {@notice}
            </p>

            <div :if={@login_mode == :pin} id="staff-pin-login" class="staff-pin-login">
              <p :if={!@pin_login_available?} class="staff-pin-empty" id="staff-pin-roster-empty">
                No PINs configured. Ask an owner to set staff PINs.
              </p>

              <div :if={@pin_login_available?} class="staff-pin-shell">
                <form
                  action={~p"/session/pin"}
                  method="post"
                  class="staff-pin-form"
                  id="staff-pin-form"
                >
                  <input
                    type="hidden"
                    name="_csrf_token"
                    value={Plug.CSRFProtection.get_csrf_token()}
                  />
                  <input :if={@tenant_slug} type="hidden" name="tenant_slug" value={@tenant_slug} />
                  <p class="sr-only" id="staff-pin-enter-hint">Enter your PIN to sign in.</p>

                  <div
                    id="staff-pin-local"
                    class="staff-pin-local"
                    phx-hook="StaffPinPad"
                    phx-update="ignore"
                    data-pin-max={@pin_max}
                    data-pin-display={@pin_display}
                    data-pin-ready="true"
                  >
                    <input type="hidden" name="pin" value="" data-pin-input autocomplete="off" />

                    <div
                      class="staff-pin-display"
                      aria-live="polite"
                      aria-label="PIN entry"
                      data-pin-display
                    >
                    </div>

                    <div class="staff-pin-pad" aria-label="PIN keypad" data-pin-pad>
                      <button
                        :for={digit <- ~w(1 2 3 4 5 6 7 8 9)}
                        type="button"
                        class="staff-pin-key"
                        data-pin-key={digit}
                        aria-label={"Digit #{digit}"}
                      >
                        {digit}
                      </button>
                      <button
                        type="button"
                        class="staff-pin-key staff-pin-key--icon"
                        data-pin-action="backspace"
                        aria-label="Backspace"
                      >
                        ⌫
                      </button>
                      <button
                        type="button"
                        class="staff-pin-key"
                        data-pin-key="0"
                        aria-label="Digit 0"
                      >
                        0
                      </button>
                      <button
                        type="button"
                        class="staff-pin-key staff-pin-key--muted"
                        data-pin-action="clear"
                        aria-label="Clear PIN"
                      >
                        Clear
                      </button>
                    </div>
                  </div>

                  <div class="staff-auth-actions">
                    <button
                      type="submit"
                      class="staff-auth-submit staff-auth-submit--shift"
                      id="staff-pin-submit"
                      data-pin-submit
                      disabled
                    >
                      Sign in
                    </button>
                  </div>
                </form>
              </div>

              <div class="staff-auth-actions staff-auth-actions--footer">
                <button
                  type="button"
                  class="staff-auth-mode-link staff-auth-mode-link--recovery"
                  id="staff-auth-account-recovery"
                  phx-click="show_email_login"
                >
                  <span class="staff-auth-mode-link-label">
                    <span class="staff-auth-mode-link-icon" aria-hidden="true">
                      <svg
                        viewBox="0 0 24 24"
                        width="15"
                        height="15"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="1.7"
                      >
                        <rect x="3.5" y="6.5" width="17" height="11" rx="1.5" />
                        <path
                          d="m4.5 8 7.5 5.5L19.5 8"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        />
                      </svg>
                    </span>
                    Account recovery
                  </span>
                </button>
              </div>
            </div>

            <.form
              :if={@login_mode == :email}
              for={@form}
              action={~p"/session"}
              method="post"
              class="staff-auth-form-v2 staff-auth-form-v2--recovery"
              id="staff-login-form"
            >
              <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
              <input :if={@tenant_slug} type="hidden" name="tenant_slug" value={@tenant_slug} />

              <label class="staff-auth-field">
                <span>Email</span>
                <input
                  id="staff-email"
                  type="email"
                  name="user[email]"
                  value={@form[:email].value}
                  placeholder="name@company.com"
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

              <button type="submit" class="staff-auth-submit">Sign in</button>

              <button
                type="button"
                class="staff-auth-mode-link"
                id="staff-auth-back-to-pin"
                phx-click="show_pin_login"
              >
                ← Back to sign in
              </button>
            </.form>
          </div>
        </main>
      </div>
    </div>
    """
  end

  defp login_page_title(nil), do: "Welcome back"
  defp login_page_title(%{guest_brand_name: name}) when is_binary(name), do: name
  defp login_page_title(_), do: "Welcome back"

  defp login_title(:pin), do: "Welcome back"
  defp login_title(:email), do: "Account recovery"

  defp login_subtitle(:pin), do: "Please login to your account"
  defp login_subtitle(:email), do: "Use email and password if you cannot sign in with a PIN."
end

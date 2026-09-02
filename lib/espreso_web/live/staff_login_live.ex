defmodule EspresoWeb.StaffLoginLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts
  alias Espreso.Accounts.User

  @pin_max 6

  @impl true
  def mount(_params, _session, socket) do
    roster = Accounts.list_staff_for_pin_login()

    {:ok,
     socket
     |> assign(:page_title, "Welcome back")
     |> assign(:login_mode, if(roster == [], do: :email, else: :pin))
     |> assign(:roster, roster)
     |> assign(:selected_staff, nil)
     |> assign(:pin, "")
     |> assign(:show_password?, false)
     |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user)), layout: false}
  end

  @impl true
  def handle_event("show_pin_login", _params, socket) do
    {:noreply,
     socket
     |> assign(:login_mode, :pin)
     |> assign(:selected_staff, nil)
     |> assign(:pin, "")}
  end

  def handle_event("show_email_login", _params, socket) do
    {:noreply,
     socket
     |> assign(:login_mode, :email)
     |> assign(:selected_staff, nil)
     |> assign(:pin, "")}
  end

  def handle_event("select_staff", %{"id" => id}, socket) do
    staff = Enum.find(socket.assigns.roster, &(to_string(&1.id) == id))

    {:noreply,
     socket
     |> assign(:selected_staff, staff)
     |> assign(:pin, "")}
  end

  def handle_event("clear_staff", _params, socket) do
    {:noreply, socket |> assign(:selected_staff, nil) |> assign(:pin, "")}
  end

  def handle_event("pin_digit", %{"digit" => digit}, socket) do
    pin = socket.assigns.pin

    if String.length(pin) < @pin_max do
      {:noreply, assign(socket, :pin, pin <> digit)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("pin_backspace", _params, socket) do
    {:noreply, assign(socket, :pin, String.slice(socket.assigns.pin, 0..-2//1))}
  end

  def handle_event("pin_clear", _params, socket) do
    {:noreply, assign(socket, :pin, "")}
  end

  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, :show_password?, !socket.assigns.show_password?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="staff-auth-page staff-auth-page--pin">
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

          <h1 class="staff-auth-title">{login_title(@login_mode, @selected_staff)}</h1>
          <p class="staff-auth-subtitle">{login_subtitle(@login_mode, @selected_staff)}</p>

          <p :if={msg = Phoenix.Flash.get(@flash, :error)} class="staff-auth-error" role="alert">
            {msg}
          </p>
          <p :if={msg = Phoenix.Flash.get(@flash, :info)} class="staff-auth-info" role="status">
            {msg}
          </p>

          <div :if={@login_mode == :pin} id="staff-pin-login" class="staff-pin-login">
            <div :if={is_nil(@selected_staff)} class="staff-pin-roster">
              <p :if={@roster == []} class="staff-pin-empty" id="staff-pin-roster-empty">
                No staff PINs configured yet. Use owner login below.
              </p>
              <div :if={@roster != []} class="staff-pin-grid" role="list" aria-label="Staff roster">
                <button
                  :for={member <- @roster}
                  type="button"
                  class="staff-pin-grid-card"
                  id={"staff-pin-user-#{member.id}"}
                  phx-click="select_staff"
                  phx-value-id={member.id}
                  role="listitem"
                >
                  <span class="staff-pin-grid-avatar" aria-hidden="true">
                    {staff_initials(member.name)}
                  </span>
                  <span class="staff-pin-grid-name">{member.name}</span>
                  <span class="staff-pin-grid-role">{User.role_label(member.role)}</span>
                </button>
              </div>
            </div>

            <div :if={@selected_staff} class="staff-pin-entry">
              <button type="button" class="staff-pin-back" phx-click="clear_staff">
                ← Choose another
              </button>

              <div class="staff-pin-selected">
                <span class="staff-pin-grid-avatar staff-pin-grid-avatar--large" aria-hidden="true">
                  {staff_initials(@selected_staff.name)}
                </span>
                <div>
                  <p class="staff-pin-selected-name">{@selected_staff.name}</p>
                  <p class="staff-pin-selected-role">{User.role_label(@selected_staff.role)}</p>
                </div>
              </div>

              <form
                action={~p"/session/pin"}
                method="post"
                class="staff-pin-form"
                id="staff-pin-form"
              >
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <input type="hidden" name="user_id" value={@selected_staff.id} />
                <input type="hidden" name="pin" value={@pin} />

                <div class="staff-pin-display" aria-live="polite">
                  <span
                    :for={index <- 1..@pin_max}
                    class={["staff-pin-dot", pin_dot_class(@pin, index)]}
                  />
                </div>

                <div class="staff-pin-pad" aria-label="PIN keypad">
                  <button
                    :for={digit <- ~w(1 2 3 4 5 6 7 8 9)}
                    type="button"
                    class="staff-pin-key"
                    phx-click="pin_digit"
                    phx-value-digit={digit}
                  >
                    {digit}
                  </button>
                  <button type="button" class="staff-pin-key staff-pin-key--muted" phx-click="pin_clear">
                    Clear
                  </button>
                  <button type="button" class="staff-pin-key" phx-click="pin_digit" phx-value-digit="0">
                    0
                  </button>
                  <button type="button" class="staff-pin-key staff-pin-key--muted" phx-click="pin_backspace">
                    ⌫
                  </button>
                </div>

                <button
                  type="submit"
                  class="staff-auth-submit"
                  disabled={String.length(@pin) < 4}
                >
                  Sign in
                </button>
              </form>
            </div>
          </div>

          <.form
            :if={@login_mode == :email}
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

          <div class="staff-auth-mode-switch">
            <button
              :if={@login_mode == :email and @roster != []}
              type="button"
              class="staff-auth-mode-link"
              phx-click="show_pin_login"
            >
              ← Staff PIN login
            </button>
            <button
              :if={@login_mode == :pin}
              type="button"
              class="staff-auth-mode-link"
              phx-click="show_email_login"
            >
              Owner / email login →
            </button>
          </div>

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

  defp login_title(:pin, nil), do: "Who’s on shift?"
  defp login_title(:pin, _staff), do: "Enter your PIN"
  defp login_title(:email, _), do: "Owner login"

  defp login_subtitle(:pin, nil), do: "Tap your name, then enter your PIN."
  defp login_subtitle(:pin, _staff), do: "4–6 digits — keep it private."
  defp login_subtitle(:email, _), do: "Email and password for owners and setup."

  defp staff_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp pin_dot_class(pin, index) when is_integer(index) do
    if String.length(pin) >= index, do: "is-filled", else: nil
  end
end

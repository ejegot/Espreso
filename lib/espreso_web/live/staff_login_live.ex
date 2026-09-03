defmodule EspresoWeb.StaffLoginLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts
  alias Espreso.Accounts.User

  @pin_max 6
  @pin_display 4

  @auth_slides [
    %{
      src: "/images/coffeespot/cold-signature-01.jpg",
      quote: "Not just great coffee, but a great experience."
    },
    %{
      src: "/images/coffeespot/cafe-atmosphere-01.jpg",
      quote: "A cozy spot for coffee, food, and good company."
    },
    %{
      src: "/images/coffeespot/visit-interior-01.jpg",
      quote: "Brewed fresh, served with care — every shift."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    roster = Accounts.list_staff_for_pin_login()

    {:ok,
     socket
     |> assign(:page_title, "Welcome back")
     |> assign(:login_mode, :pin)
     |> assign(:roster, roster)
     |> assign(:roster_query, "")
     |> assign(:roster_open, false)
     |> assign(:selected_staff, nil)
     |> assign(:pin, "")
     |> assign(:pin_max, @pin_max)
     |> assign(:pin_display, @pin_display)
     |> assign(:auth_slides, @auth_slides)
     |> assign(:show_password?, false)
     |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user)), layout: false}
  end

  @impl true
  def handle_event("show_pin_login", _params, socket) do
    {:noreply,
     socket
     |> assign(:login_mode, :pin)
     |> assign(:selected_staff, nil)
     |> assign(:pin, "")
     |> assign(:roster_query, "")
     |> assign(:roster_open, false)}
  end

  def handle_event("show_email_login", _params, socket) do
    {:noreply,
     socket
     |> assign(:login_mode, :email)
     |> assign(:selected_staff, nil)
     |> assign(:pin, "")
     |> assign(:roster_query, "")
     |> assign(:roster_open, false)}
  end

  def handle_event("open_roster", _params, socket) do
    {:noreply, assign(socket, :roster_open, true)}
  end

  def handle_event("close_roster", _params, socket) do
    {:noreply, assign(socket, :roster_open, false)}
  end

  def handle_event("search_staff", %{"q" => query}, socket) do
    selected =
      if socket.assigns.selected_staff &&
           String.trim(query) != socket.assigns.selected_staff.name do
        nil
      else
        socket.assigns.selected_staff
      end

    {:noreply,
     socket
     |> assign(:roster_query, query)
     |> assign(:roster_open, true)
     |> assign(:selected_staff, selected)
     |> assign(:pin, if(selected, do: socket.assigns.pin, else: ""))}
  end

  def handle_event("select_staff", %{"id" => id}, socket) do
    staff = Enum.find(socket.assigns.roster, &(to_string(&1.id) == id))

    {:noreply,
     socket
     |> assign(:selected_staff, staff)
     |> assign(:roster_query, staff.name)
     |> assign(:roster_open, false)
     |> assign(:pin, "")}
  end

  def handle_event("pin_digit", %{"digit" => digit}, socket) do
    if is_nil(socket.assigns.selected_staff) do
      {:noreply, socket}
    else
      pin = socket.assigns.pin

      if String.length(pin) < @pin_max do
        {:noreply, assign(socket, :pin, pin <> digit)}
      else
        {:noreply, socket}
      end
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
    filtered_roster = filter_roster(assigns.roster, assigns.roster_query)

    assigns =
      assigns
      |> assign(:filtered_roster, filtered_roster)
      |> assign(:pin_ready?, not is_nil(assigns.selected_staff))

    ~H"""
    <div class={["staff-auth-page", @login_mode == :pin && "staff-auth-page--pin"]}>
      <aside class="staff-auth-visual" aria-hidden="true">
        <div class="staff-auth-carousel" id="staff-auth-carousel" phx-hook="StaffAuthCarousel">
          <div
            :for={{slide, index} <- Enum.with_index(@auth_slides)}
            class={["staff-auth-slide", index == 0 && "is-active"]}
            data-auth-slide
          >
            <img src={slide.src} alt="" class="staff-auth-visual-img" />
            <div class="staff-auth-visual-shade"></div>
            <figure class="staff-auth-quote">
              <blockquote>“{slide.quote}”</blockquote>
              <figcaption>CoffeeSpot · Lilac Marikina</figcaption>
            </figure>
          </div>
        </div>
      </aside>

      <main class="staff-auth-panel">
        <div class={[
          "staff-auth-panel-inner staff-auth-panel-inner--login",
          @login_mode == :email && "staff-auth-panel-inner--owner"
        ]}>
          <header class="staff-auth-brand">
            <span class="staff-auth-mark" aria-hidden="true">☕</span>
            <p class="staff-auth-brand-name">coffeespot</p>
          </header>

          <h1 class="staff-auth-title">{login_title(@login_mode)}</h1>
          <p class="staff-auth-subtitle">{login_subtitle(@login_mode)}</p>

          <p :if={msg = Phoenix.Flash.get(@flash, :error)} class="staff-auth-error" role="alert">
            {msg}
          </p>
          <p :if={msg = Phoenix.Flash.get(@flash, :info)} class="staff-auth-info" role="status">
            {msg}
          </p>

          <div :if={@login_mode == :pin} id="staff-pin-login" class="staff-pin-login">
            <p :if={@roster == []} class="staff-pin-empty" id="staff-pin-roster-empty">
              No staff PINs configured yet. Use owner login below.
            </p>

            <div :if={@roster != []} class="staff-pin-shell">
              <div class="staff-pin-picker" phx-click-away="close_roster">
                <label class="staff-pin-search" for="staff-roster-search">
                  <span class="staff-pin-search-icon" aria-hidden="true">⌕</span>
                  <input
                    id="staff-roster-search"
                    type="search"
                    name="q"
                    value={@roster_query}
                    placeholder="Choose your name…"
                    phx-focus="open_roster"
                    phx-change="search_staff"
                    phx-debounce="100"
                    autocomplete="off"
                    autocorrect="off"
                    spellcheck="false"
                    aria-expanded={to_string(@roster_open)}
                    aria-controls="staff-roster-dropdown"
                    aria-autocomplete="list"
                    role="combobox"
                  />
                  <span class="staff-pin-search-chevron" aria-hidden="true">▾</span>
                </label>

                <div
                  :if={@roster_open}
                  class="staff-pin-dropdown"
                  id="staff-roster-dropdown"
                  role="listbox"
                  aria-label="Staff on shift"
                >
                  <p :if={@filtered_roster == []} class="staff-pin-dropdown-empty">
                    No match for “{@roster_query}”.
                  </p>
                  <button
                    :for={member <- @filtered_roster}
                    type="button"
                    class={[
                      "staff-pin-dropdown-option",
                      @selected_staff && @selected_staff.id == member.id && "is-selected"
                    ]}
                    id={"staff-pin-user-#{member.id}"}
                    phx-click="select_staff"
                    phx-value-id={member.id}
                    role="option"
                    aria-selected={to_string(@selected_staff && @selected_staff.id == member.id)}
                  >
                    <span class="staff-pin-grid-avatar" aria-hidden="true">
                      {staff_initials(member.name)}
                    </span>
                    <span class="staff-pin-dropdown-copy">
                      <span class="staff-pin-dropdown-name">{member.name}</span>
                      <span class="staff-pin-dropdown-role">{User.role_label(member.role)}</span>
                    </span>
                  </button>
                </div>

                <p :if={@selected_staff} class="staff-pin-selected-meta">
                  Signed in as <strong>{@selected_staff.name}</strong>
                  · {User.role_label(@selected_staff.role)}
                </p>
              </div>

              <form
                action={~p"/session/pin"}
                method="post"
                class={["staff-pin-form", !@pin_ready? && "staff-pin-form--locked"]}
                id="staff-pin-form"
              >
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <input
                  :if={@selected_staff}
                  type="hidden"
                  name="user_id"
                  value={@selected_staff.id}
                />
                <input type="hidden" name="pin" value={@pin} />

                <p :if={!@pin_ready?} class="staff-pin-hint" id="staff-pin-select-hint">
                  Pick your name above, then enter your PIN.
                </p>

                <div class="staff-pin-display" aria-live="polite" aria-label="PIN entry">
                  <span
                    :for={index <- 1..@pin_display}
                    class={[
                      "staff-pin-dot",
                      pin_dot_class(@pin, index, @pin_display)
                    ]}
                  />
                </div>

                <div class="staff-pin-pad" aria-label="PIN keypad">
                  <button
                    :for={digit <- ~w(1 2 3 4 5 6 7 8 9)}
                    type="button"
                    class="staff-pin-key"
                    phx-click="pin_digit"
                    phx-value-digit={digit}
                    disabled={!@pin_ready?}
                  >
                    {digit}
                  </button>
                  <button
                    type="button"
                    class="staff-pin-key staff-pin-key--muted"
                    phx-click="pin_clear"
                    disabled={!@pin_ready?}
                  >
                    Clear
                  </button>
                  <button
                    type="button"
                    class="staff-pin-key"
                    phx-click="pin_digit"
                    phx-value-digit="0"
                    disabled={!@pin_ready?}
                  >
                    0
                  </button>
                  <button
                    type="button"
                    class="staff-pin-key staff-pin-key--icon"
                    phx-click="pin_backspace"
                    disabled={!@pin_ready?}
                    aria-label="Backspace"
                  >
                    ⌫
                  </button>
                </div>

                <button
                  type="submit"
                  class="staff-auth-submit staff-auth-submit--shift"
                  disabled={!@pin_ready? or String.length(@pin) < 4}
                >
                  Start Shift
                </button>
              </form>
            </div>
          </div>

          <.form
            :if={@login_mode == :email}
            for={@form}
            action={~p"/session"}
            method="post"
            class="staff-auth-form-v2 staff-auth-form-v2--owner"
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

            <button type="submit" class="staff-auth-submit">Sign in</button>
          </.form>

          <div class="staff-auth-mode-switch">
            <button
              :if={@login_mode == :email}
              type="button"
              class="staff-auth-mode-link"
              phx-click="show_pin_login"
            >
              ← Staff shift login
            </button>
            <button
              :if={@login_mode == :pin}
              type="button"
              class="staff-auth-mode-link"
              phx-click="show_email_login"
            >
              Owner / manager email login →
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

  defp login_title(:pin), do: "Employee login"
  defp login_title(:email), do: "Owner login"

  defp login_subtitle(:pin), do: "Choose your account to start your shift."
  defp login_subtitle(:email), do: "Email and password for owners and managers."

  defp filter_roster(roster, query) when is_binary(query) do
    needle =
      query
      |> String.trim()
      |> String.downcase()

    if needle == "" do
      roster
    else
      Enum.filter(roster, fn member ->
        String.contains?(String.downcase(member.name), needle) or
          String.contains?(String.downcase(User.role_label(member.role)), needle)
      end)
    end
  end

  defp staff_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp pin_dot_class(pin, index, display) when is_integer(index) and is_integer(display) do
    filled =
      if String.length(pin) >= display do
        index <= display
      else
        String.length(pin) >= index
      end

    if filled, do: "is-filled", else: nil
  end
end

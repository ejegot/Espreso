defmodule EspresoWeb.StaffLoginLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts

  @pin_max 6
  @pin_display 4

  @impl true
  def mount(_params, _session, socket) do
    # Roster first: skip empty-DB check when PIN staff already exist (one query).
    # Empty roster still needs the setup check (zero users → /setup vs no PINs → login).
    roster = Accounts.list_staff_for_pin_login()

    if roster == [] and Accounts.needs_initial_owner_setup?() do
      {:ok, push_navigate(socket, to: ~p"/setup")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Welcome back")
       |> assign(:login_mode, :pin)
       |> assign(:roster, roster)
       |> assign(:roster_query, "")
       |> assign(:roster_open, false)
       |> assign(:selected_staff, nil)
       |> assign(:pin_max, @pin_max)
       |> assign(:pin_display, @pin_display)
       |> assign(:show_password?, false)
       |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user)), layout: false}
    end
  end

  @impl true
  def handle_event("show_pin_login", _params, socket) do
    {:noreply,
     socket
     |> assign(:login_mode, :pin)
     |> assign(:selected_staff, nil)
     |> assign(:roster_query, "")
     |> assign(:roster_open, false)}
  end

  def handle_event("show_email_login", _params, socket) do
    {:noreply,
     socket
     |> assign(:login_mode, :email)
     |> assign(:selected_staff, nil)
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
     |> assign(:selected_staff, selected)}
  end

  def handle_event("select_staff", %{"id" => id}, socket) do
    staff = Enum.find(socket.assigns.roster, &(to_string(&1.id) == id))

    {:noreply,
     socket
     |> assign(:selected_staff, staff)
     |> assign(:roster_query, staff.name)
     |> assign(:roster_open, false)}
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
      |> assign(
        :selected_staff_id,
        if(assigns.selected_staff, do: to_string(assigns.selected_staff.id), else: "")
      )

    ~H"""
    <div class={[
      "staff-auth-page staff-auth-page--approved",
      @login_mode == :pin && "staff-auth-page--pin",
      @login_mode == :email && "staff-auth-page--recovery"
    ]}>
      <div class="staff-auth-stage">
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
                No PINs configured. Ask an owner to set staff PINs.
              </p>

              <div :if={@roster != []} class="staff-pin-shell">
                <div class="staff-pin-picker" phx-click-away="close_roster">
                  <label class="staff-pin-search" for="staff-roster-search">
                    <span class="staff-pin-search-icon" aria-hidden="true">
                      <svg
                        viewBox="0 0 24 24"
                        width="18"
                        height="18"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="1.7"
                      >
                        <circle cx="12" cy="8" r="3.25" />
                        <path
                          d="M5.5 19.25c1.6-3.1 4-4.65 6.5-4.65s4.9 1.55 6.5 4.65"
                          stroke-linecap="round"
                        />
                      </svg>
                    </span>
                    <input
                      id="staff-roster-search"
                      type="search"
                      name="q"
                      value={@roster_query}
                      placeholder="Search or select staff member"
                      phx-focus="open_roster"
                      phx-change="search_staff"
                      phx-debounce="100"
                      autocomplete="off"
                      autocorrect="off"
                      spellcheck="false"
                      inputmode="search"
                      aria-expanded={to_string(@roster_open)}
                      aria-controls="staff-roster-dropdown"
                      aria-autocomplete="list"
                      aria-label="Search or select staff member"
                      role="combobox"
                    />
                    <span class="staff-pin-search-chevron" aria-hidden="true">
                      <svg
                        viewBox="0 0 24 24"
                        width="18"
                        height="18"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2"
                      >
                        <path d="M6 9l6 6 6-6" stroke-linecap="round" stroke-linejoin="round" />
                      </svg>
                    </span>
                  </label>

                  <div
                    :if={@roster_open}
                    class="staff-pin-dropdown"
                    id="staff-roster-dropdown"
                    role="listbox"
                    aria-label="Team members"
                  >
                    <p :if={@filtered_roster == []} class="staff-pin-dropdown-empty">
                      No matching team members.
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
                      </span>
                    </button>
                  </div>

                  <p :if={@selected_staff} class="staff-pin-selected-meta" id="staff-pin-selected">
                    Selected <strong>{@selected_staff.name}</strong>
                  </p>
                </div>

                <form
                  action={~p"/session/pin"}
                  method="post"
                  class={["staff-pin-form", !@pin_ready? && "staff-pin-form--locked"]}
                  id="staff-pin-form"
                >
                  <input
                    type="hidden"
                    name="_csrf_token"
                    value={Plug.CSRFProtection.get_csrf_token()}
                  />
                  <input
                    :if={@selected_staff}
                    type="hidden"
                    name="user_id"
                    value={@selected_staff.id}
                  />

                  <p :if={!@pin_ready?} class="sr-only" id="staff-pin-select-hint">
                    Select your name first.
                  </p>
                  <p :if={@pin_ready?} class="sr-only" id="staff-pin-enter-hint">
                    Enter your PIN.
                  </p>

                  <div
                    id="staff-pin-local"
                    class="staff-pin-local"
                    phx-hook="StaffPinPad"
                    phx-update="ignore"
                    data-pin-max={@pin_max}
                    data-pin-display={@pin_display}
                    data-pin-ready={to_string(@pin_ready?)}
                    data-staff-id={@selected_staff_id}
                  >
                    <input type="hidden" name="pin" value="" data-pin-input autocomplete="off" />

                    <div
                      class="staff-pin-display"
                      aria-live="polite"
                      aria-label="PIN entry"
                      data-pin-display
                    >
                      <span
                        :for={index <- 1..@pin_display}
                        class="staff-pin-dot"
                        data-pin-dot
                        data-index={index}
                      />
                    </div>

                    <div class="staff-pin-pad" aria-label="PIN keypad" data-pin-pad>
                      <button
                        :for={digit <- ~w(1 2 3 4 5 6 7 8 9)}
                        type="button"
                        class="staff-pin-key"
                        data-pin-key={digit}
                        aria-label={"Digit #{digit}"}
                        disabled={!@pin_ready?}
                      >
                        {digit}
                      </button>
                      <button
                        type="button"
                        class="staff-pin-key staff-pin-key--icon"
                        data-pin-action="backspace"
                        aria-label="Backspace"
                        disabled={!@pin_ready?}
                      >
                        ⌫
                      </button>
                      <button
                        type="button"
                        class="staff-pin-key"
                        data-pin-key="0"
                        aria-label="Digit 0"
                        disabled={!@pin_ready?}
                      >
                        0
                      </button>
                      <button
                        type="button"
                        class="staff-pin-key staff-pin-key--muted"
                        data-pin-action="clear"
                        aria-label="Clear PIN"
                        disabled={!@pin_ready?}
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
                      disabled={!@pin_ready?}
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

        <aside class="staff-auth-visual" aria-hidden="true">
          <picture class="staff-auth-visual-picture">
            <source
              srcset={~p"/images/elilai-kafe/login-brand-panel.webp"}
              type="image/webp"
            />
            <img
              src={~p"/images/elilai-kafe/login-brand-panel.jpg"}
              alt=""
              class="staff-auth-visual-img"
              width="1084"
              height="1310"
              decoding="async"
              fetchpriority="high"
            />
          </picture>

          <svg
            class="staff-auth-wave staff-auth-wave--bottom"
            viewBox="0 0 900 56"
            preserveAspectRatio="none"
            aria-hidden="true"
            focusable="false"
          >
            <path
              class="staff-auth-wave-fill"
              d="M0 56C90 18 180 40 270 20C360 2 450 34 540 16C630 0 720 28 810 12C860 4 885 8 900 14V56H0Z"
            />
          </svg>
        </aside>
      </div>
    </div>
    """
  end

  defp login_title(:pin), do: "Welcome back"
  defp login_title(:email), do: "Account recovery"

  defp login_subtitle(:pin), do: "Please login to your account"
  defp login_subtitle(:email), do: "Use email and password if you cannot sign in with a PIN."

  defp filter_roster(roster, query) when is_binary(query) do
    needle =
      query
      |> String.trim()
      |> String.downcase()

    if needle == "" do
      roster
    else
      Enum.filter(roster, fn member ->
        String.contains?(String.downcase(member.name), needle)
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
end

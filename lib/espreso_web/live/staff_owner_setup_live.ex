defmodule EspresoWeb.StaffOwnerSetupLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts
  alias EspresoWeb.StaffAuth

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.needs_initial_owner_setup?() do
      {:ok,
       socket
       |> assign(:page_title, "Owner setup")
       |> assign(:error, nil)
       |> assign(:name, "")
       |> assign(:show_pin?, false), layout: false}
    else
      {:ok, push_navigate(socket, to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("toggle_pin", _params, socket) do
    {:noreply, assign(socket, :show_pin?, !socket.assigns.show_pin?)}
  end

  def handle_event("save", %{"setup" => params}, socket) do
    if Accounts.needs_initial_owner_setup?() do
      case Accounts.bootstrap_initial_owner(params) do
        {:ok, user} ->
          token = StaffAuth.sign_login_token(user.id)

          {:noreply,
           socket
           |> put_flash(:info, "Welcome, #{user.name}. Your owner account is ready.")
           |> redirect(to: ~p"/session/token/#{token}")}

        {:error, :pin_mismatch} ->
          {:noreply, assign(socket, :error, "PINs do not match.")}

        {:error, :invalid_pin_format} ->
          {:noreply, assign(socket, :error, "PIN must be 4–6 digits.")}

        {:error, :invalid_name} ->
          {:noreply, assign(socket, :error, "Enter a name with at least 2 characters.")}

        {:error, :registration_closed} ->
          {:noreply,
           socket
           |> put_flash(:info, "Owner setup is already complete. Please sign in.")
           |> push_navigate(to: ~p"/login")}

        {:error, %Ecto.Changeset{}} ->
          {:noreply, assign(socket, :error, "Could not create the owner account. Try again.")}

        {:error, _} ->
          {:noreply, assign(socket, :error, "Could not create the owner account. Try again.")}
      end
    else
      {:noreply, push_navigate(socket, to: ~p"/login")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="staff-auth-page">
      <aside class="staff-auth-visual" aria-hidden="true">
        <img
          src={~p"/images/coffeespot/atmosphere-interior-01.jpg"}
          alt=""
          class="staff-auth-visual-img"
        />
        <div class="staff-auth-visual-shade"></div>
        <figure class="staff-auth-quote">
          <blockquote>
            “Set up once. Run the shop with confidence.”
          </blockquote>
          <figcaption>Elilai Kafe · Owner setup</figcaption>
        </figure>
      </aside>

      <main class="staff-auth-panel">
        <div class="staff-auth-panel-inner">
          <header class="staff-auth-brand">
            <img
              src={~p"/images/elilai-kafe/elilai-kafe-mark.png"}
              alt="Elilai Kafe"
              class="staff-auth-logo staff-auth-logo--mark"
              width="1024"
              height="1024"
            />
          </header>

          <h1 class="staff-auth-title">Owner setup</h1>
          <p class="staff-auth-subtitle">
            Create the shop owner account. You’ll use this name and PIN to sign in.
          </p>

          <p :if={@error} class="staff-auth-error" id="owner-setup-error" role="alert">
            {@error}
          </p>
          <p :if={msg = Phoenix.Flash.get(@flash, :error)} class="staff-auth-error" role="alert">
            {msg}
          </p>

          <form id="owner-setup-form" phx-submit="save" class="staff-auth-form-v2">
            <label class="staff-auth-field">
              <span>Full name</span>
              <input
                type="text"
                name="setup[name]"
                id="owner-setup-name"
                value={@name}
                placeholder="Juan Dela Cruz"
                autocomplete="name"
                required
                minlength="2"
                maxlength="80"
              />
            </label>

            <label class="staff-auth-field">
              <span>PIN</span>
              <div class="staff-auth-password-wrap">
                <input
                  type={if @show_pin?, do: "text", else: "password"}
                  name="setup[pin]"
                  id="owner-setup-pin"
                  inputmode="numeric"
                  pattern="[0-9]{4,6}"
                  maxlength="6"
                  autocomplete="new-password"
                  placeholder="4–6 digits"
                  required
                />
                <button
                  type="button"
                  class="staff-auth-eye"
                  phx-click="toggle_pin"
                  aria-label={if @show_pin?, do: "Hide PIN", else: "Show PIN"}
                >
                  {if @show_pin?, do: "Hide", else: "Show"}
                </button>
              </div>
            </label>

            <label class="staff-auth-field">
              <span>Confirm PIN</span>
              <input
                type={if @show_pin?, do: "text", else: "password"}
                name="setup[pin_confirmation]"
                id="owner-setup-pin-confirmation"
                inputmode="numeric"
                pattern="[0-9]{4,6}"
                maxlength="6"
                autocomplete="new-password"
                placeholder="Re-enter PIN"
                required
              />
            </label>

            <button type="submit" class="staff-auth-submit" id="owner-setup-submit">
              Create owner account
            </button>
          </form>
        </div>
      </main>
    </div>
    """
  end
end

defmodule EspresoWeb.StaffRegisterLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts
  alias Espreso.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    first? = Accounts.first_user?()

    {:ok,
     socket
     |> assign(:page_title, "Create account")
     |> assign(:first_user?, first?)
     |> assign(:show_password?, false)
     |> assign(
       :form,
       to_form(Accounts.change_user_registration(%User{}, %{"role" => default_role(first?)}))
     ), layout: false}
  end

  @impl true
  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, :show_password?, !socket.assigns.show_password?)}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    params = maybe_force_owner_role(params, socket.assigns.first_user?)

    form =
      %User{}
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    params = maybe_force_owner_role(params, socket.assigns.first_user?)

    case Accounts.register_self(params) do
      {:ok, user} ->
        role_note =
          case user.role do
            "owner" -> "owner"
            "manager" -> "manager"
            _ -> "staff"
          end

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Account created (#{role_note}). Sign in with your email and password."
         )
         |> redirect(to: ~p"/login")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :insert)))}
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
            “Skipping the morning line is a lifesaver!”
          </blockquote>
          <figcaption>CoffeeSpot · Team</figcaption>
        </figure>
      </aside>

      <main class="staff-auth-panel">
        <div class="staff-auth-panel-inner">
          <header class="staff-auth-brand">
            <span class="staff-auth-mark" aria-hidden="true">☕</span>
            <p class="staff-auth-brand-name">coffeespot</p>
          </header>

          <h1 class="staff-auth-title">Create your account</h1>
          <p class="staff-auth-subtitle">
            <%= if @first_user? do %>
              Fill in your details below to set up the shop owner account.
            <% else %>
              Fill in your details below to join as staff or manager.
            <% end %>
          </p>

          <p :if={msg = Phoenix.Flash.get(@flash, :error)} class="staff-auth-error" role="alert">
            {msg}
          </p>
          <p :if={msg = Phoenix.Flash.get(@flash, :info)} class="staff-auth-info" role="status">
            {msg}
          </p>

          <.form
            for={@form}
            id="staff-register-form"
            phx-change="validate"
            phx-submit="save"
            class="staff-auth-form-v2"
          >
            <label class="staff-auth-field">
              <span>Full name</span>
              <input
                type="text"
                name="user[name]"
                value={@form[:name].value}
                placeholder="Juan Dela Cruz"
                autocomplete="name"
                required
              />
              <p :for={err <- @form[:name].errors} class="staff-auth-field-error">
                {format_error(err)}
              </p>
            </label>

            <label class="staff-auth-field">
              <span>Email</span>
              <input
                type="email"
                name="user[email]"
                value={@form[:email].value}
                placeholder="you@coffeespot.local"
                autocomplete="username"
                required
              />
              <p :for={err <- @form[:email].errors} class="staff-auth-field-error">
                {format_error(err)}
              </p>
            </label>

            <label class="staff-auth-field">
              <span>Password</span>
              <div class="staff-auth-password-wrap">
                <input
                  type={if @show_password?, do: "text", else: "password"}
                  name="user[password]"
                  placeholder="Enter password"
                  autocomplete="new-password"
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
              <p :for={err <- @form[:password].errors} class="staff-auth-field-error">
                {format_error(err)}
              </p>
            </label>

            <%= if @first_user? do %>
              <input type="hidden" name="user[role]" value="owner" />
            <% else %>
              <label class="staff-auth-field">
                <span>Role</span>
                <select name="user[role]" class="staff-auth-select">
                  <option value="barista" selected={@form[:role].value in [nil, "barista"]}>
                    Staff
                  </option>
                  <option value="manager" selected={@form[:role].value == "manager"}>
                    Manager
                  </option>
                </select>
              </label>
            <% end %>

            <button type="submit" class="staff-auth-submit">Create account</button>
          </.form>

          <p class="staff-auth-switch">
            Already have an account?
            <.link navigate={~p"/login"}>Sign In</.link>
          </p>

          <p class="staff-auth-site-link">
            <.link navigate={~p"/"}>← Back to CoffeeSpot</.link>
          </p>
        </div>
      </main>
    </div>
    """
  end

  defp default_role(true), do: "owner"
  defp default_role(false), do: "barista"

  defp maybe_force_owner_role(params, true), do: Map.put(params, "role", "owner")
  defp maybe_force_owner_role(params, false), do: params

  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end

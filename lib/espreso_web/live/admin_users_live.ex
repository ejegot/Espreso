defmodule EspresoWeb.AdminUsersLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts
  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Staff users")
     |> assign(:users, Accounts.list_users())
     |> assign(
       :form,
       to_form(Accounts.change_user_registration(%User{}), as: :user, id: "new_user")
     )
     |> assign(:editing, nil)
     |> assign(:edit_form, nil)
     |> assign(:flash_note, nil), layout: false}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    actor = socket.assigns.current_user

    case Accounts.create_user_as(actor, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(
           :form,
           to_form(Accounts.change_user_registration(%User{}), as: :user, id: "new_user")
         )
         |> assign(:flash_note, "Staff account created.")}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    if Authorization.can?(socket.assigns.current_user, :user_management) do
      user = Accounts.get_user!(id)

      {:noreply,
       socket
       |> assign(:editing, user)
       |> assign(
         :edit_form,
         to_form(Accounts.change_user(user), as: :user, id: "edit_user_#{user.id}")
       )}
    else
      {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing, nil) |> assign(:edit_form, nil)}
  end

  def handle_event("update", %{"user" => params}, socket) do
    actor = socket.assigns.current_user
    target = socket.assigns.editing

    case Accounts.update_user_as(actor, target, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:editing, nil)
         |> assign(:edit_form, nil)
         |> assign(:flash_note, "Staff account updated.")}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    user = Accounts.get_user!(id)

    cond do
      not Authorization.can?(actor, :user_management) ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

      user.id == actor.id ->
        {:noreply, assign(socket, :flash_note, "You can’t disable your own account.")}

      true ->
        case Accounts.update_user_as(actor, user, %{active: !user.active}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:users, Accounts.list_users())
             |> assign(
               :flash_note,
               if(user.active, do: "Account disabled.", else: "Account enabled.")
             )}

          {:error, :unauthorized} ->
            {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-admin-page">
      <header class="staff-orders-top">
        <div>
          <p class="staff-orders-brand">CoffeeSpot</p>
          <h1 class="staff-orders-title">Staff users</h1>
        </div>
        <div class="staff-top-actions">
          <.link navigate={~p"/staff"} class="staff-refresh">Home</.link>
          <.link navigate={~p"/orders"} class="staff-refresh">Orders</.link>
          <.link href={~p"/logout"} method="delete" class="staff-refresh">Log out</.link>
        </div>
      </header>

      <main class="staff-orders-main staff-admin-main">
        <p :if={@flash_note} class="staff-admin-note">{@flash_note}</p>
        <p class="staff-auth-lede">
          Signed in as {@current_user.name} (Owner). Create staff / manager / owner accounts.
        </p>

        <section class="staff-auth-card staff-admin-form-card">
          <h2 class="staff-admin-heading">Add staff</h2>
          <.form for={@form} id="admin-user-form" phx-submit="save" class="staff-auth-form">
            <.input field={@form[:name]} type="text" label="Name" required />
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input field={@form[:password]} type="password" label="Password" required />
            <.input field={@form[:role]} type="select" label="Role" options={role_options()} />
            <button type="submit" class="menu-basket-checkout">Create account</button>
          </.form>
        </section>

        <section class="staff-orders-section">
          <h2>Team</h2>
          <article :for={user <- @users} class="staff-order-card">
            <header class="staff-order-head">
              <div>
                <p class="staff-order-number">{user.name}</p>
                <p class="staff-order-meta">{user.email}</p>
              </div>
              <div class="staff-order-badges">
                <span class="staff-badge">{User.role_label(user.role)}</span>
                <span class={"staff-badge staff-badge--pay-#{if user.active, do: "paid", else: "unpaid"}"}>
                  {if user.active, do: "Active", else: "Disabled"}
                </span>
              </div>
            </header>

            <div :if={@editing && @editing.id == user.id} class="staff-admin-edit">
              <.form
                for={@edit_form}
                id={"edit-user-#{user.id}"}
                phx-submit="update"
                class="staff-auth-form"
              >
                <.input field={@edit_form[:name]} type="text" label="Name" required />
                <.input field={@edit_form[:email]} type="email" label="Email" required />
                <.input field={@edit_form[:password]} type="password" label="New password (optional)" />
                <.input
                  :if={user.id != @current_user.id}
                  field={@edit_form[:role]}
                  type="select"
                  label="Role"
                  options={role_options()}
                />
                <div class="staff-order-actions">
                  <button type="submit" class="staff-action staff-action-primary">Save</button>
                  <button type="button" class="staff-action" phx-click="cancel_edit">Cancel</button>
                </div>
              </.form>
            </div>

            <div :if={!(@editing && @editing.id == user.id)} class="staff-order-actions">
              <button type="button" class="staff-action" phx-click="edit" phx-value-id={user.id}>
                Edit
              </button>
              <button
                :if={user.id != @current_user.id}
                type="button"
                class="staff-action"
                phx-click="toggle_active"
                phx-value-id={user.id}
              >
                {if user.active, do: "Disable", else: "Enable"}
              </button>
            </div>
          </article>
        </section>
      </main>
    </div>
    """
  end

  defp role_options do
    Enum.map(User.roles(), fn role -> {User.role_label(role), role} end)
  end
end

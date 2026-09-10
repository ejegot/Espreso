defmodule EspresoWeb.AdminUsersLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts
  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users()

    {:ok,
     socket
     |> assign(:page_title, "Staff")
     |> assign_roster(users)
     |> assign(
       :form,
       to_form(Accounts.change_user_registration(%User{}), as: :user, id: "new_user")
     )
     |> assign(:editing, nil)
     |> assign(:edit_form, nil)
     |> assign(:adding?, false)
     |> assign(:confirm, nil)
     |> assign(:flash_note, nil), layout: false}
  end

  @impl true
  def handle_event("toggle_add", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding?, !socket.assigns.adding?)
     |> assign(:confirm, nil)
     |> assign(:flash_note, nil)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    actor = socket.assigns.current_user

    case Accounts.create_user_as(actor, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign_roster(Accounts.list_users())
         |> assign(
           :form,
           to_form(Accounts.change_user_registration(%User{}), as: :user, id: "new_user")
         )
         |> assign(:adding?, false)
         |> assign(:confirm, nil)
         |> assign(:flash_note, "Staff account created.")}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:adding?, true)
         |> assign(:form, to_form(changeset))}
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
       )
       |> assign(:confirm, nil)
       |> assign(:adding?, false)}
    else
      {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign(:edit_form, nil)
     |> assign(:confirm, nil)}
  end

  def handle_event("update", %{"user" => params}, socket) do
    actor = socket.assigns.current_user
    target = socket.assigns.editing

    case Accounts.update_user_as(actor, target, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign_roster(Accounts.list_users())
         |> assign(:editing, nil)
         |> assign(:edit_form, nil)
         |> assign(:confirm, nil)
         |> assign(:flash_note, "Staff account updated.")}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

      {:error, :last_owner} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> assign(:flash_note, "You can’t disable or demote the last active Owner.")}

      {:error, :cannot_deactivate_self} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> assign(:flash_note, "You can’t deactivate your own account.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset))}
    end
  end

  def handle_event("ask_disable", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm, {:disable, id})}
  end

  def handle_event("ask_clear_pin", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm, {:clear_pin, id})}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm, nil)}
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    user = Accounts.get_user!(id)

    cond do
      not Authorization.can?(actor, :user_management) ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

      user.id == actor.id ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> assign(:flash_note, "You can’t deactivate your own account.")}

      true ->
        case Accounts.update_user_as(actor, user, %{active: !user.active}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign_roster(Accounts.list_users())
             |> assign(:confirm, nil)
             |> assign(
               :flash_note,
               if(user.active, do: "Account disabled.", else: "Account enabled.")
             )}

          {:error, :unauthorized} ->
            {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

          {:error, :last_owner} ->
            {:noreply,
             socket
             |> assign(:confirm, nil)
             |> assign(:flash_note, "You can’t disable or demote the last active Owner.")}

          {:error, :cannot_deactivate_self} ->
            {:noreply,
             socket
             |> assign(:confirm, nil)
             |> assign(:flash_note, "You can’t deactivate your own account.")}
        end
    end
  end

  def handle_event("set_pin", %{"id" => id, "pin" => pin}, socket) do
    actor = socket.assigns.current_user
    target = Accounts.get_user!(id)

    case Accounts.set_pin_as(actor, target, String.trim(pin)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign_roster(Accounts.list_users())
         |> assign(:editing, Accounts.get_user!(id))
         |> assign(:confirm, nil)
         |> assign(:flash_note, "PIN set for #{target.name}.")}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

      {:error, :invalid_pin_format} ->
        {:noreply, assign(socket, :flash_note, "PIN must be 4–6 digits.")}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not set PIN.")}
    end
  end

  def handle_event("clear_pin", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    target = Accounts.get_user!(id)

    case Accounts.clear_pin_as(actor, target) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign_roster(Accounts.list_users())
         |> assign(:editing, Accounts.get_user!(id))
         |> assign(:confirm, nil)
         |> assign(:flash_note, "PIN cleared for #{target.name}.")}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to manage users.")}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not clear PIN.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:staff} current_user={@current_user} page_title="Staff">
      <main class="staff-team-page" id="staff-team-page">
        <header class="staff-team-head">
          <div class="staff-team-head-copy">
            <p class="staff-team-eyebrow">Team</p>
            <h2 class="staff-team-title">Staff management</h2>
            <p class="staff-team-lede">Manage your team, roles, access, and PINs.</p>
          </div>
          <button
            type="button"
            class="staff-team-add-toggle"
            id="staff-team-add-toggle"
            phx-click="toggle_add"
          >
            {if(@adding?, do: "Close", else: "Add staff")}
          </button>
        </header>

        <p :if={@flash_note} class="staff-team-note" id="staff-team-note">{@flash_note}</p>

        <section class="staff-team-summary" id="staff-team-summary" aria-label="Team summary">
          <div class="staff-team-summary-item">
            <p class="staff-team-summary-value">{@summary.active}</p>
            <p class="staff-team-summary-label">Active</p>
          </div>
          <div class="staff-team-summary-item">
            <p class="staff-team-summary-value">{@summary.disabled}</p>
            <p class="staff-team-summary-label">Disabled</p>
          </div>
          <div class="staff-team-summary-item">
            <p class="staff-team-summary-value">{@summary.by_role.barista}</p>
            <p class="staff-team-summary-label">Staff</p>
          </div>
          <div class="staff-team-summary-item">
            <p class="staff-team-summary-value">{@summary.by_role.manager}</p>
            <p class="staff-team-summary-label">Managers</p>
          </div>
          <div class="staff-team-summary-item">
            <p class="staff-team-summary-value">{@summary.by_role.owner}</p>
            <p class="staff-team-summary-label">Owners</p>
          </div>
        </section>

        <section class="staff-team-roster" id="staff-team-roster" aria-label="Staff roster">
          <div class="staff-team-roster-head">
            <h3 class="staff-team-section-title">Team roster</h3>
            <p class="staff-team-section-hint">{@summary.total} people</p>
          </div>

          <p :if={@users == []} class="staff-team-empty" id="staff-team-empty">
            No staff yet. Add your first team member to get started.
          </p>

          <article
            :for={user <- @users}
            class={[
              "staff-team-card",
              !user.active && "staff-team-card--disabled",
              @editing && @editing.id == user.id && "is-editing"
            ]}
            id={"staff-team-card-#{user.id}"}
          >
            <header class="staff-team-card-head">
              <div class="staff-team-card-identity">
                <p class="staff-team-card-name">{user.name}</p>
                <p class="staff-team-card-email">{user.email}</p>
              </div>
              <div class="staff-team-card-meta">
                <span class={"staff-team-role staff-team-role--#{user.role}"}>
                  {User.role_label(user.role)}
                </span>
                <span class={"staff-team-status staff-team-status--#{if user.active, do: "active", else: "disabled"}"}>
                  {if user.active, do: "Active", else: "Disabled"}
                </span>
                <span
                  :if={Accounts.pin_set?(user)}
                  class="staff-team-pin staff-team-pin--set"
                  id={"user-pin-set-#{user.id}"}
                >
                  PIN set
                </span>
                <span
                  :if={!Accounts.pin_set?(user)}
                  class="staff-team-pin staff-team-pin--none"
                  id={"user-pin-none-#{user.id}"}
                >
                  No PIN
                </span>
              </div>
            </header>

            <div
              :if={@editing && @editing.id == user.id}
              class="staff-team-edit"
              id={"staff-team-edit-#{user.id}"}
            >
              <.form
                for={@edit_form}
                id={"edit-user-#{user.id}"}
                phx-submit="update"
                class="staff-team-form"
              >
                <div class="staff-team-edit-group">
                  <p class="staff-team-edit-label">Profile</p>
                  <.input field={@edit_form[:name]} type="text" label="Name" required />
                  <.input field={@edit_form[:email]} type="email" label="Email" required />
                </div>

                <div class="staff-team-edit-group">
                  <p class="staff-team-edit-label">Access</p>
                  <.input
                    field={@edit_form[:password]}
                    type="password"
                    label="New password (optional)"
                  />
                  <.input
                    :if={user.id != @current_user.id}
                    field={@edit_form[:role]}
                    type="select"
                    label="Role"
                    options={role_options()}
                  />
                  <p :if={user.id == @current_user.id} class="staff-team-section-hint">
                    You can’t change your own role here.
                  </p>
                </div>

                <div class="staff-team-actions">
                  <button
                    type="submit"
                    class="staff-team-btn staff-team-btn--primary"
                    phx-disable-with="Saving…"
                  >
                    Save
                  </button>
                  <button type="button" class="staff-team-btn" phx-click="cancel_edit">
                    Cancel
                  </button>
                </div>
              </.form>

              <.form
                for={%{}}
                id={"pin-form-#{user.id}"}
                phx-submit="set_pin"
                phx-value-id={user.id}
                class="staff-team-form staff-team-pin-form"
              >
                <div class="staff-team-edit-group">
                  <p class="staff-team-edit-label">PIN</p>
                  <label class="staff-team-pin-label" for={"pin-input-#{user.id}"}>
                    Staff PIN (4–6 digits, for tablet login)
                  </label>
                  <input
                    type="password"
                    name="pin"
                    id={"pin-input-#{user.id}"}
                    inputmode="numeric"
                    pattern="[0-9]{4,6}"
                    autocomplete="off"
                    class="staff-team-input"
                    placeholder={if(Accounts.pin_set?(user), do: "Enter new PIN", else: "Set PIN")}
                  />
                </div>
                <div class="staff-team-actions">
                  <button
                    type="submit"
                    class="staff-team-btn staff-team-btn--primary"
                    id={"set-pin-#{user.id}"}
                    phx-disable-with="Saving PIN…"
                  >
                    {if(Accounts.pin_set?(user), do: "Update PIN", else: "Set PIN")}
                  </button>
                  <button
                    :if={Accounts.pin_set?(user) and not confirming?(@confirm, :clear_pin, user.id)}
                    type="button"
                    class="staff-team-btn"
                    id={"clear-pin-#{user.id}"}
                    phx-click="ask_clear_pin"
                    phx-value-id={user.id}
                  >
                    Clear PIN
                  </button>
                </div>
              </.form>

              <div
                :if={confirming?(@confirm, :clear_pin, user.id)}
                class="staff-team-confirm"
                id={"staff-team-confirm-clear-pin-#{user.id}"}
              >
                <p class="staff-team-confirm-title">Clear this staff member’s PIN?</p>
                <p class="staff-team-confirm-copy">
                  They will need a new PIN before they can use PIN login again.
                </p>
                <div class="staff-team-actions">
                  <button
                    type="button"
                    class="staff-team-btn staff-team-btn--danger"
                    id={"confirm-clear-pin-#{user.id}"}
                    phx-click="clear_pin"
                    phx-value-id={user.id}
                    phx-disable-with="Clearing…"
                  >
                    Clear PIN
                  </button>
                  <button type="button" class="staff-team-btn" phx-click="cancel_confirm">
                    Cancel
                  </button>
                </div>
              </div>
            </div>

            <div :if={!(@editing && @editing.id == user.id)} class="staff-team-actions">
              <button type="button" class="staff-team-btn" phx-click="edit" phx-value-id={user.id}>
                Edit
              </button>
              <button
                :if={
                  user.id != @current_user.id and user.active and
                    not confirming?(@confirm, :disable, user.id)
                }
                type="button"
                class="staff-team-btn"
                id={"disable-user-#{user.id}"}
                phx-click="ask_disable"
                phx-value-id={user.id}
              >
                Disable
              </button>
              <button
                :if={user.id != @current_user.id and !user.active}
                type="button"
                class="staff-team-btn staff-team-btn--primary"
                id={"enable-user-#{user.id}"}
                phx-click="toggle_active"
                phx-value-id={user.id}
                phx-disable-with="Enabling…"
              >
                Enable
              </button>
            </div>

            <div
              :if={confirming?(@confirm, :disable, user.id)}
              class="staff-team-confirm"
              id={"staff-team-confirm-disable-#{user.id}"}
            >
              <p class="staff-team-confirm-title">Disable this staff account?</p>
              <p class="staff-team-confirm-copy">
                They will no longer be able to use the employee app until re-enabled.
              </p>
              <div class="staff-team-actions">
                <button
                  type="button"
                  class="staff-team-btn staff-team-btn--danger"
                  id={"confirm-disable-#{user.id}"}
                  phx-click="toggle_active"
                  phx-value-id={user.id}
                  phx-disable-with="Disabling…"
                >
                  Disable account
                </button>
                <button type="button" class="staff-team-btn" phx-click="cancel_confirm">
                  Cancel
                </button>
              </div>
            </div>
          </article>
        </section>

        <section
          :if={@adding? or @users == []}
          class="staff-team-add"
          id="staff-team-add"
          aria-label="Add staff"
        >
          <h3 class="staff-team-section-title">Add staff</h3>
          <p class="staff-team-section-hint">Create a Staff, Manager, or Owner account.</p>
          <.form for={@form} id="admin-user-form" phx-submit="save" class="staff-team-form">
            <.input field={@form[:name]} type="text" label="Name" required />
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input field={@form[:password]} type="password" label="Password" required />
            <.input field={@form[:role]} type="select" label="Role" options={role_options()} />
            <div class="staff-team-actions">
              <button
                type="submit"
                class="staff-team-btn staff-team-btn--primary"
                id="staff-team-create"
                phx-disable-with="Creating…"
              >
                Create account
              </button>
              <button :if={@users != []} type="button" class="staff-team-btn" phx-click="toggle_add">
                Cancel
              </button>
            </div>
          </.form>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp assign_roster(socket, users) do
    socket
    |> assign(:users, users)
    |> assign(:summary, team_summary(users))
  end

  defp team_summary(users) when is_list(users) do
    active = Enum.count(users, & &1.active)

    %{
      total: length(users),
      active: active,
      disabled: length(users) - active,
      by_role: %{
        barista: Enum.count(users, &(&1.role == "barista")),
        manager: Enum.count(users, &(&1.role == "manager")),
        owner: Enum.count(users, &(&1.role == "owner"))
      }
    }
  end

  defp role_options do
    Enum.map(User.roles(), fn role -> {User.role_label(role), role} end)
  end

  defp confirming?({action, id}, action, user_id) do
    to_string(id) == to_string(user_id)
  end

  defp confirming?(_, _, _), do: false
end

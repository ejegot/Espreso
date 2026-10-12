defmodule EspresoWeb.StaffAccountMenuComponent do
  @moduledoc """
  Compact account control for the staff bar: avatar, name, role, and a
  Settings / Log out menu. Open/close is local UI state only.
  """
  use EspresoWeb, :live_component

  import EspresoWeb.CoreComponents, only: [icon: 1]

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User

  @impl true
  def update(assigns, socket) do
    user = assigns.current_user

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:role_label, User.role_label(user.role))
     |> assign(:initials, account_initials(user))
     |> assign(:settings?, Authorization.can?(user, :business_settings))
     |> assign_new(:open?, fn -> false end)}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :open?, !socket.assigns.open?)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :open?, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class={["staff-account", @open? && "is-open"]}
      id={@id}
      phx-click-away="close"
      phx-target={@myself}
    >
      <button
        type="button"
        class="staff-account-trigger"
        id="staff-account-toggle"
        phx-click="toggle"
        phx-target={@myself}
        aria-expanded={to_string(@open?)}
        aria-controls="staff-account-panel"
        aria-haspopup="menu"
      >
        <span class="staff-account-avatar" aria-hidden="true">{@initials}</span>
        <span class="staff-account-copy">
          <span class="staff-account-name">{@current_user.name}</span>
          <span class="staff-account-role">{@role_label}</span>
        </span>
        <.icon name="hero-chevron-down" class="staff-account-chevron" />
      </button>

      <div
        :if={@open?}
        class="staff-account-panel"
        id="staff-account-panel"
        role="menu"
        aria-label="Account"
      >
        <.link
          :if={@settings?}
          navigate={~p"/admin/settings"}
          class="staff-account-item"
          id="staff-account-settings"
          role="menuitem"
        >
          <.icon name="hero-cog-6-tooth" class="staff-account-item-icon" />
          <span>Settings</span>
        </.link>
        <.link
          href={~p"/logout"}
          method="delete"
          class="staff-account-item staff-account-item--logout"
          id="staff-account-logout"
          role="menuitem"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="staff-account-item-icon" />
          <span>Log out</span>
        </.link>
      </div>
    </div>
    """
  end

  defp account_initials(%User{name: name}) when is_binary(name) do
    parts = name |> String.trim() |> String.split(~r/\s+/, trim: true)

    case parts do
      [] ->
        "?"

      [one] ->
        upcase_first(one)

      [first, second | _] ->
        upcase_first(first) <> upcase_first(second)
    end
  end

  defp account_initials(_), do: "?"

  defp upcase_first(text) do
    case String.first(text) do
      nil -> "?"
      letter -> String.upcase(letter)
    end
  end
end

defmodule EspresoWeb.StaffNavDrawerComponent do
  @moduledoc """
  Left-side staff navigation drawer for secondary ELIlai Kafe tools.
  Open/close is local UI state only — routes and authorization stay unchanged.
  """
  use EspresoWeb, :live_component

  import EspresoWeb.CoreComponents, only: [icon: 1]

  alias Espreso.Accounts.User

  @groups [
    {:counter, "Counter"},
    {:service, "Service"},
    {:shift, "Shift"},
    {:manage, "Manage"}
  ]

  @impl true
  def update(assigns, socket) do
    role_title = User.role_label(assigns.current_user.role)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:role_title, role_title)
     |> assign(:groups, grouped_items(assigns.items))
     |> assign_new(:orders_badge_count, fn -> 0 end)
     |> assign_new(:open?, fn -> false end)}
  end

  @impl true
  def handle_event("open", _params, socket) do
    {:noreply, assign(socket, :open?, true)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :open?, false)}
  end

  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :open?, !socket.assigns.open?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="staff-nav-drawer-root"
      phx-hook="StaffNavDrawer"
      data-open={to_string(@open?)}
    >
      <div
        :if={@open?}
        id="staff-nav-drawer-backdrop"
        class="staff-nav-drawer-backdrop is-open"
        phx-click="close"
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
        aria-hidden="true"
      >
      </div>

      <nav
        id="staff-nav-drawer-panel"
        class={["staff-nav-drawer", @open? && "is-open"]}
        aria-label={@role_title}
        aria-hidden={to_string(not @open?)}
        inert={unless(@open?, do: true)}
      >
        <header class="staff-nav-drawer-head">
          <div class="staff-nav-drawer-brand">
            <img
              src={~p"/images/elilai-kafe/elilai-kafe-mark.png"}
              alt=""
              class="staff-nav-drawer-logo"
              width="128"
              height="128"
              aria-hidden="true"
            />
            <div class="staff-nav-drawer-brand-copy">
              <p class="staff-nav-drawer-brand-name">Elilai Kafe</p>
              <p class="staff-nav-drawer-brand-meta" id="staff-nav-drawer-role">{@role_title}</p>
            </div>
          </div>
          <button
            type="button"
            id="staff-nav-menu-close"
            class="staff-nav-drawer-close"
            phx-click="close"
            phx-target={@myself}
            aria-label="Close navigation menu"
          >
            <.icon name="hero-x-mark" class="staff-nav-drawer-close-icon" />
          </button>
        </header>

        <div class="staff-nav-drawer-body">
          <section
            :for={group <- @groups}
            class="staff-nav-drawer-group"
            id={"staff-nav-drawer-group-#{group.key}"}
            aria-label={group.title}
          >
            <p class="staff-nav-drawer-group-label">{group.title}</p>
            <.link
              :for={item <- group.items}
              navigate={item.path}
              class={[
                "staff-nav-drawer-link",
                @current == item.key && "is-active"
              ]}
              id={"staff-nav-#{item.key}"}
              aria-label={nav_item_aria(item, @orders_badge_count)}
              aria-current={if(@current == item.key, do: "page", else: nil)}
            >
              <.icon name={item.icon} class="staff-nav-drawer-link-icon" />
              <span>{item.label}</span>
              <span
                :if={item.key == :orders and @orders_badge_count > 0}
                class="staff-nav-drawer-badge"
                id="staff-nav-orders-badge"
              >
                {nav_badge_count(@orders_badge_count)}
              </span>
            </.link>
          </section>
        </div>

        <footer class="staff-nav-drawer-foot">
          <.link
            href={~p"/logout"}
            method="delete"
            class="staff-nav-drawer-link staff-nav-drawer-logout"
            id="staff-nav-logout"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="staff-nav-drawer-link-icon" />
            <span>Log out</span>
          </.link>
        </footer>
      </nav>
    </div>
    """
  end

  defp grouped_items(items) do
    by_group = Enum.group_by(items, & &1.group)

    for {key, title} <- @groups,
        grouped = Map.get(by_group, key, []),
        grouped != [] do
      %{key: key, title: title, items: grouped}
    end
  end

  defp nav_item_aria(%{key: :orders, label: label}, count) when is_integer(count) and count > 0 do
    "#{label}, #{count} new"
  end

  defp nav_item_aria(%{label: label}, _count), do: label

  defp nav_badge_count(count) when count > 9, do: "9+"
  defp nav_badge_count(count), do: Integer.to_string(count)
end

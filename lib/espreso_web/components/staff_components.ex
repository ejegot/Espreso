defmodule EspresoWeb.StaffComponents do
  @moduledoc """
  Shared employee chrome for the ELIlai Kafe operations UI.
  """
  use Phoenix.Component

  import EspresoWeb.CoreComponents, only: [icon: 1]

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias EspresoWeb.StaffNavDrawerComponent

  use EspresoWeb, :verified_routes

  @primary_nav_keys [:home, :orders, :pos]

  attr :current, :atom, required: true, doc: "active nav key, e.g. :orders"
  attr :current_user, :map, required: true
  attr :page_title, :string, required: true
  attr :chrome, :atom, default: :top, values: [:top, :rail]

  slot :inner_block, required: true
  slot :tools

  def staff_shell(assigns) do
    items = nav_items(assigns.current_user)
    primary = Enum.filter(items, &(&1.key in @primary_nav_keys))
    drawer = Enum.reject(items, &(&1.key in @primary_nav_keys))

    assigns =
      assigns
      |> assign(:primary_nav, primary)
      |> assign(:drawer_nav, drawer)
      |> assign(:drawer_active?, assigns.current not in @primary_nav_keys)

    ~H"""
    <div class={["staff-app site-page", @chrome == :rail && "staff-app--rail"]}>
      <%= if @chrome == :rail do %>
        <aside class="staff-pos-rail staff-pos-rail--icons" id="staff-pos-rail" aria-label="Staff">
          <div class="staff-pos-rail-brand" title="Elilai Kafe">
            <img
              src={~p"/images/elilai-kafe/elilai-kafe-logo.png"}
              alt=""
              class="staff-pos-rail-logo"
              width="1024"
              height="1024"
              aria-hidden="true"
            />
            <span class="sr-only">Elilai Kafe · {@page_title}</span>
          </div>

          <nav class="staff-pos-rail-nav">
            <.link
              :for={item <- @primary_nav}
              navigate={item.path}
              class={["staff-pos-rail-link", @current == item.key && "is-active"]}
              id={"staff-nav-#{item.key}"}
              aria-label={item.label}
              title={item.label}
              aria-current={if(@current == item.key, do: "page", else: nil)}
            >
              <.icon name={item.icon} class="staff-pos-rail-icon" />
              <span class="sr-only">{item.label}</span>
            </.link>
          </nav>

          <button
            type="button"
            id="staff-nav-menu-open"
            class={[
              "staff-pos-rail-link staff-nav-menu-open staff-nav-menu-open--rail",
              @drawer_active? && "is-active"
            ]}
            phx-click="toggle"
            phx-target="#staff-nav-drawer"
            data-staff-nav-menu-open
            aria-expanded="false"
            aria-controls="staff-nav-drawer-panel"
            aria-label="Open navigation menu"
            title="Menu"
          >
            <.icon name="hero-bars-3" class="staff-pos-rail-icon" />
            <span class="staff-nav-menu-open-label">Menu</span>
          </button>
        </aside>

        <div class="staff-shell-body staff-shell-body--rail">
          <h1 class="sr-only staff-shell-title">{@page_title}</h1>
          {render_slot(@inner_block)}
        </div>
      <% else %>
        <header class="staff-shell" id="staff-shell">
          <div class={["staff-shell-bar", @current == :orders && "staff-shell-bar--orders"]}>
            <%= if @current == :orders do %>
              <div class="staff-shell-heading staff-shell-heading--orders">
                <p class="staff-shell-brand-label">Elilai Kafe</p>
                <h1 class="staff-shell-title staff-shell-orders-title">{@page_title}</h1>
              </div>

              <div class="staff-shell-tools-block staff-shell-tools-block--orders">
                <div class="staff-shell-tools staff-shell-tools--orders">
                  <.live_component
                    module={EspresoWeb.StaffNotificationsComponent}
                    id="staff-notifications"
                  />
                  {render_slot(@tools)}
                </div>
                <p class="staff-shell-user staff-shell-user--orders">
                  {@current_user.name} · {User.role_label(@current_user.role)}
                </p>
              </div>
            <% else %>
              <div class="staff-shell-brand-block">
                <img
                  src={~p"/images/elilai-kafe/elilai-kafe-logo.jpg"}
                  alt="Elilai Kafe"
                  class="staff-shell-brand-logo"
                  width="1024"
                  height="1024"
                />
                <div class="staff-shell-heading">
                  <p class="staff-shell-brand-label">Elilai Kafe</p>
                  <h1 class="staff-shell-title">{@page_title}</h1>
                  <p class="staff-shell-user">
                    {@current_user.name} · {User.role_label(@current_user.role)}
                  </p>
                </div>
              </div>

              <div class="staff-shell-tools">
                <.live_component
                  module={EspresoWeb.StaffNotificationsComponent}
                  id="staff-notifications"
                />
                {render_slot(@tools)}
              </div>
            <% end %>
          </div>

          <nav class="staff-shell-nav" aria-label="Elilai Kafe">
            <button
              type="button"
              id="staff-nav-menu-open"
              class={[
                "staff-nav-menu-open staff-nav-menu-open--top",
                @drawer_active? && "is-active"
              ]}
              phx-click="toggle"
              phx-target="#staff-nav-drawer"
              data-staff-nav-menu-open
              aria-expanded="false"
              aria-controls="staff-nav-drawer-panel"
              aria-label="Open navigation menu"
            >
              <.icon name="hero-bars-3" class="staff-nav-menu-open-icon" />
              <span class="staff-nav-menu-open-text">Menu</span>
            </button>

            <.link
              :for={item <- @primary_nav}
              navigate={item.path}
              class={["staff-shell-nav-link", @current == item.key && "is-active"]}
              id={"staff-nav-#{item.key}"}
              aria-current={if(@current == item.key, do: "page", else: nil)}
            >
              {item.label}
            </.link>
          </nav>
        </header>

        <div class="staff-shell-body">
          {render_slot(@inner_block)}
        </div>
      <% end %>

      <.live_component
        module={StaffNavDrawerComponent}
        id="staff-nav-drawer"
        current={@current}
        current_user={@current_user}
        items={@drawer_nav}
      />
    </div>
    """
  end

  defp nav_items(%User{} = user) do
    [
      %{key: :home, label: "Home", icon: "hero-home", path: ~p"/staff", show?: true},
      %{
        key: :orders,
        label: "Orders",
        icon: "hero-clipboard-document-list",
        path: ~p"/orders",
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :pos,
        label: "POS",
        icon: "hero-shopping-bag",
        path: ~p"/pos",
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :transactions,
        label: "Transactions",
        icon: "hero-receipt-percent",
        path: ~p"/transactions",
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :customers,
        label: "Customers",
        icon: "hero-identification",
        path: ~p"/customers",
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :my_shifts,
        label: "My shifts",
        icon: "hero-clock",
        path: ~p"/staff/shifts",
        show?: user.role == "barista"
      },
      %{
        key: :cash_out,
        label: "Cash Out",
        icon: "hero-banknotes",
        path: ~p"/staff/cash-out",
        show?: Espreso.CashOuts.can_access?(user)
      },
      %{
        key: :dashboard,
        label: "Dashboard",
        icon: "hero-chart-bar",
        path: ~p"/dashboard",
        show?: user.role in ["manager", "owner"]
      },
      %{
        key: :reports,
        label: "Reports",
        icon: "hero-document-chart-bar",
        path: ~p"/staff/reports",
        show?: Authorization.can?(user, :reports)
      },
      %{
        key: :close,
        label: "Close shift",
        icon: "hero-lock-closed",
        path: ~p"/staff/close",
        show?: Espreso.Shifts.can_access_close?(user)
      },
      %{
        key: :attendance,
        label: "Staff attendance",
        icon: "hero-user-group",
        path: ~p"/staff/attendance",
        show?: Authorization.can?(user, :reports)
      },
      %{
        key: :availability,
        label: "Availability",
        icon: "hero-cube",
        path: ~p"/admin/availability",
        show?: Authorization.can?(user, :product_availability)
      },
      %{
        key: :staff,
        label: "Staff",
        icon: "hero-users",
        path: ~p"/admin/users",
        show?: Authorization.can?(user, :user_management)
      },
      %{
        key: :settings,
        label: "Settings",
        icon: "hero-cog-6-tooth",
        path: ~p"/admin/settings",
        show?: Authorization.can?(user, :business_settings)
      }
    ]
    |> Enum.filter(& &1.show?)
  end
end

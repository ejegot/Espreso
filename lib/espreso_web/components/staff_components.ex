defmodule EspresoWeb.StaffComponents do
  @moduledoc """
  Shared employee chrome for the ELIlai Kafe operations UI.
  """
  use Phoenix.Component

  import EspresoWeb.CoreComponents, only: [icon: 1]

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.Orders
  alias EspresoWeb.StaffNavDrawerComponent

  use EspresoWeb, :verified_routes

  attr :current, :atom, required: true, doc: "active nav key, e.g. :orders"
  attr :current_user, :map, required: true
  attr :page_title, :string, required: true
  attr :chrome, :atom, default: :top, values: [:top, :rail, :bar]
  attr :orders_badge_count, :integer, default: 0

  slot :inner_block, required: true
  slot :tools

  def staff_shell(assigns) do
    items = nav_items(assigns.current_user)

    orders_badge_count =
      if assigns.current == :pos do
        assigns.orders_badge_count
      else
        Orders.new_lane_count()
      end

    assigns =
      assigns
      |> assign(:drawer_nav, items)
      |> assign(:drawer_active?, assigns.current != :home)
      |> assign(:orders_badge_count, orders_badge_count)

    ~H"""
    <div
      class={[
        "staff-app site-page",
        @chrome == :rail && "staff-app--rail",
        @chrome == :bar && "staff-app--bar"
      ]}
      id="elilai-printer-bridge"
      phx-hook="ElilaiPrinter"
    >
      <%= if @chrome in [:rail, :bar] do %>
        <header
          class={[
            "staff-pos-rail",
            @chrome == :rail && "staff-pos-rail--icons",
            @chrome == :bar && "staff-pos-rail--bar"
          ]}
          id="staff-pos-rail"
          aria-label="Staff"
        >
          <button
            type="button"
            id="staff-nav-menu-open"
            class={[
              "staff-pos-rail-link staff-nav-menu-open",
              @chrome == :rail && "staff-nav-menu-open--rail",
              @chrome == :bar && "staff-nav-menu-open--bar",
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
            <span class="sr-only">Menu</span>
          </button>

          <div class="staff-pos-rail-end">
            <div :if={@tools != []} class="staff-pos-rail-tools">
              {render_slot(@tools)}
            </div>
            <.live_component
              :if={@current != :pos}
              module={EspresoWeb.StaffNotificationsComponent}
              id="staff-notifications"
            />
            <.link
              navigate={~p"/staff"}
              class="staff-pos-rail-brand"
              id="staff-nav-logo"
              title={"#{@current_user.name} · #{User.role_label(@current_user.role)} · Elilai Kafe"}
              aria-label="Home"
            >
              <img
                src={~p"/images/elilai-kafe/elilai-kafe-logo.png"}
                alt=""
                class="staff-pos-rail-logo"
                width="1024"
                height="1024"
                aria-hidden="true"
              />
              <span class="sr-only">Elilai Kafe · {@page_title}</span>
            </.link>
          </div>
        </header>

        <div class={[
          "staff-shell-body",
          @chrome == :rail && "staff-shell-body--rail",
          @chrome == :bar && "staff-shell-body--bar"
        ]}>
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
        orders_badge_count={@orders_badge_count}
      />
    </div>
    """
  end

  defp nav_items(%User{} = user) do
    [
      %{
        key: :home,
        label: "Home",
        icon: "hero-home",
        path: ~p"/staff",
        group: :counter,
        show?: true
      },
      %{
        key: :orders,
        label: "Orders",
        icon: "hero-clipboard-document-list",
        path: ~p"/orders",
        group: :counter,
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :pos,
        label: "POS",
        icon: "hero-shopping-bag",
        path: ~p"/pos",
        group: :counter,
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :transactions,
        label: "Transactions",
        icon: "hero-receipt-percent",
        path: ~p"/transactions",
        group: :service,
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :customers,
        label: "Customers",
        icon: "hero-identification",
        path: ~p"/customers",
        group: :service,
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :cash_out,
        label: "Cash Out",
        icon: "hero-banknotes",
        path: ~p"/staff/cash-out",
        group: :shift,
        show?: Espreso.CashOuts.can_access?(user)
      },
      %{
        key: :open_shop,
        label: "Open shop",
        icon: "hero-lock-open",
        path: ~p"/staff/open",
        group: :shift,
        show?: Espreso.Shifts.can_access_open?(user)
      },
      %{
        key: :close,
        label: "Close shift",
        icon: "hero-lock-closed",
        path: ~p"/staff/close",
        group: :shift,
        show?: Espreso.Shifts.can_access_close?(user)
      },
      %{
        key: :attendance,
        label: "Staff attendance",
        icon: "hero-user-group",
        path: ~p"/staff/attendance",
        group: :shift,
        show?: Authorization.can?(user, :reports)
      },
      %{
        key: :my_shifts,
        label: "My shifts",
        icon: "hero-clock",
        path: ~p"/staff/shifts",
        group: :shift,
        show?: user.role == "barista"
      },
      %{
        key: :reports,
        label: "Reports",
        icon: "hero-document-chart-bar",
        path: ~p"/staff/reports",
        group: :manage,
        show?: Authorization.can?(user, :reports)
      },
      %{
        key: :availability,
        label: "Availability",
        icon: "hero-cube",
        path: ~p"/admin/availability",
        group: :manage,
        show?: Authorization.can?(user, :product_availability)
      },
      %{
        key: :staff,
        label: "Staff",
        icon: "hero-users",
        path: ~p"/admin/users",
        group: :manage,
        show?: Authorization.can?(user, :user_management)
      },
      %{
        key: :settings,
        label: "Settings",
        icon: "hero-cog-6-tooth",
        path: ~p"/admin/settings",
        group: :manage,
        show?: Authorization.can?(user, :business_settings)
      }
    ]
    |> Enum.filter(& &1.show?)
  end

  attr :status, :atom, required: true
  attr :id, :string, required: true
  attr :show_open_link, :boolean, default: true

  def shop_day_sales_banner(%{status: :open} = assigns) do
    ~H""
  end

  def shop_day_sales_banner(assigns) do
    {title, body, link?} =
      case assigns.status do
        :closed ->
          {"Shop day is closed",
           "No new sales until tomorrow. Mid-shift Time In/Out does not reopen the kaha.", false}

        _ ->
          {"Opening cash required",
           "Count the drawer once before selling. Mid and close shifts skip this.", true}
      end

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:body, body)
      |> assign(:link?, link? and assigns.show_open_link)

    ~H"""
    <section class="staff-home-shop-open" id={@id}>
      <p class="staff-home-shop-open-title">{@title}</p>
      <p class="staff-home-shop-open-body">{@body}</p>
      <.link :if={@link?} navigate={~p"/staff/open"} class="staff-home-shop-open-action">
        Enter opening cash
      </.link>
    </section>
    """
  end
end

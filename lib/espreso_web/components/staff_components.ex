defmodule EspresoWeb.StaffComponents do
  @moduledoc """
  Shared employee chrome for the ELIlai Kafe operations UI.
  """
  use Phoenix.Component

  import EspresoWeb.CoreComponents, only: [icon: 1]

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.Orders
  alias Espreso.Tenancy
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

    owner_rail? = owner_rail?(assigns.current_user)
    owner_rail_overlay? = owner_rail? and assigns.current in [:orders, :pos]

    assigns =
      assigns
      |> assign(:drawer_nav, items)
      |> assign(:orders_badge_count, orders_badge_count)
      |> assign(:owner_rail?, owner_rail?)
      |> assign(:owner_rail_overlay?, owner_rail_overlay?)
      |> assign(:owner_nav_groups, if(owner_rail?, do: staff_nav_groups(items), else: []))

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
              @chrome == :bar && "staff-nav-menu-open--bar"
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
          <.link
            :if={@chrome == :bar}
            navigate={~p"/staff"}
            class="staff-bar-brand"
            id="staff-bar-brand"
            aria-label="Elilai Kafe Home"
          >
            <img
              src={~p"/images/elilai-kafe/elilai-kafe-mark.png"}
              alt=""
              class="staff-bar-brand-logo"
              width="1024"
              height="1024"
              aria-hidden="true"
            />
            <span class="staff-bar-brand-name">Elilai Kafe</span>
          </.link>

          <div class="staff-pos-rail-end">
            <form
              :if={branch_switcher?(assigns)}
              id="staff-branch-switch"
              class="staff-branch-switch"
              method="post"
              action={~p"/session/branch"}
            >
              <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
              <label class="sr-only" for="staff-branch-select">Branch</label>
              <select
                id="staff-branch-select"
                name="branch_id"
                class="staff-branch-select"
                onchange="this.form.submit()"
              >
                <option
                  :for={branch <- tenant_branches(assigns)}
                  value={branch.id}
                  selected={branch.id == current_branch_id(assigns)}
                >
                  {branch.name}
                </option>
              </select>
            </form>
            <p :if={not branch_switcher?(assigns)} class="staff-branch-label">
              {current_branch_name(assigns)}
            </p>
            <div :if={@tools != []} class="staff-pos-rail-tools">
              {render_slot(@tools)}
            </div>
            <.live_component
              :if={@current not in [:pos, :orders]}
              module={EspresoWeb.StaffNotificationsComponent}
              id="staff-notifications"
            />
            <.link
              :if={@current == :orders}
              navigate={~p"/pos"}
              class="staff-pos-rail-hop"
              id="staff-rail-hop-pos"
              title="POS"
              aria-label="POS"
            >
              <.icon name="hero-shopping-bag" class="staff-pos-rail-icon" />
              <span class="sr-only">POS</span>
            </.link>
            <.link
              :if={@current == :pos}
              navigate={~p"/orders"}
              class="staff-pos-rail-hop"
              id="staff-rail-hop-orders"
              title="Orders"
              aria-label={
                if @orders_badge_count > 0,
                  do: "Orders, #{@orders_badge_count} new",
                  else: "Orders"
              }
            >
              <.icon name="hero-clipboard-document-list" class="staff-pos-rail-icon" />
              <span
                :if={@orders_badge_count > 0}
                class="staff-pos-rail-hop-badge"
                id="staff-rail-hop-orders-badge"
              >
                {hop_badge_count(@orders_badge_count)}
              </span>
              <span class="sr-only">Orders</span>
            </.link>
            <.live_component
              :if={@chrome == :bar}
              module={EspresoWeb.StaffAccountMenuComponent}
              id="staff-account-menu"
              current_user={@current_user}
            />
            <.link
              :if={@chrome == :rail}
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

        <%= if @owner_rail_overlay? do %>
          <.owner_dash_rail flyout current={@current} groups={@owner_nav_groups} />
        <% end %>

        <div class={[
          "staff-shell-body",
          @chrome == :rail && "staff-shell-body--rail",
          @chrome == :bar && "staff-shell-body--bar"
        ]}>
          <%= if @owner_rail? and not @owner_rail_overlay? do %>
            <div class="owner-dash" id="owner-dashboard">
              <.owner_dash_rail current={@current} groups={@owner_nav_groups} />
              <div class="owner-dash-canvas">
                <h1 class="sr-only staff-shell-title">{@page_title}</h1>
                {render_slot(@inner_block)}
              </div>
            </div>
          <% else %>
            <h1 class="sr-only staff-shell-title">{@page_title}</h1>
            {render_slot(@inner_block)}
          <% end %>
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
              class="staff-nav-menu-open staff-nav-menu-open--top"
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

  def staff_nav_items(%User{} = user), do: nav_items(user)

  attr :current, :atom, required: true
  attr :groups, :list, required: true
  attr :flyout, :boolean, default: false

  defp owner_dash_rail(assigns) do
    ~H"""
    <aside
      class={["owner-dash-aside", @flyout && "owner-dash-aside--flyout"]}
      id="owner-dash-aside"
      aria-label="Owner"
      phx-hook="OwnerDashRail"
    >
      <div class="owner-dash-rail">
        <nav class="owner-dash-nav">
          <section
            :for={group <- @groups}
            class="owner-dash-nav-group"
            id={"owner-dash-nav-group-#{group.key}"}
            aria-label={group.title}
          >
            <p class="owner-dash-nav-group-label">{group.title}</p>
            <.link
              :for={item <- group.items}
              navigate={item.path}
              class={["owner-dash-nav-link", item.key == @current && "is-active"]}
              id={"owner-dash-nav-#{item.key}"}
              title={item.label}
            >
              <.icon name={item.icon} class="owner-dash-nav-icon" />
              <span class="owner-dash-nav-label">{item.label}</span>
            </.link>
          </section>
        </nav>
        <footer class="owner-dash-foot">
          <.link
            href={~p"/logout"}
            method="delete"
            class="owner-dash-nav-link owner-dash-logout"
            id="owner-dash-nav-logout"
            title="Log out"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="owner-dash-nav-icon" />
            <span class="owner-dash-nav-label">Log out</span>
          </.link>
        </footer>
      </div>
    </aside>
    """
  end

  defp owner_rail?(%User{role: "owner"}), do: true
  defp owner_rail?(_user), do: false

  @nav_groups [
    {:counter, "Counter"},
    {:service, "Service"},
    {:shift, "Shift"},
    {:manage, "Manage"}
  ]

  def staff_nav_groups(items) when is_list(items) do
    by_group = Enum.group_by(items, & &1.group)

    for {key, title} <- @nav_groups,
        grouped = Map.get(by_group, key, []),
        grouped != [] do
      %{key: key, title: title, items: grouped}
    end
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
        key: :branches,
        label: "Branches",
        icon: "hero-building-storefront",
        path: ~p"/admin/branches",
        group: :manage,
        show?: Authorization.can?(user, :user_management)
      },
      %{
        key: :tenants,
        label: "Tenants",
        icon: "hero-building-office",
        path: ~p"/admin/tenants",
        group: :manage,
        show?: Tenancy.platform_owner?(user)
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

  defp hop_badge_count(count) when count > 9, do: "9+"
  defp hop_badge_count(count), do: Integer.to_string(count)

  defp current_branch_id(assigns) do
    Map.get(assigns, :current_branch_id) || Tenancy.current_branch_id()
  end

  defp current_branch_name(assigns) do
    case Map.get(assigns, :current_branch) || Tenancy.current_branch() do
      %{name: name} -> name
      _ -> "Lilac"
    end
  end

  defp tenant_branches(assigns) do
    case Map.get(assigns, :tenant_branches) do
      list when is_list(list) and list != [] -> list
      _ -> Tenancy.list_branches(Tenancy.current_tenant_id())
    end
  end

  defp branch_switcher?(assigns) do
    Tenancy.switcher?(assigns.current_user) and length(tenant_branches(assigns)) > 1
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

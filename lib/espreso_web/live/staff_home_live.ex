defmodule EspresoWeb.StaffHomeLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.Menu
  alias Espreso.Orders
  alias EspresoWeb.StaffNotifications

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Orders.subscribe()

    user = socket.assigns.current_user
    overview = Orders.dashboard_overview()
    sales = if manager_or_owner?(user), do: Orders.sales_overview(), else: nil

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:overview, overview)
     |> assign(:sales, sales)
     |> assign(:primary, primary_tiles(user, overview))
     |> assign(:secondary, secondary_tiles(user)), layout: false}
  end

  @impl true
  def handle_info({:order_changed, order}, socket) do
    StaffNotifications.push_order_change(order)
    user = socket.assigns.current_user
    overview = Orders.dashboard_overview()
    sales = if manager_or_owner?(user), do: Orders.sales_overview(), else: nil

    {:noreply,
     socket
     |> assign(:overview, overview)
     |> assign(:sales, sales)
     |> assign(:primary, primary_tiles(user, overview))
     |> assign(:secondary, secondary_tiles(user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:home} current_user={@current_user} page_title="Home">
      <main class="staff-home-main staff-home-hub staff-home-desk" id="staff-home-desk">
        <header class="staff-home-desk-head">
          <div>
            <p class="staff-home-desk-eyebrow">Shift desk</p>
            <h2 class="staff-home-desk-title">Good shift, {@current_user.name}.</h2>
            <p class="staff-home-lede staff-home-desk-lede">
              {User.role_label(@current_user.role)} · Choose where to work.
            </p>
          </div>
          <div class="staff-home-desk-status" id="staff-home-shop-status">
            <span class="staff-home-status-dot" aria-hidden="true"></span>
            <span>Shop · Live</span>
          </div>
        </header>

        <section class="staff-home-primary" aria-label="Primary workspaces">
          <.link
            :for={item <- @primary}
            navigate={item.path}
            class={["staff-home-hero-tile", item[:class]]}
            id={"staff-home-#{item.id}"}
          >
            <div class="staff-home-hero-top">
              <span class="staff-home-card-eyebrow">{item.eyebrow}</span>
              <span
                :if={is_integer(item[:count]) and item.count > 0}
                class="staff-home-hero-count"
              >
                {item.count}
              </span>
            </div>
            <span class="staff-home-card-title">{item.title}</span>
            <span class="staff-home-card-body">{item.body}</span>
            <span class="staff-home-hero-cta">{item.cta}</span>
          </.link>
        </section>

        <section
          :if={@secondary != []}
          class="staff-home-secondary"
          aria-label="More tools"
        >
          <.link
            :for={item <- @secondary}
            navigate={item.path}
            class={["staff-home-card", "staff-home-hub-card", item[:class]]}
            id={"staff-home-#{item.id}"}
          >
            <span class="staff-home-card-eyebrow">{item.eyebrow}</span>
            <span class="staff-home-card-title">
              {item.title}
              <span
                :if={is_integer(item[:count]) and item.count > 0}
                class="staff-home-inline-count"
              >
                {item.count}
              </span>
            </span>
            <span class="staff-home-card-body">{item.body}</span>
          </.link>
        </section>

        <section
          class="staff-home-today"
          id="staff-home-today"
          aria-label="Today"
        >
          <p class="staff-home-today-eyebrow">Today</p>
          <%= if @sales do %>
            <div class="staff-home-today-row">
              <p class="staff-home-today-total">
                {Menu.format_price(@sales.todays_paid_total)}
                <span>paid</span>
              </p>
              <p class="staff-home-today-meta">
                {@sales.todays_paid_count} paid orders · {@overview.active_count} active · {@overview.unpaid_active_count} unpaid in kitchen
              </p>
            </div>
          <% else %>
            <div class="staff-home-today-row staff-home-today-row--compact">
              <p class="staff-home-today-meta" id="staff-home-today-barista">
                {@overview.received_count} new · {@overview.preparing_count} preparing · {@overview.unpaid_active_count} unpaid · {@overview.todays_count} orders today
              </p>
            </div>
          <% end %>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp primary_tiles(%User{} = user, overview) do
    [
      %{
        id: "orders",
        eyebrow: "Kitchen",
        title: "Orders",
        body: orders_body(overview),
        path: ~p"/orders",
        count: overview.received_count,
        cta: "Open board →",
        class: "staff-home-hero-tile--orders",
        show?: Authorization.can?(user, :orders)
      },
      %{
        id: "pos",
        eyebrow: "Counter",
        title: "POS",
        body: "Walk-in orders and pay-at-create.",
        path: ~p"/pos",
        count: nil,
        cta: "New order →",
        class: "staff-home-hero-tile--pos",
        show?: Authorization.can?(user, :orders)
      }
    ]
    |> Enum.filter(& &1.show?)
  end

  defp secondary_tiles(%User{} = user) do
    unpaid_count = length(Orders.list_todays_unpaid())

    base = [
      %{
        id: "unpaid",
        eyebrow: "Attention",
        title: "Unpaid",
        body: "Confirm counter and QR payments.",
        path: ~p"/orders?unpaid=1",
        count: unpaid_count,
        show?: Authorization.can?(user, :orders),
        class: "staff-home-card--attention"
      }
    ]

    manager =
      if manager_or_owner?(user) do
        [
          %{
            id: "dashboard",
            eyebrow: "Overview",
            title: "Dashboard",
            body: "Sales, reports, and today’s activity.",
            path: ~p"/dashboard",
            count: nil,
            show?: true
          },
          %{
            id: "availability",
            eyebrow: "Menu",
            title: "Availability",
            body: "Mark items sold out or back in stock.",
            path: ~p"/admin/availability",
            count: nil,
            show?: Authorization.can?(user, :product_availability)
          }
        ]
      else
        []
      end

    owner =
      if user.role == "owner" do
        [
          %{
            id: "staff",
            eyebrow: "Team",
            title: "Staff",
            body: "Accounts, roles, and PINs.",
            path: ~p"/admin/users",
            count: nil,
            show?: true,
            class: "staff-home-card-owner"
          },
          %{
            id: "settings",
            eyebrow: "Shop",
            title: "Settings",
            body: "Payments mode, QR codes, and contact info.",
            path: ~p"/admin/settings",
            count: nil,
            show?: true,
            class: "staff-home-card-owner"
          }
        ]
      else
        []
      end

    (base ++ manager ++ owner)
    |> Enum.filter(& &1.show?)
  end

  defp manager_or_owner?(%User{role: role}), do: role in ["manager", "owner"]
  defp manager_or_owner?(_), do: false

  defp orders_body(overview) do
    "#{overview.received_count} new · #{overview.preparing_count} preparing · #{overview.unpaid_active_count} unpaid"
  end
end

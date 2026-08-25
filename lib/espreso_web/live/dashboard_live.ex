defmodule EspresoWeb.DashboardLive do
  use EspresoWeb, :live_view

  alias Espreso.Menu
  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:order_overview, Orders.dashboard_overview())
     |> assign(:todays_orders, Orders.list_todays_orders())
     |> assign(:sales_overview, Orders.sales_overview())
     |> assign(:popular_products, Orders.popular_products())
     |> assign(:reports_overview, Orders.reports_overview()), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:dashboard} current_user={@current_user} page_title="Dashboard">
      <main class="staff-home-main">
        <p class="staff-home-lede">
          {dashboard_lede(@current_user.role)}
        </p>

        <div class="staff-home-grid" id="dashboard-panels">
          <%= for panel <-
                panels_for(
                  @current_user.role,
                  @order_overview,
                  @sales_overview,
                  @popular_products,
                  @reports_overview
                ) do %>
            <%= case panel.kind do %>
              <% :link -> %>
                <.link
                  navigate={panel.to}
                  class={["staff-home-card", "dashboard-card-link", panel[:class]]}
                  id={"dashboard-panel-#{panel.id}"}
                >
                  <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                  <span class="staff-home-card-title">{panel.title}</span>
                  <span class="staff-home-card-body">{panel.body}</span>
                </.link>
              <% :metric -> %>
                <div
                  class="staff-home-card dashboard-card-metric-panel"
                  id={"dashboard-panel-#{panel.id}"}
                >
                  <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                  <span class="staff-home-card-title">{panel.title}</span>
                  <span class="staff-home-card-body dashboard-card-metric">{panel.body}</span>
                </div>
              <% :list -> %>
                <div
                  class="staff-home-card dashboard-card-metric-panel"
                  id={"dashboard-panel-#{panel.id}"}
                >
                  <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                  <span class="staff-home-card-title">{panel.title}</span>
                  <p :if={panel.items == []} class="staff-home-card-body">
                    {panel.empty_body}
                  </p>
                  <ul :if={panel.items != []} class="dashboard-popular-list">
                    <li :for={item <- panel.items}>
                      <span class="dashboard-popular-name">{item.name}</span>
                      <span class="dashboard-popular-qty">· {item.quantity}</span>
                    </li>
                  </ul>
                </div>
              <% :placeholder -> %>
                <div
                  class="staff-home-card staff-home-card-soon dashboard-card-soon"
                  id={"dashboard-panel-#{panel.id}"}
                >
                  <span class="staff-home-soon-pill">Coming soon</span>
                  <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                  <span class="staff-home-card-title">{panel.title}</span>
                  <span class="staff-home-card-body">{panel.body}</span>
                </div>
            <% end %>
          <% end %>
        </div>

        <section
          id="dashboard-todays-orders-preview"
          class="staff-orders-section dashboard-todays-preview"
        >
          <div class="dashboard-todays-preview-head">
            <h2>Today’s Orders</h2>
            <.link navigate={~p"/orders"} class="staff-shell-tool">Open order queue</.link>
          </div>

          <p :if={@todays_orders == []} class="staff-empty">No orders yet today.</p>

          <article
            :for={order <- @todays_orders}
            class="staff-order-card"
            id={"dashboard-preview-order-#{order.id}"}
          >
            <header class="staff-order-head">
              <div>
                <p class="staff-order-number">{order.number}</p>
                <p class="staff-order-name">{order.customer_name}</p>
              </div>
              <div class="staff-order-badges">
                <span class={"staff-badge staff-badge--#{order.status}"}>
                  {Orders.status_label(order.status)}
                </span>
                <span class={"staff-badge staff-badge--pay-#{order.payment_status}"}>
                  {Orders.payment_label(order)}
                </span>
              </div>
            </header>

            <p class="staff-order-meta">
              {Orders.fulfillment_label(order.fulfillment)}
              <span :if={order.table_number}>· Table {order.table_number}</span>
            </p>
          </article>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp dashboard_lede("owner"), do: "Shop overview — sales, team, and settings."
  defp dashboard_lede("manager"), do: "Day-to-day operations — orders, availability, and reports."
  defp dashboard_lede(_), do: "Your shift overview — today’s orders."

  defp panels_for("owner", overview, sales, popular, reports) do
    [
      sales_panel(sales),
      orders_panel(overview),
      popular_products_panel(popular),
      reports_panel(reports),
      availability_panel(),
      %{
        kind: :placeholder,
        id: "staff-activity",
        eyebrow: "Team",
        title: "Staff Activity",
        body: "Coming soon"
      },
      %{
        kind: :link,
        id: "users",
        eyebrow: "Owner",
        title: "Users",
        body: "Manage staff accounts.",
        to: ~p"/admin/users",
        class: "staff-home-card-owner"
      },
      %{
        kind: :link,
        id: "settings",
        eyebrow: "Owner",
        title: "Settings",
        body: "Business contact, hours, and social links.",
        to: ~p"/admin/settings",
        class: "staff-home-card-owner"
      }
    ]
  end

  defp panels_for("manager", overview, sales, _popular, reports) do
    [
      sales_panel(sales),
      orders_panel(overview),
      availability_panel(),
      reports_panel(reports)
    ]
  end

  defp panels_for(_staff, _overview, _sales, _popular, _reports), do: []

  defp availability_panel do
    %{
      kind: :link,
      id: "availability",
      eyebrow: "Menu",
      title: "Availability",
      body: "86 sold-out items and restore them.",
      to: ~p"/admin/availability",
      class: nil
    }
  end

  defp sales_panel(sales) do
    %{
      kind: :metric,
      id: "sales",
      eyebrow: "Today",
      title: "Sales",
      body: sales_body(sales)
    }
  end

  defp sales_body(%{todays_paid_total: total, todays_paid_count: count}) do
    "#{Menu.format_price(total)} today · #{count} paid orders"
  end

  defp reports_panel(reports) do
    %{
      kind: :metric,
      id: "reports",
      eyebrow: "Last 7 days",
      title: "Reports",
      body: reports_body(reports)
    }
  end

  defp reports_body(%{period_paid_count: 0}), do: "No paid sales in the last 7 days."

  defp reports_body(%{period_paid_total: total, period_paid_count: count, period_days: days}) do
    "#{Menu.format_price(total)} last #{days} days · #{count} paid orders"
  end

  defp popular_products_panel(popular) do
    %{
      kind: :list,
      id: "popular-products",
      eyebrow: "Menu",
      title: "Popular Products",
      items: popular,
      empty_body: "No paid product sales today."
    }
  end

  defp orders_panel(overview) do
    %{
      kind: :link,
      id: "orders",
      eyebrow: "Kitchen",
      title: "Orders",
      body: orders_body(overview),
      to: ~p"/orders",
      class: nil
    }
  end

  defp orders_body(overview) do
    "#{overview.active_count} active · #{overview.received_count} received · #{overview.preparing_count} preparing · #{overview.unpaid_active_count} unpaid"
  end
end

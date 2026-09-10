defmodule EspresoWeb.DashboardLive do
  use EspresoWeb, :live_view

  alias Espreso.Menu
  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    breakdown = Orders.todays_paid_breakdown()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:order_overview, Orders.dashboard_overview())
     |> assign(:todays_orders, Orders.list_todays_orders())
     |> assign(:sales_overview, Orders.sales_overview())
     |> assign(:paid_breakdown, breakdown)
     |> assign(:via_rows, Orders.paid_via_rows(breakdown))
     |> assign(:popular_products, Orders.popular_products())
     |> assign(:reports_overview, Orders.reports_overview()), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:dashboard} current_user={@current_user} page_title="Dashboard">
      <main class="staff-home-main dashboard-page" id="staff-dashboard">
        <header class="dashboard-head">
          <p class="staff-home-lede dashboard-lede">
            {dashboard_lede(@current_user.role)}
          </p>
        </header>

        <section
          :if={show_money?(@current_user.role)}
          class="dashboard-primary"
          id="dashboard-primary"
          aria-label="Today’s paid sales"
        >
          <div
            class="staff-home-card dashboard-card-metric-panel dashboard-hero-sales"
            id="dashboard-panel-sales"
          >
            <span class="staff-home-card-eyebrow">Today</span>
            <span class="staff-home-card-title">Paid today</span>
            <span class="staff-home-card-body dashboard-card-metric">
              {sales_body(@sales_overview)}
            </span>
          </div>

          <section
            id="dashboard-paid-breakdown"
            class="staff-home-card dashboard-paid-breakdown-panel"
            aria-label="Payment methods"
          >
            <span class="staff-home-card-eyebrow">Settled today</span>
            <span class="staff-home-card-title">Payment methods</span>
            <p class="staff-home-card-body dashboard-paid-breakdown-note">
              Breakdown of today’s paid sales by method.
            </p>
            <ul class="staff-paid-breakdown">
              <li :for={row <- @via_rows} class="staff-paid-breakdown-row">
                <span class="staff-paid-breakdown-label">{row.label}</span>
                <span class="staff-paid-breakdown-total">{Menu.format_price(row.total)}</span>
                <span class="staff-paid-breakdown-count">{row.count}</span>
              </li>
            </ul>
            <.link navigate={~p"/staff/close"} class="staff-shell-tool dashboard-close-link">
              Close shift
            </.link>
          </section>
        </section>

        <div
          :if={show_money?(@current_user.role)}
          class="staff-home-grid dashboard-panels"
          id="dashboard-panels"
        >
          <%= for panel <-
                panels_for(
                  @current_user.role,
                  @order_overview,
                  @popular_products,
                  @reports_overview
                ) do %>
            <%= case panel.kind do %>
              <% :link -> %>
                <.link
                  navigate={panel.to}
                  class={[
                    "staff-home-card",
                    "dashboard-card-link",
                    panel[:class],
                    panel[:emphasis] && "dashboard-card-link--attention"
                  ]}
                  id={"dashboard-panel-#{panel.id}"}
                >
                  <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                  <span class="staff-home-card-title">{panel.title}</span>
                  <span class="staff-home-card-body">{panel.body}</span>
                </.link>
              <% :metric -> %>
                <div
                  class={[
                    "staff-home-card dashboard-card-metric-panel",
                    panel[:secondary] && "dashboard-card-secondary"
                  ]}
                  id={"dashboard-panel-#{panel.id}"}
                >
                  <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                  <span class="staff-home-card-title">{panel.title}</span>
                  <span class="staff-home-card-body dashboard-card-metric">{panel.body}</span>
                </div>
              <% :list -> %>
                <div
                  class={[
                    "staff-home-card dashboard-card-metric-panel",
                    panel[:secondary] && "dashboard-card-secondary"
                  ]}
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
            <% end %>
          <% end %>
        </div>

        <section
          id="dashboard-todays-orders-preview"
          class="staff-orders-section dashboard-todays-preview"
        >
          <div class="dashboard-todays-preview-head">
            <div>
              <p class="dashboard-todays-preview-eyebrow">Order queue</p>
              <h2>Today’s Orders</h2>
              <p class="dashboard-todays-preview-note">
                Live kitchen work lives on Orders — this is a quick glance only.
              </p>
            </div>
            <.link navigate={~p"/orders"} class="staff-shell-tool" id="dashboard-open-orders">
              Open order queue
            </.link>
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
            </p>
          </article>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp dashboard_lede("owner"),
    do: "Today’s management snapshot — paid sales, attention, and shortcuts."

  defp dashboard_lede("manager"),
    do: "Today’s management snapshot — paid sales, attention, and shortcuts."

  defp dashboard_lede(_), do: "Your shift overview — today’s orders."

  defp show_money?(role) when role in ["manager", "owner"], do: true
  defp show_money?(_), do: false

  defp panels_for("owner", overview, popular, reports) do
    [
      orders_panel(overview),
      transactions_panel(),
      close_shift_panel(),
      availability_panel(),
      reports_panel(reports),
      popular_products_panel(popular),
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

  defp panels_for("manager", overview, _popular, reports) do
    [
      orders_panel(overview),
      transactions_panel(),
      close_shift_panel(),
      availability_panel(),
      reports_panel(reports)
    ]
  end

  defp panels_for(_staff, _overview, _popular, _reports), do: []

  defp availability_panel do
    %{
      kind: :link,
      id: "availability",
      eyebrow: "Menu",
      title: "Availability",
      body: "Mark items sold out or available.",
      to: ~p"/admin/availability",
      class: nil
    }
  end

  defp transactions_panel do
    %{
      kind: :link,
      id: "transactions",
      eyebrow: "Receipts",
      title: "Transactions",
      body: "Paid receipt history and reprints.",
      to: ~p"/transactions",
      class: nil
    }
  end

  defp close_shift_panel do
    %{
      kind: :link,
      id: "close-shift",
      eyebrow: "Shift",
      title: "Close shift",
      body: "Reconcile counted cash and close the shop day.",
      to: ~p"/staff/close",
      class: nil
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
      body: reports_body(reports),
      secondary: true
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
      empty_body: "No paid product sales today.",
      secondary: true
    }
  end

  defp orders_panel(overview) do
    %{
      kind: :link,
      id: "orders",
      eyebrow: "Attention",
      title: "Orders",
      body: orders_body(overview),
      to: ~p"/orders",
      class: nil,
      emphasis: true
    }
  end

  defp orders_body(overview) do
    "#{overview.active_count} active · #{overview.received_count} received · #{overview.preparing_count} preparing · #{overview.unpaid_active_count} unpaid"
  end
end

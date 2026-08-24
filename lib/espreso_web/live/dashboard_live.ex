defmodule EspresoWeb.DashboardLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User
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
    <div class="menu-page-brune site-page staff-home-page dashboard-page">
      <header class="staff-orders-top">
        <div>
          <p class="staff-orders-brand">CoffeeSpot</p>
          <h1 class="staff-orders-title">Dashboard</h1>
          <p class="staff-orders-user">
            {@current_user.name} · {User.role_label(@current_user.role)}
          </p>
        </div>
        <div class="staff-top-actions">
          <.link navigate={~p"/staff"} class="staff-refresh">Staff workspace</.link>
          <.link href={~p"/logout"} method="delete" class="staff-refresh">Log out</.link>
        </div>
      </header>

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
            <%= if panel[:to] do %>
              <.link navigate={panel.to} class="staff-home-card" id={"dashboard-panel-#{panel.id}"}>
                <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                <span class="staff-home-card-title">{panel.title}</span>
                <span class="staff-home-card-body">{panel.body}</span>
              </.link>
            <% else %>
              <div class="staff-home-card staff-home-card-soon" id={"dashboard-panel-#{panel.id}"}>
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
            <.link navigate={~p"/orders"} class="staff-refresh">Open order queue</.link>
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
    </div>
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
      %{
        id: "staff-activity",
        eyebrow: "Team",
        title: "Staff Activity",
        body: "Staff activity will appear here.",
        to: nil
      },
      %{
        id: "users",
        eyebrow: "Owner",
        title: "Users",
        body: "Manage staff accounts.",
        to: ~p"/admin/users"
      },
      %{
        id: "settings",
        eyebrow: "Owner",
        title: "Settings",
        body: "Business settings will appear here.",
        to: nil
      }
    ]
  end

  defp panels_for("manager", overview, sales, _popular, reports) do
    [
      sales_panel(sales),
      orders_panel(overview),
      %{
        id: "availability",
        eyebrow: "Menu",
        title: "Availability",
        body: "Product availability will appear here.",
        to: nil
      },
      reports_panel(reports)
    ]
  end

  defp panels_for(_staff, overview, _sales, _popular, _reports) do
    [
      %{
        id: "todays-orders",
        eyebrow: "Kitchen",
        title: "Today’s Orders",
        body: todays_orders_body(overview),
        to: ~p"/orders"
      }
    ]
  end

  defp sales_panel(sales) do
    %{
      id: "sales",
      eyebrow: "Overview",
      title: "Sales",
      body: sales_body(sales),
      to: nil
    }
  end

  defp sales_body(%{todays_paid_total: total, todays_paid_count: count}) do
    "#{Menu.format_price(total)} today · #{count} paid orders"
  end

  defp reports_panel(reports) do
    %{
      id: "reports",
      eyebrow: "Insights",
      title: "Reports",
      body: reports_body(reports),
      to: nil
    }
  end

  defp reports_body(%{period_paid_count: 0}), do: "No paid sales in the last 7 days."

  defp reports_body(%{period_paid_total: total, period_paid_count: count, period_days: days}) do
    "#{Menu.format_price(total)} last #{days} days · #{count} paid orders"
  end

  defp popular_products_panel(popular) do
    %{
      id: "popular-products",
      eyebrow: "Menu",
      title: "Popular Products",
      body: popular_products_body(popular),
      to: nil
    }
  end

  defp popular_products_body([]), do: "No paid product sales today."

  defp popular_products_body(products) do
    products
    |> Enum.map(fn %{name: name, quantity: quantity} -> "#{name} (#{quantity})" end)
    |> Enum.join(", ")
  end

  defp orders_panel(overview) do
    %{
      id: "orders",
      eyebrow: "Kitchen",
      title: "Orders",
      body: orders_body(overview),
      to: ~p"/orders"
    }
  end

  defp orders_body(overview) do
    "#{overview.active_count} active · #{overview.received_count} received · #{overview.preparing_count} preparing · #{overview.unpaid_active_count} unpaid"
  end

  defp todays_orders_body(overview) do
    "#{overview.todays_count} today · #{overview.active_count} active"
  end
end

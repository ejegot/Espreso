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
     |> assign(:sales_overview, Orders.sales_overview())
     |> assign(:paid_breakdown, breakdown)
     |> assign(:via_rows, Orders.paid_via_rows(breakdown))
     |> assign(:popular_products, Orders.popular_products())
     |> assign(:reports_overview, Orders.reports_overview()), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell
      current={:dashboard}
      current_user={@current_user}
      page_title="Dashboard"
      chrome={:bar}
    >
      <main class="staff-home-main dashboard-page dashboard-page--sales" id="staff-dashboard">
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
          </section>
        </section>

        <div
          :if={show_money?(@current_user.role)}
          class="staff-home-grid dashboard-panels"
          id="dashboard-panels"
        >
          <%= for panel <- sales_panels(@current_user.role, @popular_products, @reports_overview) do %>
            <%= case panel.kind do %>
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
          :if={not show_money?(@current_user.role)}
          class="dashboard-staff-note"
          id="dashboard-staff-note"
        >
          <p class="staff-empty">Sales reports are for managers. Kitchen work lives on Orders.</p>
          <.link navigate={~p"/orders"} class="staff-shell-tool" id="dashboard-open-orders">
            Open Orders
          </.link>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp dashboard_lede(role) when role in ["owner", "manager"],
    do: "Today’s sales — paid mix, last 7 days, and what’s selling."

  defp dashboard_lede(_), do: "Sales reports are for managers."

  defp show_money?(role) when role in ["manager", "owner"], do: true
  defp show_money?(_), do: false

  defp sales_panels("owner", popular, reports) do
    [reports_panel(reports), popular_products_panel(popular)]
  end

  defp sales_panels("manager", _popular, reports) do
    [reports_panel(reports)]
  end

  defp sales_panels(_staff, _popular, _reports), do: []

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
end

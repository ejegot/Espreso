defmodule EspresoWeb.DashboardLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Shifts

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
     |> assign(:reports_overview, Orders.reports_overview())
     |> assign(:sales_chart, Orders.paid_sales_chart())
     |> assign(:shop_date, Orders.shop_date_today())
     |> assign(:shop_day_status, Shifts.shop_day_status()), layout: false}
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
          <div class="dashboard-head-copy">
            <p class="dashboard-kicker">{User.role_label(@current_user.role)}</p>
            <h1 class="dashboard-heading" id="dashboard-heading">Dashboard</h1>
            <p class="staff-home-lede dashboard-lede">
              {dashboard_lede(@current_user.role)}
            </p>
          </div>
          <div :if={show_money?(@current_user.role)} class="dashboard-head-pills">
            <span class="dashboard-date-pill">
              <span class="dashboard-pill-label">Shop day</span>
              <strong>{Calendar.strftime(@shop_date, "%a %b %d")}</strong>
            </span>
            <span class="dashboard-date-pill">
              <span class="dashboard-pill-label">Status</span>
              <strong>{shop_day_status_label(@shop_day_status)}</strong>
            </span>
          </div>
        </header>

        <section
          :if={show_money?(@current_user.role)}
          class="dashboard-kpi-grid"
          id="dashboard-primary"
          aria-label="Key numbers"
        >
          <article class="dashboard-kpi-card is-hero" id="dashboard-panel-sales">
            <span class="dashboard-kpi-icon" aria-hidden="true">₱</span>
            <span class="staff-home-card-eyebrow">Today</span>
            <span class="staff-home-card-title">Paid today</span>
            <span class="staff-home-card-body dashboard-card-metric">
              {sales_body(@sales_overview)}
            </span>
          </article>

          <article class="dashboard-kpi-card" id="dashboard-panel-reports">
            <span class="dashboard-kpi-icon" aria-hidden="true">7</span>
            <span class="staff-home-card-eyebrow">Last 7 days</span>
            <span class="staff-home-card-title">Reports</span>
            <span class="staff-home-card-body dashboard-card-metric">
              {reports_body(@reports_overview)}
            </span>
          </article>

          <article class="dashboard-kpi-card is-compact" id="dashboard-kpi-tickets">
            <span class="dashboard-kpi-icon" aria-hidden="true">#</span>
            <span class="staff-home-card-eyebrow">Today</span>
            <span class="staff-home-card-title">Paid tickets</span>
            <strong class="dashboard-kpi-value">{@sales_overview.todays_paid_count}</strong>
            <span class="dashboard-kpi-hint">Settled this shop day</span>
          </article>

          <article class="dashboard-kpi-card is-compact" id="dashboard-kpi-cash">
            <span class="dashboard-kpi-icon" aria-hidden="true">C</span>
            <span class="staff-home-card-eyebrow">Today</span>
            <span class="staff-home-card-title">Cash</span>
            <strong class="dashboard-kpi-value">
              {Menu.format_price(cash_today(@paid_breakdown))}
            </strong>
            <span class="dashboard-kpi-hint">Of paid mix</span>
          </article>
        </section>

        <section
          :if={show_money?(@current_user.role)}
          class="dashboard-quick-actions"
          id="dashboard-quick-actions"
          aria-label="Shortcuts"
        >
          <.link
            navigate={~p"/staff/reports"}
            class="dashboard-quick-action"
            id="dashboard-action-reports"
          >
            <span class="dashboard-quick-action-icon" aria-hidden="true">↗</span>
            <span>Sales report</span>
          </.link>
          <.link
            navigate={~p"/staff/close"}
            class="dashboard-quick-action"
            id="dashboard-action-close"
          >
            <span class="dashboard-quick-action-icon" aria-hidden="true">▣</span>
            <span>Close shift</span>
          </.link>
          <.link
            navigate={~p"/transactions"}
            class="dashboard-quick-action"
            id="dashboard-action-receipts"
          >
            <span class="dashboard-quick-action-icon" aria-hidden="true">≡</span>
            <span>Receipts</span>
          </.link>
          <.link navigate={~p"/staff"} class="dashboard-quick-action" id="dashboard-action-home">
            <span class="dashboard-quick-action-icon" aria-hidden="true">⌂</span>
            <span>Home drawer</span>
          </.link>
        </section>

        <section
          :if={show_money?(@current_user.role)}
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

        <section
          :if={show_money?(@current_user.role)}
          class="staff-home-card dashboard-chart-panel"
          id="dashboard-sales-chart"
          aria-labelledby="dashboard-chart-heading"
        >
          <header class="dashboard-panel-header">
            <div>
              <span class="staff-home-card-eyebrow">Last 7 days</span>
              <span class="staff-home-card-title" id="dashboard-chart-heading">Paid sales</span>
              <p class="dashboard-chart-legend">Daily settled totals</p>
            </div>
          </header>
          <div class="dashboard-chart" role="img" aria-label="Paid sales for the last 7 shop days">
            <div :for={point <- @sales_chart} class="dashboard-chart-col">
              <div class="dashboard-chart-value">{chart_amount_label(point.amount)}</div>
              <div class="dashboard-chart-track">
                <div
                  class="dashboard-chart-bar is-revenue"
                  style={"height: #{point.pct}%"}
                  title={"#{point.day_label}: #{Menu.format_price(point.amount)} · #{point.count}"}
                >
                </div>
              </div>
              <span>{point.label}</span>
            </div>
          </div>
        </section>

        <div
          :if={show_money?(@current_user.role)}
          class="staff-home-grid dashboard-panels"
          id="dashboard-panels"
        >
          <%= for panel <- sales_panels(@current_user.role, @popular_products) do %>
            <div
              class="staff-home-card dashboard-card-metric-panel dashboard-card-secondary"
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

  defp shop_day_status_label(:open), do: "Open"
  defp shop_day_status_label(:closed), do: "Closed"
  defp shop_day_status_label(_), do: "Not open"

  defp sales_panels("owner", popular), do: [popular_products_panel(popular)]
  defp sales_panels(_, _), do: []

  defp sales_body(%{todays_paid_total: total, todays_paid_count: count}) do
    "#{Menu.format_price(total)} today · #{count} paid orders"
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
      items: popular,
      empty_body: "No paid product sales today."
    }
  end

  defp cash_today(%{by_via: by_via}) when is_map(by_via) do
    Shifts.cash_sales_total(%{by_via: by_via})
  end

  defp cash_today(_), do: Decimal.new("0")

  defp chart_amount_label(%Decimal{} = amount) do
    if Decimal.compare(amount, 0) == :eq do
      "—"
    else
      Menu.format_price(amount)
    end
  end

  defp chart_amount_label(_), do: "—"
end

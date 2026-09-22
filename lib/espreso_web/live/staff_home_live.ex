defmodule EspresoWeb.StaffHomeLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.CashOuts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Printer
  alias Espreso.Shifts
  alias EspresoWeb.StaffNotifications

  @pubsub_reload_debounce_ms 300

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Orders.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:printer_note, nil)
     |> assign(:pubsub_reload_timer, nil)
     |> assign(:pubsub_reload_token, nil)
     |> assign_home_state(), layout: false}
  end

  @impl true
  def handle_event("printer_test_print", _params, socket) do
    case Printer.dispatch_payload_test() do
      {:client_dispatch, bytes} ->
        {:noreply,
         socket
         |> assign(:printer_note, "Sending test print…")
         |> push_event("elilai-printer", %{
           action: "raw_test",
           permit: "raw",
           request_id: Integer.to_string(System.unique_integer([:positive])),
           data_base64: Printer.encode_payload(bytes),
           order_id: 0,
           flow: "raw_test"
         })}

      other ->
        {:noreply,
         assign(socket, :printer_note, printer_action_note(map_test_result(other), "Test print"))}
    end
  end

  def handle_event("printer_open_drawer", _params, socket) do
    case Printer.dispatch_drawer() do
      {:client_dispatch, bytes} ->
        {:noreply,
         socket
         |> assign(:printer_note, "Test Drawer…")
         |> push_event("elilai-printer", %{
           action: "raw_drawer",
           permit: "raw",
           request_id: Integer.to_string(System.unique_integer([:positive])),
           data_base64: Printer.encode_payload(bytes),
           order_id: 0,
           flow: "raw_drawer"
         })}

      other ->
        {:noreply,
         assign(
           socket,
           :printer_note,
           printer_action_note(map_drawer_result(other), "Test Drawer")
         )}
    end
  end

  def handle_event("elilai_printer_result", params, socket) do
    case params do
      %{"flow" => flow, "ok" => ok} when flow in ["raw_test", "raw_drawer"] ->
        ok? = ok in [true, "true"]

        note =
          cond do
            ok? and flow == "raw_drawer" ->
              "Test Drawer: ok"

            ok? ->
              "Test print: ok"

            true ->
              "#{if(flow == "raw_drawer", do: "Test Drawer", else: "Test print")}: #{Map.get(params, "error") || "failed"}"
          end

        {:noreply, assign(socket, :printer_note, note)}

      _ ->
        {:noreply, socket}
    end
  end

  defp map_test_result(:dispatched), do: :ok
  defp map_test_result(:disabled), do: :disabled
  defp map_test_result({:definite_failure, reason}), do: {:error, reason}
  defp map_test_result({:uncertain, reason}), do: {:error, reason}
  defp map_test_result(other), do: other

  defp map_drawer_result(:dispatched), do: :ok
  defp map_drawer_result(:disabled), do: :disabled
  defp map_drawer_result({:definite_failure, reason}), do: {:error, reason}
  defp map_drawer_result({:uncertain, reason}), do: {:error, reason}
  defp map_drawer_result(other), do: other

  @impl true
  def handle_info({:order_changed, order}, socket) do
    StaffNotifications.push_order_change(order)

    {:noreply, schedule_pubsub_reload(socket)}
  end

  def handle_info({:coalesced_home_reload, token}, socket) do
    if socket.assigns.pubsub_reload_token == token do
      {:noreply,
       socket
       |> assign(:pubsub_reload_timer, nil)
       |> assign(:pubsub_reload_token, nil)
       |> assign_home_state()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:home} current_user={@current_user} page_title="Home" chrome={:bar}>
      <main class="staff-home-main dashboard-page dashboard-page--sales" id="staff-home-desk">
        <header class="dashboard-head" id="staff-home-identity">
          <div class="dashboard-head-copy">
            <p class="dashboard-kicker">{User.role_label(@current_user.role)}</p>
            <h1 class="dashboard-heading">Home</h1>
            <p class="staff-home-lede dashboard-lede" id="staff-home-greeting">{@greeting}</p>
          </div>
          <div class="dashboard-head-pills">
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

        <section :if={@shop_open_prompt?} class="staff-home-shop-open" id="staff-home-shop-open">
          <p class="staff-home-shop-open-title">Opening cash required</p>
          <p class="staff-home-shop-open-body">
            Count the drawer once before selling. POS and orders stay locked until this is recorded.
          </p>
          <.link
            navigate={~p"/staff/open"}
            class="staff-home-shop-open-action"
            id="staff-home-shop-open-link"
          >
            Enter opening cash
          </.link>
        </section>

        <.shop_day_sales_banner
          :if={!@shop_open_prompt?}
          status={@shop_day_status}
          id="staff-home-shop-closed"
          show_open_link={false}
        />

        <section class="dashboard-kpi-grid" id="staff-home-kpis" aria-label="Key numbers">
          <%= if @money? do %>
            <article class="dashboard-kpi-card" id="dashboard-panel-sales">
              <span class="staff-home-card-title">Paid today</span>
              <strong class="dashboard-kpi-value">
                {Menu.format_price(@sales.todays_paid_total)}
              </strong>
              <span class="staff-home-card-body dashboard-kpi-hint">{sales_body(@sales)}</span>
            </article>
            <article class="dashboard-kpi-card" id="dashboard-kpi-tickets">
              <span class="staff-home-card-title">Paid tickets</span>
              <strong class="dashboard-kpi-value">{@sales.todays_paid_count}</strong>
              <span class="dashboard-kpi-hint">Settled this shop day</span>
            </article>
            <article class="dashboard-kpi-card" id="dashboard-kpi-cash">
              <span class="staff-home-card-title">Cash</span>
              <strong class="dashboard-kpi-value">{Menu.format_price(cash_today(@breakdown))}</strong>
              <span class="dashboard-kpi-hint">Of paid mix</span>
            </article>
            <.link
              navigate={~p"/staff/reports"}
              class="dashboard-kpi-card"
              id="dashboard-panel-reports"
            >
              <span class="staff-home-card-title">Reports</span>
              <strong class="dashboard-kpi-value">
                {Menu.format_price(@reports_overview.period_paid_total)}
              </strong>
              <span class="staff-home-card-body dashboard-kpi-hint">
                {reports_body(@reports_overview)}
              </span>
            </.link>
          <% else %>
            <article class="dashboard-kpi-card" id="staff-home-kpi-active">
              <span class="staff-home-card-title">Active</span>
              <strong class="dashboard-kpi-value">{@overview.active_count}</strong>
              <span class="dashboard-kpi-hint">Received + preparing</span>
            </article>
            <article class="dashboard-kpi-card" id="staff-home-kpi-unpaid">
              <span class="staff-home-card-title">Unpaid</span>
              <strong class="dashboard-kpi-value">{@overview.unpaid_active_count}</strong>
              <span class="dashboard-kpi-hint">Still open on the board</span>
            </article>
            <article class="dashboard-kpi-card" id="staff-home-kpi-preparing">
              <span class="staff-home-card-title">Preparing</span>
              <strong class="dashboard-kpi-value">{@overview.preparing_count}</strong>
              <span class="dashboard-kpi-hint">In progress</span>
            </article>
            <article class="dashboard-kpi-card" id="staff-home-kpi-tickets">
              <span class="staff-home-card-title">Tickets</span>
              <strong class="dashboard-kpi-value">{@overview.todays_count}</strong>
              <span class="dashboard-kpi-hint">Placed this shop day</span>
            </article>
          <% end %>
        </section>

        <section class="dashboard-launch" aria-label="Primary action">
          <.link
            :for={item <- @primary}
            navigate={item.path}
            class={["dashboard-launch-btn", item[:class]]}
            id={"staff-home-#{item.id}"}
          >
            <span class="dashboard-launch-title">{item.title}</span>
            <span class="dashboard-launch-body">{item.body}</span>
          </.link>
        </section>

        <div class={["dashboard-split", not @money? && "is-single"]}>
          <section
            class="staff-home-card dashboard-chart-panel"
            id="staff-home-chart"
            aria-labelledby="staff-home-chart-heading"
          >
            <header class="dashboard-panel-header">
              <span class="staff-home-card-title" id="staff-home-chart-heading">
                {if(@money?, do: "Paid sales", else: "Tickets")}
              </span>
              <p class="dashboard-chart-legend">Last 7 days</p>
            </header>
            <svg
              class="dashboard-sparkline"
              viewBox="0 0 100 40"
              preserveAspectRatio="none"
              role="img"
              aria-label="Last 7 shop days"
            >
              <polyline
                class="dashboard-sparkline-fill"
                fill="color-mix(in srgb, #394331 14%, transparent)"
                stroke="none"
                points={"0,40 #{sparkline_points(@chart)} 100,40"}
              />
              <polyline
                class="dashboard-sparkline-line"
                fill="none"
                stroke="#394331"
                stroke-width="1.8"
                stroke-linejoin="round"
                stroke-linecap="round"
                points={sparkline_points(@chart)}
              />
            </svg>
            <ol class="dashboard-sparkline-axis">
              <li :for={point <- @chart}>{point.label}</li>
            </ol>
          </section>

          <section
            :if={@money?}
            id="staff-home-paid-breakdown"
            class="staff-home-card dashboard-donut-panel"
            aria-label="Payment methods"
          >
            <span class="staff-home-card-title">Payment methods</span>
            <div class="dashboard-donut-row">
              <div class="dashboard-donut" style={donut_style(@via_rows)} aria-hidden="true"></div>
              <ul class="staff-paid-breakdown">
                <li :for={row <- @via_rows} class="staff-paid-breakdown-row">
                  <span class="staff-paid-breakdown-label">{row.label}</span>
                  <span class="staff-paid-breakdown-total">{Menu.format_price(row.total)}</span>
                  <span class="staff-paid-breakdown-count">{row.count}</span>
                </li>
              </ul>
            </div>
          </section>
        </div>

        <section :if={@money?} class="staff-home-today" id="staff-home-today" aria-label="Today">
          <p :if={@shift_close} class="staff-home-today-closed" id="staff-home-shift-closed">
            Closed · {Shifts.format_closed_at(@shift_close.closed_at)}
            <span :if={@shift_close.closed_by_user}>
              by {@shift_close.closed_by_user.name}
            </span>
          </p>

          <div :if={@drawer_summary} class="staff-home-drawer" id="staff-home-drawer">
            <p class="staff-home-today-eyebrow">
              {if(@drawer_summary.sealed?, do: "Drawer · sealed", else: "Drawer")}
            </p>
            <ul class="staff-home-drawer-list">
              <li>
                <span>Opening</span>
                <strong>{Menu.format_price(@drawer_summary.opening)}</strong>
              </li>
              <li>
                <span>Cash sales</span>
                <strong>{Menu.format_price(@drawer_summary.cash_sales)}</strong>
              </li>
              <li>
                <span>Cash outs</span>
                <strong>{Menu.format_price(@drawer_summary.cash_outs)}</strong>
              </li>
              <li>
                <span>Expected</span>
                <strong>{Menu.format_price(@drawer_summary.expected)}</strong>
              </li>
              <li :if={@drawer_summary.sealed?}>
                <span>Counted</span>
                <strong>{Menu.format_price(@drawer_summary.counted)}</strong>
              </li>
              <li :if={@drawer_summary.sealed?} id="staff-home-drawer-variance">
                <span>Variance</span>
                <strong>{variance_line(@drawer_summary.variance)}</strong>
              </li>
            </ul>
            <.link
              navigate={~p"/staff/close"}
              class="staff-home-drawer-link"
              id="staff-home-drawer-close"
            >
              {if(@drawer_summary.sealed?, do: "View close", else: "Close shift")}
            </.link>
          </div>
        </section>

        <div
          :if={@current_user.role == "owner"}
          class="staff-home-grid dashboard-panels"
          id="dashboard-panels"
        >
          <div
            class="staff-home-card dashboard-card-metric-panel dashboard-card-secondary"
            id="dashboard-panel-popular-products"
          >
            <span class="staff-home-card-eyebrow">Menu</span>
            <span class="staff-home-card-title">Popular Products</span>
            <p :if={@popular_products == []} class="staff-home-card-body">
              No paid product sales today.
            </p>
            <table :if={@popular_products != []} class="dashboard-popular-table">
              <thead>
                <tr>
                  <th>Item</th>
                  <th>Qty</th>
                </tr>
              </thead>
              <tbody class="dashboard-popular-list">
                <tr :for={item <- @popular_products}>
                  <td class="dashboard-popular-name">{item.name}</td>
                  <td class="dashboard-popular-qty">{item.quantity}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <section class="staff-home-desk-tools" aria-label="Now">
          <div class="staff-home-secondary">
            <.link
              :for={item <- @launch_tools}
              navigate={item.path}
              class={["staff-home-tool-link", item[:class]]}
              id={"staff-home-#{item.id}"}
            >
              <span class="staff-home-tool-label">
                {item.title}
                <span
                  :if={is_integer(item[:count]) and item.count > 0}
                  class="staff-home-inline-count"
                >
                  {item.count}
                </span>
              </span>
              <span class="staff-home-tool-body">{item.body}</span>
            </.link>
          </div>
          <div :if={@shift_tools != []} class="staff-home-tertiary">
            <.link
              :for={item <- @shift_tools}
              navigate={item.path}
              class={["staff-home-tool-link", "staff-home-tool-link--quiet", item[:class]]}
              id={"staff-home-#{item.id}"}
            >
              <span class="staff-home-tool-label">{item.title}</span>
              <span class="staff-home-tool-body">{item.body}</span>
            </.link>
          </div>
        </section>

        <section
          :if={@printer_on_home?}
          class="staff-home-printer staff-home-printer--compact"
          id="staff-home-printer"
          aria-label="Printer"
        >
          <div class="staff-home-printer-copy">
            <p class="staff-home-today-eyebrow">Printer</p>
            <p class="staff-home-today-meta">
              LAN · {Printer.host()}:{Printer.port()}
            </p>
          </div>
          <div class="staff-home-printer-actions">
            <button
              type="button"
              id="staff-printer-test"
              class="staff-home-printer-btn"
              phx-click="printer_test_print"
            >
              Test print
            </button>
            <button
              type="button"
              id="staff-printer-drawer"
              class="staff-home-printer-btn"
              phx-click="printer_open_drawer"
            >
              Test Drawer
            </button>
          </div>
          <p
            :if={@printer_note}
            class="staff-home-today-meta staff-home-printer-note"
            id="staff-printer-note"
          >
            {@printer_note}
          </p>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp schedule_pubsub_reload(socket) do
    socket = cancel_pubsub_reload(socket)
    ms = pubsub_reload_debounce_ms()

    if ms <= 0 do
      assign_home_state(socket)
    else
      token = make_ref()
      timer = Process.send_after(self(), {:coalesced_home_reload, token}, ms)

      socket
      |> assign(:pubsub_reload_timer, timer)
      |> assign(:pubsub_reload_token, token)
    end
  end

  defp cancel_pubsub_reload(socket) do
    if timer = socket.assigns[:pubsub_reload_timer] do
      Process.cancel_timer(timer)
    end

    socket
    |> assign(:pubsub_reload_timer, nil)
    |> assign(:pubsub_reload_token, nil)
  end

  defp pubsub_reload_debounce_ms do
    Application.get_env(:espreso, :staff_pubsub_reload_debounce_ms, @pubsub_reload_debounce_ms)
  end

  defp assign_home_state(socket) do
    socket = cancel_pubsub_reload(socket)
    user = socket.assigns.current_user
    overview = Orders.dashboard_overview()
    money? = manager_or_owner?(user)

    breakdown = if money?, do: Orders.todays_paid_breakdown(), else: nil
    sales = if breakdown, do: Orders.sales_overview(), else: nil
    shop_open = Shifts.get_todays_open()
    close = Shifts.get_todays_close()
    shift_close = if money?, do: close, else: nil

    shop_open_prompt? =
      Shifts.can_access_open?(user) and is_nil(shop_open) and is_nil(close)

    chart = if money?, do: Orders.paid_sales_chart(), else: Orders.order_volume_chart()
    popular = if user.role == "owner", do: Orders.popular_products(), else: []

    socket
    |> assign(:overview, overview)
    |> assign(:money?, money?)
    |> assign(:sales, sales)
    |> assign(:breakdown, breakdown)
    |> assign(:via_rows, if(breakdown, do: Orders.paid_via_rows(breakdown), else: []))
    |> assign(:shift_close, shift_close)
    |> assign(:shop_open, shop_open)
    |> assign(:shop_open_prompt?, shop_open_prompt?)
    |> assign(:shop_day_status, Shifts.shop_day_status())
    |> assign(:shop_date, Orders.shop_date_today())
    |> assign(:drawer_summary, drawer_summary(money?, shop_open, close, breakdown))
    |> assign(:today_visible?, money?)
    |> assign(:chart, chart)
    |> assign(:reports_overview, if(money?, do: Orders.reports_overview(), else: nil))
    |> assign(:popular_products, popular)
    |> assign(:printer_on_home?, money? and Printer.enabled?())
    |> assign(:greeting, staff_greeting(user))
    |> assign(:primary, primary_tiles(user, overview))
    |> then(fn socket ->
      tools = desk_tools(user, overview)
      {shift_tools, launch_tools} = Enum.split_with(tools, &(&1.id == "my-shifts"))

      socket
      |> assign(:launch_tools, launch_tools)
      |> assign(:shift_tools, shift_tools)
    end)
  end

  defp staff_greeting(%User{name: name}) do
    first_name =
      name
      |> to_string()
      |> String.trim()
      |> String.split(~r/\s+/, parts: 2)
      |> List.first()
      |> case do
        nil -> "there"
        "" -> "there"
        value -> value
      end

    "#{daypart_greeting()}, #{first_name}"
  end

  defp daypart_greeting do
    hour =
      DateTime.utc_now()
      |> DateTime.add(8 * 60 * 60, :second)
      |> Map.fetch!(:hour)

    cond do
      hour < 12 -> "Good morning"
      hour < 17 -> "Good afternoon"
      true -> "Good evening"
    end
  end

  defp primary_tiles(%User{} = user, overview) do
    [
      %{
        id: "pos",
        eyebrow: "Counter",
        title: "Open POS",
        body: "Take walk-in orders and payment",
        path: ~p"/pos",
        cta: "Open POS →",
        class: "staff-home-pos-cta--primary",
        show?: Authorization.can?(user, :orders)
      },
      %{
        id: "orders",
        eyebrow: "Board",
        title: "Orders",
        body: orders_body(overview),
        path: ~p"/orders",
        cta: "Open Orders →",
        class: "staff-home-pos-cta--secondary",
        show?: Authorization.can?(user, :orders)
      }
    ]
    |> Enum.filter(& &1.show?)
  end

  defp desk_tools(%User{} = user, _overview) do
    unpaid_count = Orders.count_todays_unpaid()

    [
      %{
        id: "unpaid",
        title: "Unpaid",
        body: "Confirm counter & QR",
        path: ~p"/orders?unpaid=1",
        count: unpaid_count,
        show?: Authorization.can?(user, :orders),
        class: "staff-home-tool-link--attention"
      },
      %{
        id: "my-shifts",
        title: "My shifts",
        body: "Time In, Time Out & sales",
        path: ~p"/staff/shifts",
        count: nil,
        show?: user.role == "barista"
      }
    ]
    |> Enum.filter(& &1.show?)
  end

  defp manager_or_owner?(%User{role: role}), do: role in ["manager", "owner"]
  defp manager_or_owner?(_), do: false

  defp sparkline_points(chart) when is_list(chart) do
    n = max(length(chart) - 1, 1)

    chart
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {point, index} ->
      x = index / n * 100
      y = 36 - Map.get(point, :pct, 0) / 100 * 32
      "#{Float.round(x / 1, 2)},#{Float.round(y / 1, 2)}"
    end)
  end

  defp sparkline_points(_), do: "0,36 100,36"

  @donut_colors ["#394331", "#f85020", "#c4a574", "#6b7f5a", "#8b6914"]

  defp donut_style(rows) when is_list(rows) do
    total =
      Enum.reduce(rows, Decimal.new("0"), fn row, acc ->
        Decimal.add(acc, row.total || Decimal.new("0"))
      end)

    if Decimal.compare(total, 0) != :gt do
      "background: color-mix(in srgb, var(--dash-forest, #394331) 12%, #fff)"
    else
      {stops, _} =
        rows
        |> Enum.with_index()
        |> Enum.reduce({[], 0.0}, fn {row, index}, {acc, start} ->
          pct =
            row.total
            |> Decimal.div(total)
            |> Decimal.mult(Decimal.new(100))
            |> Decimal.to_float()

          color = Enum.at(@donut_colors, rem(index, length(@donut_colors)))
          stop = start + pct
          {acc ++ ["#{color} #{start}% #{stop}%"], stop}
        end)

      "background: conic-gradient(#{Enum.join(stops, ", ")})"
    end
  end

  defp donut_style(_), do: "background: #fff"

  defp shop_day_status_label(:open), do: "Open"
  defp shop_day_status_label(:closed), do: "Closed"
  defp shop_day_status_label(_), do: "Not open"

  defp sales_body(%{todays_paid_total: total, todays_paid_count: count}) do
    "#{Menu.format_price(total)} today · #{count} paid orders"
  end

  defp reports_body(%{period_paid_count: 0}), do: "No paid sales in the last 7 days."

  defp reports_body(%{period_paid_total: total, period_paid_count: count, period_days: days}) do
    "#{Menu.format_price(total)} last #{days} days · #{count} paid orders"
  end

  defp cash_today(%{by_via: by_via}) when is_map(by_via),
    do: Shifts.cash_sales_total(%{by_via: by_via})

  defp cash_today(_), do: Decimal.new("0")

  defp drawer_summary(false, _, _, _), do: nil
  defp drawer_summary(true, nil, nil, _), do: nil

  defp drawer_summary(true, shop_open, close, breakdown) do
    opening =
      cond do
        close && close.opening_cash -> close.opening_cash
        shop_open && shop_open.opening_cash -> shop_open.opening_cash
        true -> Decimal.new("0")
      end

    cash_outs = CashOuts.total_for_shop_date(Orders.shop_date_today())

    cash_sales =
      if close do
        Shifts.cash_sales_total(close)
      else
        Shifts.cash_sales_total(breakdown)
      end

    expected =
      if close && close.expected_cash do
        close.expected_cash
      else
        Shifts.expected_drawer_cash(opening, cash_sales, cash_outs)
      end

    %{
      sealed?: not is_nil(close),
      opening: opening,
      cash_sales: cash_sales,
      cash_outs: cash_outs,
      expected: expected,
      counted: close && close.counted_cash,
      variance: close && close.variance
    }
  end

  defp variance_line(nil), do: "—"

  defp variance_line(%Decimal{} = variance) do
    abs = Decimal.abs(variance)

    case Decimal.compare(variance, 0) do
      :eq -> "Even"
      :gt -> "Over #{Menu.format_price(abs)}"
      :lt -> "Short #{Menu.format_price(abs)}"
    end
  end

  defp variance_line(_), do: "—"

  defp orders_body(overview) do
    "#{overview.received_count} new · #{overview.preparing_count} preparing · #{overview.unpaid_active_count} unpaid"
  end

  defp printer_action_note(:ok, label), do: "#{label} OK"
  defp printer_action_note(:disabled, label), do: "#{label} skipped (printer disabled)"
  defp printer_action_note({:error, reason}, label), do: "#{label} failed (#{inspect(reason)})"
end

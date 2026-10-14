defmodule EspresoWeb.StaffHomeLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.CashOuts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Printer
  alias Espreso.Shifts
  alias Espreso.StaffShifts
  alias Espreso.Tenancy
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

  def handle_event("owner_chart_range", %{"range" => range}, socket) do
    if socket.assigns[:owner_dashboard?] do
      range = owner_chart_range(range)

      chart = owner_sales_chart(range)

      {:noreply,
       socket
       |> assign(:chart_range, range)
       |> assign(:sales_chart, chart)
       |> assign(:sales_trend, owner_trend_model(chart))}
    else
      {:noreply, socket}
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
      <main
        class={[
          "staff-home-main dashboard-page dashboard-page--sales",
          @owner_dashboard? && "owner-dash-main"
        ]}
        id="staff-home-desk"
      >
        <header class="dashboard-head" id="staff-home-identity">
          <div class="dashboard-head-copy">
            <p class="dashboard-kicker">{User.role_label(@current_user.role)}</p>
            <h1 class="dashboard-heading text-slate-900" id="staff-home-greeting">{@greeting}</h1>
            <p class="staff-home-lede dashboard-lede">
              Here's what's happening at your coffee shop today.
            </p>
            <p
              class={["dashboard-shop-line", shop_line_class(@shop_day_status)]}
              id="staff-home-shop-line"
            >
              <span class="dashboard-status-dot" aria-hidden="true"></span>
              <span>{Calendar.strftime(@shop_date, "%a %b %d")}</span>
              <span aria-hidden="true">·</span>
              <span>{shop_day_status_label(@shop_day_status)}</span>
            </p>
          </div>
        </header>

        <section :if={@shop_open_prompt?} class="staff-home-shop-open" id="staff-home-shop-open">
          <p class="staff-home-shop-open-title">Opening cash required</p>
          <p class="staff-home-shop-open-body">
            Count the drawer once before selling. POS and orders stay locked until this is recorded.
          </p>
        </section>

        <.shop_day_sales_banner
          :if={!@shop_open_prompt?}
          status={@shop_day_status}
          id="staff-home-shop-closed"
          show_open_link={false}
        />

        <section
          class={[
            "mb-6 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4",
            @owner_dashboard? && "owner-kpi-grid"
          ]}
          id="staff-home-kpis"
          aria-label="Key numbers"
        >
          <%= if @money? do %>
            <article class="staff-kpi-float" id="dashboard-panel-sales">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-banknotes" class="h-5 w-5 text-[#394331]" />
                <span class={["text-xs font-medium", sales_delta_class(@sales_delta)]}>
                  {@sales_delta.short}
                </span>
              </div>
              <strong class="mt-4 block text-[1.65rem] font-semibold tracking-tight text-slate-900">
                {peso_kpi(@sales.todays_paid_total)}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Total Sales Today</p>
              <p class="mt-0.5 text-xs text-slate-400">vs yesterday</p>
            </article>
            <article class="staff-kpi-float" id="dashboard-kpi-tickets">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-clipboard-document-list" class="h-5 w-5 text-[#394331]" />
                <span class={["text-xs font-medium", sales_delta_class(@orders_delta)]}>
                  {@orders_delta.short}
                </span>
              </div>
              <strong class="mt-4 block text-[1.65rem] font-semibold tracking-tight text-slate-900">
                {@sales.todays_paid_count}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Orders Completed</p>
              <p class="mt-0.5 text-xs text-slate-400">vs yesterday</p>
            </article>
            <article class="staff-kpi-float" id="dashboard-panel-top-item">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-shopping-bag" class="h-5 w-5 text-[#394331]" />
                <span class="text-xs font-medium text-[#3d6b45]">
                  {top_seller_badge(@top_seller)}
                </span>
              </div>
              <strong class="mt-4 block truncate text-[1.35rem] font-semibold tracking-tight text-slate-900">
                {top_seller_name(@top_seller)}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Top-selling item</p>
              <p class="mt-0.5 text-xs text-slate-400">today</p>
            </article>
            <article :if={@owner_dashboard?} class="staff-kpi-float" id="dashboard-kpi-staff-shift">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-user-group" class="h-5 w-5 text-[#394331]" />
                <span class="text-xs font-medium text-[#3d6b45]">
                  {staff_on_shift_badge(@staff_on_shift)}
                </span>
              </div>
              <strong class="mt-4 block text-[1.65rem] font-semibold tracking-tight text-slate-900">
                {@staff_on_shift}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Active Staff on Shift</p>
              <p class="mt-0.5 text-xs text-slate-400">current shift</p>
            </article>
            <article :if={not @owner_dashboard?} class="staff-kpi-float" id="dashboard-kpi-drawer">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-wallet" class="h-5 w-5 text-[#394331]" />
              </div>
              <strong class="mt-4 block text-[1.65rem] font-semibold tracking-tight text-slate-900">
                {peso_kpi(drawer_cash(@drawer_summary))}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Cash in drawer</p>
              <p class="mt-0.5 text-xs text-slate-400">{drawer_kpi_hint(@drawer_summary)}</p>
            </article>
          <% else %>
            <article class="staff-kpi-float" id="staff-home-kpi-active">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-user-group" class="h-5 w-5 text-[#394331]" />
              </div>
              <strong class="mt-4 block text-[1.65rem] font-semibold tracking-tight text-slate-900">
                {@overview.active_count}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Active</p>
              <p class="mt-0.5 text-xs text-slate-400">Received + preparing</p>
            </article>
            <article class="staff-kpi-float" id="staff-home-kpi-unpaid">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-[#394331]" />
              </div>
              <strong class="mt-4 block text-[1.65rem] font-semibold tracking-tight text-slate-900">
                {@overview.unpaid_active_count}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Unpaid</p>
              <p class="mt-0.5 text-xs text-slate-400">Still open on the board</p>
            </article>
            <article class="staff-kpi-float" id="staff-home-kpi-preparing">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-clock" class="h-5 w-5 text-[#394331]" />
              </div>
              <strong class="mt-4 block text-[1.65rem] font-semibold tracking-tight text-slate-900">
                {@overview.preparing_count}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Preparing</p>
              <p class="mt-0.5 text-xs text-slate-400">In progress</p>
            </article>
            <article class="staff-kpi-float" id="staff-home-kpi-tickets">
              <div class="flex items-start justify-between gap-3">
                <.icon name="hero-document-text" class="h-5 w-5 text-[#394331]" />
              </div>
              <strong class="mt-4 block text-[1.65rem] font-semibold tracking-tight text-slate-900">
                {@overview.todays_count}
              </strong>
              <p class="mt-1 text-sm font-medium text-slate-800">Tickets</p>
              <p class="mt-0.5 text-xs text-slate-400">Placed this shop day</p>
            </article>
          <% end %>
        </section>

        <section
          :if={@owner_dashboard?}
          class="owner-trends"
          id="owner-sales-trends"
          aria-labelledby="owner-trends-heading"
          data-range={@chart_range}
          phx-hook="OwnerSalesTrend"
        >
          <header class="owner-trends-head">
            <h2 class="owner-trends-title" id="owner-trends-heading">Sales Trends</h2>
            <div class="owner-trends-ranges" role="tablist" aria-label="Sales range">
              <button
                :for={range <- [:daily, :weekly, :monthly]}
                type="button"
                id={"owner-chart-#{range}"}
                class={["owner-trends-range", @chart_range == range && "is-active"]}
                phx-click="owner_chart_range"
                phx-value-range={range}
                role="tab"
                aria-selected={@chart_range == range}
              >
                {owner_range_label(range)}
              </button>
            </div>
          </header>
          <div class="owner-trends-body">
            <ul class="owner-trends-y" aria-hidden="true">
              <li :for={tick <- @sales_trend.y_ticks}>{tick.label}</li>
            </ul>
            <div class="owner-trends-plot">
              <div class="owner-trends-svg-wrap">
                <svg
                  class="owner-trends-svg"
                  id={"owner-trends-plot-#{@chart_range}"}
                  viewBox="0 0 100 100"
                  preserveAspectRatio="none"
                  role="img"
                  aria-label="Paid sales trend"
                >
                  <g class="owner-trends-grid" aria-hidden="true">
                    <line :for={tick <- @sales_trend.y_ticks} x1="0" x2="100" y1={tick.y} y2={tick.y} />
                  </g>
                  <path
                    :if={@sales_trend.fill_path != ""}
                    id="owner-trends-fill"
                    class="owner-trends-fill"
                    d={@sales_trend.fill_path}
                  />
                  <path
                    :if={@sales_trend.path != ""}
                    id="owner-trends-line"
                    class="owner-trends-line"
                    d={@sales_trend.path}
                    fill="none"
                    stroke-linejoin="round"
                    stroke-linecap="round"
                  />
                </svg>
                <span
                  :for={{point, index} <- Enum.with_index(@sales_trend.points)}
                  id={"owner-trend-dot-#{index}"}
                  class="owner-trends-dot"
                  style={"left: #{point.x}%; top: #{point.y}%; --i: #{index}"}
                >
                </span>
              </div>
              <ol class="owner-trends-x">
                <li
                  :for={{point, index} <- Enum.with_index(@sales_trend.points)}
                  id={"owner-trend-x-#{index}"}
                  data-date={point.date}
                >
                  {point.label}
                </li>
              </ol>
            </div>
          </div>
        </section>

        <section
          :if={@primary != [] and not @owner_dashboard?}
          class={["dashboard-launch", length(@primary) == 1 && "is-single"]}
          aria-label="Primary action"
        >
          <.link
            :for={item <- @primary}
            navigate={item.path}
            class={["dashboard-launch-btn", item[:class]]}
            id={"staff-home-#{item.id}"}
          >
            <span :if={item[:icon]} class="dashboard-launch-mark" aria-hidden="true">
              <.icon name={item.icon} class="staff-home-card-glyph" />
            </span>
            <span class="dashboard-launch-copy">
              <span class="dashboard-launch-title">{item.title}</span>
              <span class="dashboard-launch-body">{item.body}</span>
            </span>
          </.link>
        </section>

        <div :if={@money? and @owner_dashboard?} class="owner-home-boards" id="owner-home-boards">
          <div class="owner-board-stack">
            <.payment_methods_card via_rows={@via_rows} />
            <.drawer_card drawer_summary={@drawer_summary} shift_close={@shift_close} />
          </div>
          <div class="owner-board-stack">
            <.sales_by_item_card popular_products={@popular_products} />
            <.payout_card item_payouts={@item_payouts} />
          </div>
        </div>

        <div :if={@money? and not @owner_dashboard?} class="dashboard-split">
          <.drawer_card drawer_summary={@drawer_summary} shift_close={@shift_close} />
          <.payment_methods_card via_rows={@via_rows} />
          <.sales_by_item_card popular_products={@popular_products} />
        </div>

        <.payout_card :if={@money? and not @owner_dashboard?} item_payouts={@item_payouts} />

        <section
          :if={not @owner_dashboard? and (@launch_tools != [] or @shift_tools != [])}
          class="staff-home-desk-tools"
          aria-label="Now"
        >
          <div class="staff-home-secondary">
            <.link
              :for={item <- @launch_tools}
              navigate={item.path}
              class={["staff-home-tool-link", item[:class]]}
              id={"staff-home-#{item.id}"}
            >
              <span :if={item[:icon]} class="staff-home-tool-icon" aria-hidden="true">
                <.icon name={item.icon} class="staff-home-card-glyph" />
              </span>
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
              <span :if={item[:icon]} class="staff-home-tool-icon" aria-hidden="true">
                <.icon name={item.icon} class="staff-home-card-glyph" />
              </span>
              <span class="staff-home-tool-label">{item.title}</span>
              <span class="staff-home-tool-body">{item.body}</span>
            </.link>
          </div>
        </section>

        <section
          :if={@printer_on_home? and not @owner_dashboard?}
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
    owner_dashboard? = user.role == "owner"

    breakdown = if money?, do: Orders.todays_paid_breakdown(), else: nil
    sales = if breakdown, do: Orders.sales_overview(), else: nil
    shop_date = Orders.shop_date_today()

    {sales_delta, orders_delta} =
      if money? do
        yesterday = Orders.paid_breakdown_for_shop_date(Date.add(shop_date, -1))

        {vs_yesterday(sales.todays_paid_total, yesterday.total),
         vs_yesterday(sales.todays_paid_count, yesterday.count)}
      else
        {nil, nil}
      end

    shop_open = Shifts.get_todays_open()
    close = Shifts.get_todays_close()
    shift_close = if money?, do: close, else: nil
    shop_day_status = Shifts.shop_day_status()

    shop_open_prompt? =
      Shifts.can_access_open?(user) and is_nil(shop_open) and is_nil(close)

    ranked = if money?, do: Orders.popular_products(), else: []
    top_seller = List.first(ranked)
    popular = if money?, do: Orders.paid_item_sales(limit: 8), else: []
    payouts = if money?, do: Orders.paid_item_payouts(), else: []

    tools = desk_tools(user)
    {shift_tools, launch_tools} = Enum.split_with(tools, &(&1.id == "my-shifts"))
    chart_range = socket.assigns[:chart_range] || :daily
    sales_chart = if owner_dashboard?, do: owner_sales_chart(chart_range), else: []

    socket
    |> assign(:overview, overview)
    |> assign(:owner_dashboard?, owner_dashboard?)
    |> assign(:staff_on_shift, if(owner_dashboard?, do: staff_on_shift_count(), else: 0))
    |> assign(:chart_range, if(owner_dashboard?, do: chart_range, else: :daily))
    |> assign(:sales_chart, sales_chart)
    |> assign(:sales_trend, owner_trend_model(sales_chart))
    |> assign(:money?, money?)
    |> assign(:sales, sales)
    |> assign(:sales_delta, sales_delta)
    |> assign(:orders_delta, orders_delta)
    |> assign(:breakdown, breakdown)
    |> assign(:top_seller, top_seller)
    |> assign(:via_rows, if(breakdown, do: Orders.paid_via_rows(breakdown), else: []))
    |> assign(:shift_close, shift_close)
    |> assign(:shop_open, shop_open)
    |> assign(:shop_open_prompt?, shop_open_prompt?)
    |> assign(:shop_day_status, shop_day_status)
    |> assign(:shop_date, shop_date)
    |> assign(:drawer_summary, drawer_summary(money?, shop_open, close, breakdown))
    |> assign(:today_visible?, money?)
    |> assign(:popular_products, popular)
    |> assign(:item_payouts, payouts)
    |> assign(:printer_on_home?, money? and Printer.enabled?())
    |> assign(:greeting, staff_greeting(user))
    |> assign(:primary, primary_tiles(user, overview, shop_day_status))
    |> assign(:launch_tools, launch_tools)
    |> assign(:shift_tools, shift_tools)
  end

  defp staff_greeting(%User{name: name}) do
    display_name =
      name
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "there"
        value -> value
      end

    "#{daypart_greeting()}, #{display_name}!"
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

  defp primary_tiles(%User{} = user, overview, shop_day_status) do
    orders_tile = %{
      id: "orders",
      eyebrow: "Board",
      title: "Orders",
      body: orders_body(overview),
      path: ~p"/orders",
      cta: "Open Orders →",
      class: "staff-home-pos-cta--secondary",
      icon: "hero-clipboard-document-list",
      show?: Authorization.can?(user, :orders)
    }

    cond do
      shop_day_status == :not_open and Shifts.can_access_open?(user) ->
        [
          %{
            id: "open-shop",
            eyebrow: "Shift",
            title: "Enter opening cash",
            body: "Count the drawer before selling",
            path: ~p"/staff/open",
            cta: "Enter opening cash →",
            class: "staff-home-pos-cta--primary",
            icon: "hero-lock-open",
            show?: true
          }
        ]

      shop_day_status == :closed ->
        [
          %{
            id: "reports",
            eyebrow: "Day",
            title: "View reports",
            body: "Shop day is closed · no new sales",
            path: ~p"/staff/reports",
            cta: "Reports →",
            class: "staff-home-pos-cta--primary",
            icon: "hero-chart-bar",
            show?: manager_or_owner?(user) and Authorization.can?(user, :reports)
          },
          %{
            orders_tile
            | class:
                if(manager_or_owner?(user),
                  do: "staff-home-pos-cta--secondary",
                  else: "staff-home-pos-cta--primary"
                )
          }
        ]
        |> Enum.filter(& &1.show?)

      true ->
        [
          %{
            id: "pos",
            eyebrow: "Counter",
            title: "Open POS",
            body: "Take walk-in orders and payment",
            path: ~p"/pos",
            cta: "Open POS →",
            class: "staff-home-pos-cta--primary",
            icon: "hero-plus",
            show?: Authorization.can?(user, :orders)
          },
          orders_tile
        ]
        |> Enum.filter(& &1.show?)
    end
  end

  defp desk_tools(%User{} = user) do
    [
      %{
        id: "my-shifts",
        title: "My shifts",
        body: "Time In, Time Out & sales",
        path: ~p"/staff/shifts",
        count: nil,
        show?: user.role == "barista",
        class: "staff-home-tool-link--shifts",
        icon: "hero-calendar-days"
      }
    ]
    |> Enum.filter(& &1.show?)
  end

  defp manager_or_owner?(%User{role: role}), do: role in ["manager", "owner"]
  defp manager_or_owner?(_), do: false

  @donut_colors ["#394331", "#f85020", "#c4a574", "#6b7f5a", "#8b6914"]
  @via_color_index %{"cash" => 0, "gcash" => 1, "maya" => 2, "counter" => 3, "paymongo" => 4}

  attr :via_rows, :list, required: true

  defp payment_methods_card(assigns) do
    ~H"""
    <section
      id="staff-home-paid-breakdown"
      class="staff-home-card dashboard-donut-panel"
      aria-label="Payment methods"
    >
      <span class="staff-home-card-title">Payment methods</span>
      <p :if={payment_mix_empty?(@via_rows)} class="dashboard-kpi-hint" id="staff-home-mix-empty">
        No payments yet today
      </p>
      <div :if={not payment_mix_empty?(@via_rows)} class="dashboard-donut-row">
        <div
          class="dashboard-donut"
          style={donut_style(active_via_rows(@via_rows))}
          aria-hidden="true"
        >
        </div>
        <ul class="staff-paid-breakdown">
          <li
            :for={row <- active_via_rows(@via_rows)}
            class="staff-paid-breakdown-row"
            style={"--mix-color: #{mix_color_for(row)}"}
          >
            <span class="staff-paid-breakdown-swatch" aria-hidden="true"></span>
            <span class="staff-paid-breakdown-label">{row.label}</span>
            <span class="staff-paid-breakdown-total">{peso(row.total)}</span>
            <span class="staff-paid-breakdown-count">{row.count}</span>
          </li>
        </ul>
      </div>
      <ul :if={payment_mix_empty?(@via_rows)} class="staff-paid-breakdown owner-mix-empty-list">
        <li
          :for={row <- @via_rows}
          class="staff-paid-breakdown-row"
          style={"--mix-color: #{mix_color_for(row)}"}
        >
          <span class="staff-paid-breakdown-swatch" aria-hidden="true"></span>
          <span class="staff-paid-breakdown-label">{row.label}</span>
          <span class="staff-paid-breakdown-total">{peso(row.total)}</span>
          <span class="staff-paid-breakdown-count">{row.count}</span>
        </li>
      </ul>
    </section>
    """
  end

  attr :drawer_summary, :any, default: nil
  attr :shift_close, :any, default: nil

  defp drawer_card(assigns) do
    ~H"""
    <section
      :if={@drawer_summary || @shift_close}
      class="staff-home-card staff-home-drawer-panel"
      id="staff-home-today"
      aria-label="Drawer"
    >
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
            <strong>{peso(@drawer_summary.opening)}</strong>
          </li>
          <li>
            <span>Cash sales</span>
            <strong>{peso(@drawer_summary.cash_sales)}</strong>
          </li>
          <li>
            <span>Cash outs</span>
            <strong>{peso(@drawer_summary.cash_outs)}</strong>
          </li>
          <li>
            <span>Expected</span>
            <strong>{peso(@drawer_summary.expected)}</strong>
          </li>
          <li :if={@drawer_summary.sealed?}>
            <span>Counted</span>
            <strong>{peso(@drawer_summary.counted)}</strong>
          </li>
          <li :if={@drawer_summary.sealed?} id="staff-home-drawer-variance">
            <span>Variance</span>
            <strong>{variance_line(@drawer_summary.variance)}</strong>
          </li>
        </ul>
        <.link navigate={~p"/staff/close"} class="staff-home-drawer-link" id="staff-home-drawer-close">
          {if(@drawer_summary.sealed?, do: "View close", else: "Close shift")}
        </.link>
      </div>
    </section>
    """
  end

  attr :popular_products, :list, required: true

  defp sales_by_item_card(assigns) do
    ~H"""
    <section
      class="staff-home-card dashboard-card-metric-panel"
      id="dashboard-panel-popular-products"
      aria-label="Sales by item"
    >
      <span class="staff-home-card-title">Sales by item</span>
      <p :if={@popular_products == []} class="staff-home-card-body">
        No paid items yet.
      </p>
      <ul :if={@popular_products != []} class="dashboard-popular-list">
        <li :for={item <- @popular_products}>
          <span class="dashboard-popular-copy">
            <span class="dashboard-popular-name">{item.name}</span>
            <span :if={item_owner(item)} class="dashboard-popular-owner">
              {item_owner(item)}
            </span>
          </span>
          <span class="dashboard-popular-qty">{item_qty(item.quantity)}</span>
          <span class="dashboard-popular-total">{peso(item.total)}</span>
        </li>
      </ul>
    </section>
    """
  end

  attr :item_payouts, :list, required: true

  defp payout_card(assigns) do
    ~H"""
    <section
      class="staff-home-card dashboard-card-metric-panel"
      id="dashboard-panel-payout"
      aria-label="Payout today"
    >
      <span class="staff-home-card-title">Payout today</span>
      <p :if={@item_payouts == []} class="staff-home-card-body">
        No paid items yet.
      </p>
      <ul :if={@item_payouts != []} class="dashboard-popular-list">
        <li :for={row <- @item_payouts}>
          <span class="dashboard-popular-copy">
            <span class="dashboard-popular-name">{payout_owner(row)}</span>
          </span>
          <span class="dashboard-popular-qty">{item_qty(row.quantity)}</span>
          <span class="dashboard-popular-total">{peso(row.total)}</span>
        </li>
      </ul>
    </section>
    """
  end

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
        |> Enum.reduce({[], 0.0}, fn row, {acc, start} ->
          pct =
            row.total
            |> Decimal.div(total)
            |> Decimal.mult(Decimal.new(100))
            |> Decimal.to_float()

          color = mix_color_for(row)
          stop = start + pct
          {acc ++ ["#{color} #{start}% #{stop}%"], stop}
        end)

      "background: conic-gradient(#{Enum.join(stops, ", ")})"
    end
  end

  defp donut_style(_), do: "background: #fff"

  defp mix_color(index) when is_integer(index) do
    Enum.at(@donut_colors, rem(index, length(@donut_colors)))
  end

  defp mix_color_for(%{via: via}) when is_binary(via) do
    mix_color(Map.get(@via_color_index, via, 0))
  end

  defp mix_color_for(_), do: mix_color(0)

  defp active_via_rows(rows) when is_list(rows) do
    Enum.filter(rows, fn row ->
      Decimal.compare(row.total || Decimal.new("0"), 0) == :gt
    end)
  end

  defp active_via_rows(_), do: []

  defp shop_day_status_label(:open), do: "Open"
  defp shop_day_status_label(:closed), do: "Closed"
  defp shop_day_status_label(_), do: "Not open"

  defp shop_line_class(:open), do: "is-open"
  defp shop_line_class(:closed), do: "is-closed"
  defp shop_line_class(_), do: "is-pending"

  defp peso(amount) do
    amount
    |> Menu.format_price()
    |> String.replace(~r/^P(?=[\d,])/, "₱")
  end

  defp vs_yesterday(today, yesterday) do
    today = decimalize_metric(today)
    yesterday = decimalize_metric(yesterday)

    cond do
      Decimal.compare(today, 0) != :gt and Decimal.compare(yesterday, 0) != :gt ->
        %{tone: :muted, short: "Even", label: "vs yesterday"}

      Decimal.compare(yesterday, 0) != :gt ->
        %{tone: :up, short: "Up", label: "vs yesterday"}

      true ->
        diff = Decimal.sub(today, yesterday)

        pct =
          diff
          |> Decimal.div(yesterday)
          |> Decimal.mult(100)
          |> Decimal.round(0)
          |> Decimal.to_integer()

        cond do
          pct > 0 -> %{tone: :up, short: "+#{pct}%", label: "vs yesterday"}
          pct < 0 -> %{tone: :down, short: "#{pct}%", label: "vs yesterday"}
          true -> %{tone: :muted, short: "Even", label: "vs yesterday"}
        end
    end
  end

  defp decimalize_metric(%Decimal{} = value), do: value
  defp decimalize_metric(value) when is_integer(value), do: Decimal.new(value)
  defp decimalize_metric(value) when is_float(value), do: Decimal.from_float(value)
  defp decimalize_metric(_), do: Decimal.new("0")

  defp owner_chart_range("weekly"), do: :weekly
  defp owner_chart_range("monthly"), do: :monthly
  defp owner_chart_range(_), do: :daily

  defp owner_range_label(:weekly), do: "Weekly"
  defp owner_range_label(:monthly), do: "Monthly"
  defp owner_range_label(_), do: "Daily"

  defp owner_sales_chart(:weekly), do: group_sales_chart(Orders.paid_sales_chart(28), :week)
  defp owner_sales_chart(:monthly), do: group_sales_chart(Orders.paid_sales_chart(90), :month)
  defp owner_sales_chart(_), do: Orders.paid_sales_chart(7)

  defp group_sales_chart(points, :week) do
    points
    |> Enum.group_by(&Date.beginning_of_week(&1.date, :monday))
    |> chart_groups(&Calendar.strftime(&1, "%b %d"))
  end

  defp group_sales_chart(points, :month) do
    points
    |> Enum.group_by(&Date.beginning_of_month(&1.date))
    |> chart_groups(&Calendar.strftime(&1, "%b"))
  end

  defp chart_groups(grouped, label_fun) do
    rows =
      grouped
      |> Enum.sort_by(fn {key, _} -> key end, Date)
      |> Enum.map(fn {key, items} ->
        amount =
          Enum.reduce(items, Decimal.new("0"), fn item, acc ->
            Decimal.add(acc, item.amount || Decimal.new("0"))
          end)

        %{date: key, label: label_fun.(key), amount: amount}
      end)

    max_amount =
      Enum.reduce(rows, Decimal.new("0"), fn row, acc -> Decimal.max(acc, row.amount) end)

    Enum.map(rows, fn row ->
      Map.put(row, :pct, chart_pct(row.amount, max_amount))
    end)
  end

  defp chart_pct(amount, max) do
    cond do
      Decimal.compare(max, 0) != :gt ->
        0

      Decimal.compare(amount, 0) != :gt ->
        0

      true ->
        amount
        |> Decimal.div(max)
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()
    end
  end

  @trend_pad_x 3
  @trend_pad_top 6
  @trend_pad_bot 8

  defp owner_trend_model(chart) when is_list(chart) and chart != [] do
    y_max = trend_y_max(chart)
    n = length(chart)
    plot_w = 100 - @trend_pad_x * 2
    plot_h = 100 - @trend_pad_top - @trend_pad_bot

    points =
      chart
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        amount = decimalize_metric(Map.get(point, :amount))
        t = if n == 1, do: 0.0, else: index / (n - 1)
        ratio = trend_amount_ratio(amount, y_max)

        %{
          x: trend_num(@trend_pad_x + t * plot_w),
          y: trend_num(@trend_pad_top + (1.0 - ratio) * plot_h),
          label: point.label,
          date: Map.get(point, :date),
          amount: amount
        }
      end)

    y_ticks =
      Enum.map(0..2, fn step ->
        %{
          y: trend_num(@trend_pad_top + step / 2 * plot_h),
          label: peso_axis(y_max * (2 - step) / 2)
        }
      end)

    line = trend_smooth_path(points)
    %{path: line, fill_path: trend_fill_path(points, line), points: points, y_ticks: y_ticks}
  end

  defp owner_trend_model(_) do
    owner_trend_model([%{label: "", amount: Decimal.new("0")}])
  end

  defp trend_y_max(chart) do
    max_int =
      chart
      |> Enum.reduce(Decimal.new("0"), fn point, acc ->
        Decimal.max(acc, decimalize_metric(Map.get(point, :amount)))
      end)
      |> Decimal.round(0, :ceiling)
      |> Decimal.to_integer()

    nice_ceiling(max_int)
  end

  defp nice_ceiling(n) when is_integer(n) and n <= 0, do: 4000

  defp nice_ceiling(n) when is_integer(n) do
    exp = n |> :math.log10() |> :math.floor()
    base = :math.pow(10, exp)
    f = n / base

    nice_f =
      cond do
        f <= 1 -> 1
        f <= 2 -> 2
        f <= 5 -> 5
        true -> 10
      end

    round(nice_f * base)
  end

  defp trend_amount_ratio(amount, y_max) when y_max > 0 do
    amount
    |> Decimal.to_float()
    |> Kernel./(y_max)
    |> min(1.0)
    |> max(0.0)
  end

  defp trend_amount_ratio(_, _), do: 0.0

  defp trend_fill_path(points, line) when is_binary(line) and line != "" and is_list(points) do
    case points do
      [first | rest] when rest != [] ->
        last = List.last(rest)
        "#{line} L #{last.x} 100 L #{first.x} 100 Z"

      _ ->
        ""
    end
  end

  defp trend_fill_path(_, _), do: ""

  defp trend_smooth_path([]), do: ""
  defp trend_smooth_path([_one]), do: ""

  defp trend_smooth_path(points) do
    coords = Enum.map(points, &{trend_float(&1.x), trend_float(&1.y)})
    [{x0, y0} | _] = coords
    n = length(coords)
    plot_top = @trend_pad_top * 1.0
    plot_bottom = (100 - @trend_pad_bot) * 1.0

    rest =
      coords
      |> Enum.with_index()
      |> Enum.drop(-1)
      |> Enum.map_join(fn {{x1, y1}, i} ->
        {x0p, y0p} = Enum.at(coords, max(i - 1, 0))
        {x2, y2} = Enum.at(coords, i + 1)
        {x3, y3} = Enum.at(coords, min(i + 2, n - 1))
        c1x = x1 + (x2 - x0p) / 6
        c1y = trend_clamp(y1 + (y2 - y0p) / 6, plot_top, plot_bottom)
        c2x = x2 - (x3 - x1) / 6
        c2y = trend_clamp(y2 - (y3 - y1) / 6, plot_top, plot_bottom)

        " C #{trend_num(c1x)} #{trend_num(c1y)}, #{trend_num(c2x)} #{trend_num(c2y)}, #{trend_num(x2)} #{trend_num(y2)}"
      end)

    "M #{trend_num(x0)} #{trend_num(y0)}" <> rest
  end

  defp trend_clamp(value, min_v, max_v), do: value |> max(min_v) |> min(max_v)

  defp peso_axis(value) when is_float(value), do: peso_axis(round(value))
  defp peso_axis(0), do: "₱0"

  defp peso_axis(n) when is_integer(n) and n >= 1000 do
    k = n / 1000

    label =
      if k == trunc(k) do
        Integer.to_string(trunc(k))
      else
        :erlang.float_to_binary(k, decimals: 1)
      end

    "₱#{label}K"
  end

  defp peso_axis(n) when is_integer(n), do: "₱#{n}"
  defp peso_axis(_), do: "₱0"

  defp trend_num(n) when is_integer(n), do: Integer.to_string(n)

  defp trend_num(n) when is_float(n) do
    n
    |> Float.round(2)
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp trend_float(n) when is_binary(n) do
    case Float.parse(n) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp trend_float(n) when is_number(n), do: n / 1
  defp trend_float(_), do: 0.0

  defp staff_on_shift_count do
    branch_id = Tenancy.current_branch_id()

    StaffShifts.list_open_shifts()
    |> Enum.count(fn shift ->
      is_nil(branch_id) or shift.branch_id == branch_id
    end)
  end

  defp staff_on_shift_badge(0), do: "None in"
  defp staff_on_shift_badge(_count), do: "On shift"

  defp sales_delta_class(%{tone: :up}), do: "text-[#3d6b45]"
  defp sales_delta_class(%{tone: :down}), do: "text-rose-500"
  defp sales_delta_class(_), do: "text-slate-400"

  defp top_seller_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp top_seller_name(_), do: "No sales yet"

  defp top_seller_badge(%{quantity: qty}), do: "#{top_seller_qty(qty)} sold"
  defp top_seller_badge(_), do: "0 sold"

  defp top_seller_qty(qty) when is_integer(qty), do: qty
  defp top_seller_qty(%Decimal{} = qty), do: qty |> Decimal.round(0) |> Decimal.to_integer()
  defp top_seller_qty(_), do: 0

  defp drawer_cash(%{expected: expected}), do: expected
  defp drawer_cash(_), do: Decimal.new("0")

  defp drawer_kpi_hint(%{opening: opening}) do
    "Includes #{peso_kpi(opening)} base"
  end

  defp drawer_kpi_hint(_), do: "Includes ₱0.00 base"

  defp peso_kpi(amount) do
    rounded =
      (amount || Decimal.new("0"))
      |> Decimal.round(2)

    {sign, abs} =
      if Decimal.compare(rounded, 0) == :lt do
        {"-", Decimal.abs(rounded)}
      else
        {"", rounded}
      end

    string = Decimal.to_string(abs, :normal)

    {int, frac} =
      case String.split(string, ".", parts: 2) do
        [whole] -> {whole, "00"}
        [whole, rest] -> {whole, String.pad_trailing(String.slice(rest, 0, 2), 2, "0")}
      end

    "#{sign}₱#{thousands(int)}.#{frac}"
  end

  defp thousands(int) when is_binary(int) do
    Regex.replace(~r/\B(?=(\d{3})+(?!\d))/, int, ",")
  end

  defp payment_mix_empty?(rows) when is_list(rows) do
    Enum.all?(rows, fn row ->
      total = row.total || Decimal.new("0")
      Decimal.compare(total, 0) != :gt
    end)
  end

  defp payment_mix_empty?(_), do: true

  defp item_qty(qty) when is_integer(qty), do: qty
  defp item_qty(%Decimal{} = qty), do: qty |> Decimal.round(0) |> Decimal.to_integer()
  defp item_qty(_), do: 0

  defp item_owner(%{item_owner: owner}) when is_binary(owner) and owner != "" do
    case String.downcase(owner) do
      "manager" -> "Manager"
      _ -> owner
    end
  end

  defp item_owner(_), do: nil

  defp payout_owner(row), do: item_owner(row) || "Café"

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
      :gt -> "Over #{peso(abs)}"
      :lt -> "Short #{peso(abs)}"
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

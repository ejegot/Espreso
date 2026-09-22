defmodule EspresoWeb.StaffHomeLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
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
      <main
        class={[
          "staff-home-main staff-home-hub staff-home-desk",
          @today_visible? && "staff-home-desk--money",
          not @today_visible? && "staff-home-desk--counter"
        ]}
        id="staff-home-desk"
      >
        <header class="staff-home-identity" id="staff-home-identity">
          <p class="staff-home-greeting" id="staff-home-greeting">{@greeting}</p>
          <p class="staff-home-identity-role">{User.role_label(@current_user.role)}</p>
        </header>

        <section :if={@shop_open_prompt?} class="staff-home-shop-open" id="staff-home-shop-open">
          <p class="staff-home-shop-open-title">Opening cash not recorded</p>
          <p class="staff-home-shop-open-body">
            Opening shift: count the drawer once. Mid and close shifts skip this.
          </p>
          <.link
            navigate={~p"/staff/open"}
            class="staff-home-shop-open-action"
            id="staff-home-shop-open-link"
          >
            Enter opening cash
          </.link>
        </section>

        <div class={["staff-home-desk-stage", @today_visible? && "staff-home-desk-stage--split"]}>
          <section
            :if={@today_visible?}
            class="staff-home-today"
            id="staff-home-today"
            aria-label="Today"
          >
            <div class="staff-home-today-head">
              <p class="staff-home-today-eyebrow">Today</p>
              <p :if={@shift_close} class="staff-home-today-closed" id="staff-home-shift-closed">
                Closed · {Shifts.format_closed_at(@shift_close.closed_at)}
                <span :if={@shift_close.closed_by_user}>
                  by {@shift_close.closed_by_user.name}
                </span>
              </p>
            </div>

            <div class="staff-home-today-row">
              <p class="staff-home-today-total">
                {Menu.format_price(@sales.todays_paid_total)}
                <span>paid</span>
              </p>
              <p class="staff-home-today-meta">
                {@sales.todays_paid_count} paid · {@overview.active_count} active · {@overview.unpaid_active_count} unpaid
              </p>
            </div>

            <ul :if={@breakdown} class="staff-paid-breakdown" id="staff-home-paid-breakdown">
              <li :for={row <- @via_rows} class="staff-paid-breakdown-row">
                <span class="staff-paid-breakdown-label">{row.label}</span>
                <span class="staff-paid-breakdown-total">{Menu.format_price(row.total)}</span>
                <span class="staff-paid-breakdown-count">{row.count}</span>
              </li>
            </ul>
          </section>

          <section class="staff-home-primary" aria-label="Primary action">
            <.link
              :for={item <- @primary}
              navigate={item.path}
              class={["staff-home-pos-cta", item[:class]]}
              id={"staff-home-#{item.id}"}
            >
              <span class="staff-home-pos-cta-kicker">{item.eyebrow}</span>
              <span class="staff-home-pos-cta-title">{item.title}</span>
              <span class="staff-home-pos-cta-body">{item.body}</span>
              <span class="staff-home-pos-cta-action">{item.cta}</span>
            </.link>
          </section>
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

    socket
    |> assign(:overview, overview)
    |> assign(:sales, sales)
    |> assign(:breakdown, breakdown)
    |> assign(:via_rows, if(breakdown, do: Orders.paid_via_rows(breakdown), else: []))
    |> assign(:shift_close, shift_close)
    |> assign(:shop_open, shop_open)
    |> assign(:shop_open_prompt?, shop_open_prompt?)
    |> assign(:today_visible?, money?)
    |> assign(:printer_on_home?, money? and Printer.enabled?())
    |> assign(:greeting, staff_greeting(user))
    |> assign(:primary, primary_tiles(user))
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

  defp primary_tiles(%User{} = user) do
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
      }
    ]
    |> Enum.filter(& &1.show?)
  end

  defp desk_tools(%User{} = user, overview) do
    unpaid_count = Orders.count_todays_unpaid()

    [
      %{
        id: "orders",
        title: "Orders",
        body: orders_body(overview),
        path: ~p"/orders",
        count: overview.received_count,
        show?: Authorization.can?(user, :orders)
      },
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

  defp orders_body(overview) do
    "#{overview.received_count} new · #{overview.preparing_count} preparing · #{overview.unpaid_active_count} unpaid"
  end

  defp printer_action_note(:ok, label), do: "#{label} OK"
  defp printer_action_note(:disabled, label), do: "#{label} skipped (printer disabled)"
  defp printer_action_note({:error, reason}, label), do: "#{label} failed (#{inspect(reason)})"
end

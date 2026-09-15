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

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Orders.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:printer_note, nil)
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
        {:noreply, assign(socket, :printer_note, printer_action_note(map_test_result(other), "Test print"))}
    end
  end

  def handle_event("printer_open_drawer", _params, socket) do
    case Printer.dispatch_drawer() do
      {:client_dispatch, bytes} ->
        {:noreply,
         socket
         |> assign(:printer_note, "Opening kaha…")
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
         assign(socket, :printer_note, printer_action_note(map_drawer_result(other), "Open kaha"))}
    end
  end

  def handle_event("elilai_printer_result", params, socket) do
    case params do
      %{"flow" => flow, "ok" => ok} when flow in ["raw_test", "raw_drawer"] ->
        ok? = ok in [true, "true"]

        note =
          cond do
            ok? and flow == "raw_drawer" -> "Open kaha: ok"
            ok? -> "Test print: ok"
            true -> "#{if(flow == "raw_drawer", do: "Open kaha", else: "Test print")}: #{Map.get(params, "error") || "failed"}"
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

    {:noreply, assign_home_state(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:home} current_user={@current_user} page_title="Home">
      <main class="staff-home-main staff-home-hub staff-home-desk" id="staff-home-desk">
        <header class="staff-home-identity" id="staff-home-identity">
          <p class="staff-home-greeting" id="staff-home-greeting">{@greeting}</p>
          <p class="staff-home-identity-role">{User.role_label(@current_user.role)}</p>
        </header>

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

          <%= if @sales do %>
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
          <% else %>
            <div class="staff-home-today-row staff-home-today-row--compact">
              <p class="staff-home-today-meta" id="staff-home-today-barista">
                {@overview.received_count} new · {@overview.preparing_count} preparing · {@overview.unpaid_active_count} unpaid · {@overview.todays_count} orders today
              </p>
            </div>
          <% end %>
        </section>

        <section
          :for={group <- @shortcut_groups}
          class="staff-home-shortcut-group"
          aria-label={group.title}
        >
          <p class="staff-home-shortcut-eyebrow">{group.title}</p>
          <div class="staff-home-secondary">
            <.link
              :for={item <- group.items}
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
        </section>

        <section
          :if={@printer_enabled?}
          class="staff-home-printer"
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
              Open kaha
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

  defp assign_home_state(socket) do
    user = socket.assigns.current_user
    overview = Orders.dashboard_overview()
    money? = manager_or_owner?(user)

    breakdown = if money?, do: Orders.todays_paid_breakdown(), else: nil
    sales = if breakdown, do: Orders.sales_overview(), else: nil
    shift_close = if money?, do: Shifts.get_todays_close(), else: nil

    socket
    |> assign(:overview, overview)
    |> assign(:sales, sales)
    |> assign(:breakdown, breakdown)
    |> assign(:via_rows, if(breakdown, do: Orders.paid_via_rows(breakdown), else: []))
    |> assign(:shift_close, shift_close)
    |> assign(:today_visible?, today_visible?(overview, sales, shift_close))
    |> assign(:printer_enabled?, Printer.enabled?())
    |> assign(:greeting, staff_greeting(user))
    |> assign(:primary, primary_tiles(user, overview))
    |> assign(:shortcut_groups, shortcut_groups(user, shift_close))
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

  defp today_visible?(_overview, _sales, shift_close) when not is_nil(shift_close), do: true

  defp today_visible?(overview, sales, nil) do
    cond do
      match?(%{todays_paid_count: count} when count > 0, sales) -> true
      match?(%{active_count: count} when count > 0, overview) -> true
      match?(%{unpaid_active_count: count} when count > 0, overview) -> true
      match?(%{received_count: count} when count > 0, overview) -> true
      match?(%{preparing_count: count} when count > 0, overview) -> true
      match?(%{todays_count: count} when count > 0, overview) -> true
      true -> false
    end
  end

  defp primary_tiles(%User{} = user, _overview) do
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

  defp shortcut_groups(%User{} = user, shift_close) do
    unpaid_count = Orders.count_todays_unpaid()
    overview = Orders.dashboard_overview()

    service =
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
          id: "transactions",
          title: "Transactions",
          body: "Daily receipts & reprints",
          path: ~p"/transactions",
          count: nil,
          show?: Authorization.can?(user, :orders)
        },
        %{
          id: "customers",
          title: "Loyalty / Customers",
          body: "Find customers & history",
          path: ~p"/customers",
          count: nil,
          show?: Authorization.can?(user, :orders)
        }
      ]
      |> Enum.filter(& &1.show?)

    shift =
      [
        %{
          id: "my-shifts",
          title: "My shifts",
          body: "Time In, Time Out & sales",
          path: ~p"/staff/shifts",
          count: nil,
          show?: user.role == "barista"
        },
        %{
          id: "cash-out",
          title: "Cash Out",
          body: "Drawer expense for the shop",
          path: ~p"/staff/cash-out",
          count: nil,
          show?: CashOuts.can_access?(user)
        },
        %{
          id: "close",
          title: if(shift_close, do: "Shift closed", else: "Close shift"),
          body: if(shift_close, do: "View close snapshot", else: "Totals & counted cash"),
          path: ~p"/staff/close",
          count: nil,
          show?: Shifts.can_access_close?(user),
          class: "staff-home-tool-link--close"
        }
      ]
      |> Enum.filter(& &1.show?)

    manage =
      [
        %{
          id: "dashboard",
          title: "Dashboard",
          body: "Sales & activity",
          path: ~p"/dashboard",
          count: nil,
          show?: manager_or_owner?(user)
        },
        %{
          id: "availability",
          title: "Availability",
          body: "Sold out / in stock",
          path: ~p"/admin/availability",
          count: nil,
          show?: Authorization.can?(user, :product_availability)
        },
        %{
          id: "staff",
          title: "Staff",
          body: "Accounts & PINs",
          path: ~p"/admin/users",
          count: nil,
          show?: user.role == "owner",
          class: "staff-home-tool-link--owner"
        },
        %{
          id: "settings",
          title: "Settings",
          body: "Payments & shop",
          path: ~p"/admin/settings",
          count: nil,
          show?: user.role == "owner",
          class: "staff-home-tool-link--owner"
        }
      ]
      |> Enum.filter(& &1.show?)

    [
      %{title: "Service", items: service},
      %{title: "Shift", items: shift},
      %{title: "Manage", items: manage}
    ]
    |> Enum.reject(&(&1.items == []))
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

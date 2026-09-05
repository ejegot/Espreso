defmodule EspresoWeb.StaffHomeLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
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
    {:noreply, assign(socket, :printer_note, printer_action_note(Printer.test_print(), "Test print"))}
  end

  def handle_event("printer_open_drawer", _params, socket) do
    {:noreply,
     assign(socket, :printer_note, printer_action_note(Printer.open_drawer(), "Open kaha"))}
  end

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

            <ul
              :if={@breakdown}
              class="staff-paid-breakdown"
              id="staff-home-paid-breakdown"
            >
              <li :for={row <- @via_rows} class="staff-paid-breakdown-row">
                <span class="staff-paid-breakdown-label">{row.label}</span>
                <span class="staff-paid-breakdown-total">{Menu.format_price(row.total)}</span>
                <span class="staff-paid-breakdown-count">{row.count}</span>
              </li>
            </ul>

            <p
              :if={@shift_close}
              class="staff-home-today-closed"
              id="staff-home-shift-closed"
            >
              Closed · {Shifts.format_closed_at(@shift_close.closed_at)}
              <span :if={@shift_close.closed_by_user}>
                by {@shift_close.closed_by_user.name}
              </span>
            </p>
          <% else %>
            <div class="staff-home-today-row staff-home-today-row--compact">
              <p class="staff-home-today-meta" id="staff-home-today-barista">
                {@overview.received_count} new · {@overview.preparing_count} preparing · {@overview.unpaid_active_count} unpaid · {@overview.todays_count} orders today
              </p>
            </div>
          <% end %>
        </section>

        <section
          :if={@printer_enabled?}
          class="staff-home-printer"
          id="staff-home-printer"
          aria-label="Printer"
        >
          <p class="staff-home-today-eyebrow">Printer</p>
          <p class="staff-home-today-meta">
            LAN · {Printer.host()}:{Printer.port()}
          </p>
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
          <p :if={@printer_note} class="staff-home-today-meta" id="staff-printer-note">
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
    |> assign(:printer_enabled?, Printer.enabled?())
    |> assign(:primary, primary_tiles(user, overview))
    |> assign(:secondary, secondary_tiles(user, shift_close))
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

  defp secondary_tiles(%User{} = user, shift_close) do
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
            id: "close",
            eyebrow: "End of day",
            title: if(shift_close, do: "Shift closed", else: "Close shift"),
            body:
              if shift_close do
                "View today’s close snapshot."
              else
                "Record system totals and counted cash."
              end,
            path: ~p"/staff/close",
            count: nil,
            show?: Authorization.can?(user, :reports),
            class: "staff-home-card--close"
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

  defp printer_action_note(:ok, label), do: "#{label} OK"
  defp printer_action_note(:disabled, label), do: "#{label} skipped (printer disabled)"
  defp printer_action_note({:error, reason}, label), do: "#{label} failed (#{inspect(reason)})"
end

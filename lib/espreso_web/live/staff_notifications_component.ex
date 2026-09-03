defmodule EspresoWeb.StaffNotificationsComponent do
  @moduledoc """
  Staff shell notification bell + feed (Bitepoint-inspired).

  Parents call `EspresoWeb.StaffNotifications.push_order_change/1` from
  `handle_info({:order_changed, order}, …)`.
  """
  use EspresoWeb, :live_component

  alias Espreso.Orders
  alias Espreso.Orders.Order

  @max_items 30

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open?, false)
     |> assign(:items, [])
     |> assign(:unread, 0)
     |> assign(:snapshots, %{})}
  end

  @impl true
  def update(%{order_changed: %Order{} = order} = assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:order_changed, :id]))
      |> maybe_append(order)

    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, Map.drop(assigns, [:id]))}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :open?, !socket.assigns.open?)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :open?, false)}
  end

  def handle_event("mark_all_read", _params, socket) do
    items = Enum.map(socket.assigns.items, &%{&1 | read?: true})

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:unread, 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class={["staff-notif", @open? && "is-open"]}
      id="staff-notifications"
      phx-hook="StaffNotifications"
    >
      <button
        type="button"
        class="staff-notif-bell"
        id="staff-notif-toggle"
        phx-click="toggle"
        phx-target={@myself}
        aria-expanded={to_string(@open?)}
        aria-controls="staff-notif-panel"
        aria-label={notif_aria_label(@unread)}
      >
        <span class="staff-notif-bell-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M15 17h5l-1.4-1.4A2 2 0 0 1 18 14.2V11a6 6 0 1 0-12 0v3.2a2 2 0 0 1-.6 1.4L4 17h5" />
            <path d="M9.5 17a2.5 2.5 0 0 0 5 0" />
          </svg>
        </span>
        <span :if={@unread > 0} class="staff-notif-badge" id="staff-notif-badge">
          {badge_count(@unread)}
        </span>
      </button>

      <div
        :if={@open?}
        class="staff-notif-backdrop"
        id="staff-notif-backdrop"
        phx-click="close"
        phx-target={@myself}
        aria-hidden="true"
      >
      </div>

      <div
        :if={@open?}
        class="staff-notif-panel"
        id="staff-notif-panel"
        role="dialog"
        aria-label="Notifications"
      >
        <header class="staff-notif-head">
          <div>
            <p class="staff-notif-title">Notifications</p>
            <p class="staff-notif-sub">Live order alerts</p>
          </div>
          <div class="staff-notif-head-actions">
            <button
              type="button"
              class="staff-notif-mute"
              id="staff-notif-mute"
              data-staff-notif-mute
              aria-pressed="false"
              title="Toggle alert sound"
            >
              Sound on
            </button>
            <button
              type="button"
              class="staff-notif-mark"
              id="staff-notif-mark-all"
              phx-click="mark_all_read"
              phx-target={@myself}
              disabled={@unread == 0}
            >
              Mark all read
            </button>
          </div>
        </header>

        <ul class="staff-notif-list" id="staff-notif-list">
          <li :if={@items == []} class="staff-notif-empty" id="staff-notif-empty">
            No alerts yet this shift.
          </li>
          <li
            :for={item <- @items}
            class={["staff-notif-item", "staff-notif-item--#{item.type}", !item.read? && "is-unread"]}
            id={"staff-notif-#{item.id}"}
          >
            <span class={"staff-notif-icon staff-notif-icon--#{item.type}"} aria-hidden="true">
              {icon_glyph(item.type)}
            </span>
            <div class="staff-notif-copy">
              <p class="staff-notif-item-title">{item.title}</p>
              <p class="staff-notif-item-body">{item.body}</p>
              <p class="staff-notif-item-time">{format_age(item.at)}</p>
            </div>
            <span :if={!item.read?} class="staff-notif-dot" aria-hidden="true"></span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp maybe_append(socket, %Order{} = order) do
    snap = {order.status, order.payment_status}
    prev = Map.get(socket.assigns.snapshots, order.id)
    snapshots = Map.put(socket.assigns.snapshots, order.id, snap)

    case notification_for(order, prev, snap) do
      nil ->
        assign(socket, :snapshots, snapshots)

      item ->
        items = [item | socket.assigns.items] |> Enum.take(@max_items)

        socket =
          socket
          |> assign(:snapshots, snapshots)
          |> assign(:items, items)
          |> assign(:unread, socket.assigns.unread + 1)

        if item.type == "new_order" do
          push_event(socket, "staff_notify_chime", %{})
        else
          socket
        end
    end
  end

  defp notification_for(order, nil, {"received", _payment}) do
    build(order, "new_order", "New order", order_body(order))
  end

  defp notification_for(order, {prev_status, _}, {"ready", _})
       when prev_status != "ready" do
    build(order, "ready", "Ready to serve", order_body(order))
  end

  defp notification_for(order, {_status, prev_pay}, {_status2, "paid"})
       when prev_pay in ["unpaid", "awaiting_payment"] do
    build(order, "payment", "Payment completed", payment_body(order))
  end

  defp notification_for(_order, _prev, _snap), do: nil

  defp build(order, type, title, body) do
    %{
      id: "#{order.id}-#{type}-#{System.unique_integer([:positive])}",
      type: type,
      title: title,
      body: body,
      at: DateTime.utc_now(:second),
      read?: false,
      order_number: order.number
    }
  end

  defp order_body(order) do
    [
      order.number,
      order.customer_name,
      fulfillment_short(order)
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
  end

  defp payment_body(order) do
    via =
      case order.paid_via do
        nil -> Orders.payment_label(order)
        via -> String.capitalize(to_string(via))
      end

    "#{order.number} · #{via}"
  end

  defp fulfillment_short(%{fulfillment: "dine_in", table_number: table})
       when is_binary(table) and table != "",
       do: "Table #{table}"

  defp fulfillment_short(%{fulfillment: "dine_in"}), do: "Dine-in"
  defp fulfillment_short(%{fulfillment: "pickup"}), do: "Pickup"
  defp fulfillment_short(_), do: nil

  defp format_age(%DateTime{} = at) do
    seconds =
      DateTime.utc_now(:second)
      |> DateTime.diff(DateTime.truncate(at, :second), :second)
      |> max(0)

    cond do
      seconds < 60 -> "Just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      true -> "#{div(seconds, 3600)}h ago"
    end
  end

  defp format_age(_), do: ""

  defp badge_count(n) when n > 9, do: "9+"
  defp badge_count(n), do: Integer.to_string(n)

  defp notif_aria_label(0), do: "Notifications"
  defp notif_aria_label(1), do: "Notifications, 1 unread"
  defp notif_aria_label(n), do: "Notifications, #{n} unread"

  defp icon_glyph("new_order"), do: "＋"
  defp icon_glyph("payment"), do: "₱"
  defp icon_glyph("ready"), do: "✓"
  defp icon_glyph(_), do: "•"
end

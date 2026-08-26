defmodule EspresoWeb.StaffOrdersLive do
  use EspresoWeb, :live_view

  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Orders.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Orders")
     |> assign(:flash_note, nil)
     |> load_orders(), layout: false}
  end

  @impl true
  def handle_info({:order_changed, _order}, socket) do
    {:noreply, load_orders(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_orders(socket)}
  end

  def handle_event("set_status", %{"id" => id, "status" => status}, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)

    case Orders.update_status(order, status) do
      {:ok, _} -> {:noreply, load_orders(assign(socket, :flash_note, nil))}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("mark_paid", %{"id" => id}, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)

    case Orders.mark_paid(order) do
      {:ok, paid} ->
        {:noreply,
         socket
         |> assign(:flash_note, "#{paid.number} marked paid.")
         |> load_orders()}

      {:error, :cancelled} ->
        {:noreply, assign(socket, :flash_note, "Cancelled orders cannot be marked paid.")}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not mark order paid.")}
    end
  end

  def handle_event("cancel_order", %{"id" => id}, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)

    case Orders.cancel_order(order) do
      {:ok, cancelled} ->
        {:noreply,
         socket
         |> assign(:flash_note, "#{cancelled.number} cancelled.")
         |> load_orders()}

      {:error, :paid} ->
        {:noreply, assign(socket, :flash_note, "Paid orders cannot be cancelled.")}

      {:error, :invalid_status} ->
        {:noreply, assign(socket, :flash_note, "This order can no longer be cancelled.")}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not cancel order.")}
    end
  end

  def handle_event("complete_order", %{"id" => id}, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)

    case Orders.complete_order(order) do
      {:ok, completed} ->
        {:noreply,
         socket
         |> assign(:flash_note, "#{completed.number} picked up.")
         |> load_orders()}

      {:error, :cancelled} ->
        {:noreply, assign(socket, :flash_note, "Cancelled orders cannot be marked picked up.")}

      {:error, :invalid_status} ->
        {:noreply, assign(socket, :flash_note, "Only ready orders can be marked picked up.")}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not mark order picked up.")}
    end
  end

  @impl true
  def render(assigns) do
    received = Enum.filter(assigns.active_orders, &(&1.status == "received"))
    preparing = Enum.filter(assigns.active_orders, &(&1.status == "preparing"))

    assigns =
      assigns
      |> assign(:received_orders, received)
      |> assign(:preparing_orders, preparing)

    ~H"""
    <.staff_shell current={:orders} current_user={@current_user} page_title="Orders">
      <:tools>
        <button type="button" class="staff-shell-tool" phx-click="refresh">Refresh</button>
      </:tools>

      <div class="staff-orders-page">
        <main class="staff-orders-main">
          <p :if={@flash_note} class="staff-admin-note" id="orders-flash">{@flash_note}</p>

          <div class="staff-orders-board">
            <div
              class="staff-orders-kitchen"
              id="orders-kitchen"
              role="region"
              aria-label="Kitchen"
            >
              <section class="staff-orders-section staff-orders-section--new" id="orders-new">
                <header class="staff-orders-section-head">
                  <h2>New</h2>
                  <span class="staff-orders-count">{length(@received_orders)}</span>
                </header>
                <p :if={@received_orders == []} class="staff-empty">No new orders.</p>
                <.kitchen_order_card :for={order <- @received_orders} order={order} />
              </section>

              <section
                class="staff-orders-section staff-orders-section--preparing"
                id="orders-preparing"
              >
                <header class="staff-orders-section-head">
                  <h2>Preparing</h2>
                  <span class="staff-orders-count">{length(@preparing_orders)}</span>
                </header>
                <p :if={@preparing_orders == []} class="staff-empty">Nothing preparing.</p>
                <.kitchen_order_card :for={order <- @preparing_orders} order={order} />
              </section>

              <section class="staff-orders-section staff-orders-section--ready" id="orders-ready">
                <header class="staff-orders-section-head">
                  <h2>Ready</h2>
                  <span class="staff-orders-count">{length(@ready_orders)}</span>
                </header>
                <p :if={@ready_orders == []} class="staff-empty">None yet.</p>
                <.kitchen_order_card :for={order <- @ready_orders} order={order} />
              </section>
            </div>

            <section
              class="staff-orders-section staff-orders-section--unpaid staff-orders-collections"
              id="unpaid-orders"
              role="region"
              aria-label="Unpaid orders"
            >
              <header class="staff-orders-section-head">
                <h2>Unpaid Orders</h2>
                <span class="staff-orders-count">{length(@unpaid_orders)}</span>
              </header>
              <p :if={@unpaid_orders == []} class="staff-empty" id="unpaid-orders-empty">
                No unpaid orders today.
              </p>
              <article
                :for={order <- @unpaid_orders}
                class="staff-order-card staff-order-card--unpaid"
                id={"unpaid-order-#{order.id}"}
              >
                <p class="staff-order-number">{order.number}</p>
                <p class="staff-order-name">{order.customer_name}</p>
                <p class="staff-order-pay">
                  <span class="staff-order-pay-amount">{Orders.format_total(order)}</span>
                  ·
                  <span class={"staff-badge staff-badge--pay-#{order.payment_status}"}>
                    {payment_state_label(order)}
                  </span>
                </p>
                <p class="staff-order-meta">
                  <span class={"staff-badge staff-badge--#{order.status}"}>
                    {Orders.status_label(order.status)}
                  </span>
                </p>
                <div class="staff-order-actions">
                  <button
                    type="button"
                    class="staff-action staff-action-primary"
                    id={"unpaid-mark-paid-#{order.id}"}
                    phx-click="mark_paid"
                    phx-value-id={order.id}
                  >
                    Mark paid
                  </button>
                </div>
              </article>
            </section>
          </div>
        </main>
      </div>
    </.staff_shell>
    """
  end

  defp kitchen_order_card(assigns) do
    ~H"""
    <article
      class={["staff-order-card", "staff-order-card--#{@order.status}"]}
      id={"order-card-#{@order.id}"}
    >
      <p class="staff-order-number">{@order.number}</p>
      <p class="staff-order-name">{@order.customer_name}</p>

      <ul class="staff-order-items">
        <li :for={item <- @order.items}>
          <span class="staff-order-item-qty">{item.quantity} ×</span>
          {item.name}
          <span :if={item.size} class="staff-order-item-size">({item.size})</span>
        </li>
      </ul>

      <p class="staff-order-pay">
        <span class="staff-order-pay-amount">{Orders.format_total(@order)}</span>
        ·
        <span class={"staff-order-pay-state staff-badge--pay-#{@order.payment_status}"}>
          {payment_state_label(@order)}
        </span>
      </p>

      <p class="staff-order-meta">{fulfillment_short(@order)}</p>
      <p :if={@order.notes} class="staff-order-notes">{@order.notes}</p>

      <div class="staff-order-actions">
        <button
          :if={@order.status == "received"}
          type="button"
          class="staff-action staff-action-primary"
          id={"order-prepare-#{@order.id}"}
          phx-click="set_status"
          phx-value-id={@order.id}
          phx-value-status="preparing"
        >
          Prepare
        </button>
        <button
          :if={@order.status == "preparing"}
          type="button"
          class="staff-action staff-action-primary"
          id={"order-ready-#{@order.id}"}
          phx-click="set_status"
          phx-value-id={@order.id}
          phx-value-status="ready"
        >
          Ready
        </button>
        <button
          :if={@order.status == "ready"}
          type="button"
          class="staff-action staff-action-primary"
          id={"ready-complete-#{@order.id}"}
          phx-click="complete_order"
          phx-value-id={@order.id}
        >
          Picked up
        </button>

        <button
          :if={@order.payment_status == "unpaid"}
          type="button"
          class="staff-action staff-action-secondary"
          id={if(@order.status == "ready", do: "ready-mark-paid-#{@order.id}")}
          phx-click="mark_paid"
          phx-value-id={@order.id}
        >
          Mark paid
        </button>
        <button
          :if={@order.payment_status == "unpaid" and @order.status in ["received", "preparing"]}
          type="button"
          class="staff-action staff-action-muted"
          id={"cancel-order-#{@order.id}"}
          phx-click="cancel_order"
          phx-value-id={@order.id}
        >
          Cancel
        </button>
      </div>
    </article>
    """
  end

  defp payment_state_label(%{payment_status: "paid"}), do: "Paid"
  defp payment_state_label(_), do: "Unpaid"

  defp fulfillment_short(%{fulfillment: "dine_in", table_number: table})
       when is_binary(table) and table != "",
       do: "Table #{table}"

  defp fulfillment_short(%{fulfillment: "dine_in"}), do: "Dine-in"
  defp fulfillment_short(%{fulfillment: "pickup"}), do: "Pickup"
  defp fulfillment_short(_), do: "Order"

  defp load_orders(socket) do
    socket
    |> assign(:active_orders, Orders.list_active_orders())
    |> assign(:ready_orders, Orders.list_recent_ready())
    |> assign(:unpaid_orders, Orders.list_todays_unpaid())
  end
end

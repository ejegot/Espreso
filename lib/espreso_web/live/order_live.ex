defmodule EspresoWeb.OrderLive do
  use EspresoWeb, :live_view

  alias Espreso.Orders
  alias Espreso.Menu

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    case Orders.get_order_by_number(number) do
      nil ->
        {:ok,
         socket
         |> assign(:page_title, "Order not found")
         |> assign(:order, nil)
         |> assign(:confirming?, false), layout: false}

      order ->
        if connected?(socket), do: Orders.subscribe(order)

        {:ok,
         socket
         |> assign(:page_title, "Order #{order.number}")
         |> assign(:order, order)
         |> assign(:confirming?, false), layout: false}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    confirming? =
      not is_nil(socket.assigns.order) and Map.get(params, "confirm") in ["1", "true"]

    page_title =
      cond do
        is_nil(socket.assigns.order) -> "Order not found"
        confirming? -> "Order confirmed"
        true -> "Order #{socket.assigns.order.number}"
      end

    {:noreply,
     socket
     |> assign(:confirming?, confirming?)
     |> assign(:page_title, page_title)}
  end

  @impl true
  def handle_info({:order_changed, %{id: id}}, socket) do
    case socket.assigns.order do
      %{id: ^id, number: number} ->
        {:noreply, assign(socket, :order, Orders.get_order_by_number!(number))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page order-page">
      <.brune_header current="menu" />

      <main class="order-main">
        <div :if={is_nil(@order)} class="order-card">
          <p class="order-eyebrow">Order</p>
          <h1 class="order-title">Order not found</h1>
          <p class="order-lede">
            Check the number on your screen, or place a new order from the menu.
          </p>
          <.link navigate={menu_browse_path()} class="brune-primary-btn">Back to menu</.link>
        </div>

        <div
          :if={@order && @confirming?}
          id="order-confirm"
          class="order-card order-card--confirm"
          phx-hook="OrderConfirm"
          data-order-number={@order.number}
        >
          <p class="order-eyebrow">CoffeeSpot</p>
          <h1 class="order-title" id="order-confirm-title">Order confirmed</h1>
          <p class="order-lede">
            Your order is in. Show your order number at the counter when you pick it up.
          </p>
          <p class="order-number order-number--confirm" id="order-confirm-number">{@order.number}</p>

          <div class="order-actions order-actions--confirm">
            <.link
              navigate={~p"/order/#{@order.number}"}
              class="order-view-link"
              id="order-view-my-order"
            >
              View My Order
            </.link>
            <.link
              navigate={menu_browse_path()}
              class="order-more-link"
              id="order-order-more"
            >
              Order More
            </.link>
          </div>
        </div>

        <div :if={@order && !@confirming?} class="order-card">
          <div class="order-status-block">
            <h1 class="order-status-message" id="order-status-message">
              {customer_status_message(@order.status)}
            </h1>
            <p class="order-number">{@order.number}</p>

            <ol
              :if={show_order_tracker?(@order.status)}
              id="order-progress"
              class="order-progress"
              aria-label="Order progress"
            >
              <li
                :for={step <- tracker_steps(@order.status)}
                class={[
                  "order-progress-step",
                  "is-#{step.state}"
                ]}
                data-step={step.key}
                data-state={step.state}
                aria-current={if(step.state == "current", do: "step")}
              >
                <span class="order-progress-marker" aria-hidden="true">
                  <span class="order-progress-marker-inner">{step.marker}</span>
                </span>
                <span class="order-progress-label">
                  <span class="order-progress-sr">{step.sr_prefix}</span>
                  {step.label}
                </span>
              </li>
            </ol>

            <div
              :if={@order.status == "cancelled"}
              id="order-cancelled-state"
              class="order-cancelled-state"
              role="status"
            >
              <p class="order-cancelled-badge">Cancelled</p>
              <p class="order-cancelled-lede">This order will not be prepared.</p>
            </div>

            <p class="order-hint" id="order-hint">{customer_status_hint(@order)}</p>
          </div>

          <section id="order-receipt" class="order-receipt" aria-labelledby="order-receipt-title">
            <h2 id="order-receipt-title" class="order-receipt-title">Your order</h2>

            <dl class="order-meta">
              <div>
                <dt>Name</dt>
                <dd>{@order.customer_name}</dd>
              </div>
              <div>
                <dt>Type</dt>
                <dd>
                  {Orders.fulfillment_label(@order.fulfillment)}
                  <span :if={@order.table_number}>· Table {@order.table_number}</span>
                </dd>
              </div>
              <div :if={@order.notes} class="order-meta-notes">
                <dt>Notes</dt>
                <dd>{@order.notes}</dd>
              </div>
            </dl>

            <ul class="order-items">
              <li :for={item <- @order.items} class="order-item">
                <div class="order-item-copy">
                  <p class="order-item-name">
                    <span class="order-item-qty">{item.quantity}×</span>
                    {item.name}
                  </p>
                  <p :if={item.size} class="order-item-size">{item.size}</p>
                </div>
                <p class="order-item-price">{Menu.format_price(item.line_total)}</p>
              </li>
            </ul>

            <div class="order-receipt-footer">
              <div class="order-total">
                <span>Total</span>
                <strong>{Orders.format_total(@order)}</strong>
              </div>
              <p class="order-payment">{Orders.payment_label(@order)}</p>
            </div>
          </section>

          <div class="order-actions">
            <.link navigate={menu_browse_path()} class="order-more-link" id="order-order-more">
              Order More
            </.link>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp menu_browse_path, do: ~p"/menu?stage=menu"

  defp customer_status_message("received"), do: "Order received"
  defp customer_status_message("preparing"), do: "We're preparing your order"
  defp customer_status_message("ready"), do: "Your order is ready"
  defp customer_status_message("completed"), do: "Order picked up"
  defp customer_status_message("cancelled"), do: "Order cancelled"
  defp customer_status_message(_), do: "Order"

  defp customer_status_hint(%{status: "completed"}),
    do: "Thanks — this order is complete. We hope you enjoyed CoffeeSpot."

  defp customer_status_hint(%{status: "cancelled"}),
    do: "This order was cancelled. You can place a new order from the menu."

  defp customer_status_hint(%{status: "preparing"}),
    do: "We're preparing it — keep this screen for updates."

  defp customer_status_hint(%{status: "ready", payment_status: "paid"}),
    do: "Your order is ready — show this screen at the counter."

  defp customer_status_hint(%{status: "ready"}),
    do: "Your order is ready — show this screen at the counter. Payment is due at the counter."

  defp customer_status_hint(%{status: "received", payment_status: "paid"}),
    do: "Keep this screen open for live updates on your order."

  defp customer_status_hint(%{status: "received", payment_method: "counter"}),
    do: "Keep this screen and show it at the counter for your order. Payment is due at the counter."

  defp customer_status_hint(%{status: "received"}),
    do: "Keep this screen open for live updates on your order."

  defp customer_status_hint(_order),
    do: "Keep this screen open for live updates on your order."

  defp show_order_tracker?(status) when status in ["received", "preparing", "ready", "completed"],
    do: true

  defp show_order_tracker?(_status), do: false

  defp tracker_steps(order_status) do
    [
      {"received", "Received"},
      {"preparing", "Preparing"},
      {"ready", "Ready"},
      {"completed", "Picked up"}
    ]
    |> Enum.map(fn {key, label} ->
      state = tracker_step_state(order_status, key)

      %{
        key: key,
        label: label,
        state: state,
        marker: tracker_marker(state),
        sr_prefix: tracker_sr_prefix(state)
      }
    end)
  end

  defp tracker_step_state(order_status, step_key) do
    order_idx = tracker_index(order_status)
    step_idx = tracker_index(step_key)

    cond do
      order_idx > step_idx -> "completed"
      order_idx == step_idx -> "current"
      true -> "upcoming"
    end
  end

  defp tracker_index("received"), do: 0
  defp tracker_index("preparing"), do: 1
  defp tracker_index("ready"), do: 2
  defp tracker_index("completed"), do: 3
  defp tracker_index(_), do: -1

  defp tracker_marker("completed"), do: "✓"
  defp tracker_marker("current"), do: "●"
  defp tracker_marker("upcoming"), do: "○"
  defp tracker_marker(_), do: "○"

  defp tracker_sr_prefix("completed"), do: "Completed: "
  defp tracker_sr_prefix("current"), do: "Current: "
  defp tracker_sr_prefix("upcoming"), do: "Upcoming: "
  defp tracker_sr_prefix(_), do: ""
end

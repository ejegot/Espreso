defmodule EspresoWeb.OrderLive do
  use EspresoWeb, :live_view

  alias Espreso.BusinessSettings
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
         |> assign(:payment_config, BusinessSettings.payment_config())
         |> assign(:confirming?, false), layout: false}

      order ->
        if connected?(socket), do: Orders.subscribe(order)
        payment_config = BusinessSettings.payment_config()

        {:ok,
         socket
         |> assign(:page_title, "Order #{order.number}")
         |> assign(:order, order)
         |> assign(:payment_config, payment_config)
         |> assign(:confirming?, false), layout: false}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    confirming? =
      not is_nil(socket.assigns.order) and Map.get(params, "confirm") in ["1", "true"]

    {:noreply,
     socket
     |> assign(:confirming?, confirming?)
     |> assign(:page_title, page_title(socket.assigns.order, confirming?))}
  end

  @impl true
  def handle_info({:order_changed, %{id: id}}, socket) do
    case socket.assigns.order do
      %{id: ^id, number: number} ->
        order = Orders.get_order_by_number!(number)

        {:noreply,
         socket
         |> assign(:order, order)
         |> assign(:page_title, page_title(order, socket.assigns.confirming?))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page order-page">
      <header class="order-chrome menu-qr-chrome menu-qr-top" id="order-chrome">
        <.link
          navigate={menu_browse_path()}
          class="menu-qr-chrome-back"
          id="order-chrome-back"
          aria-label="Back to menu"
        >
          <.icon name="hero-arrow-left" class="menu-qr-chrome-icon" />
        </.link>

        <h1 id="order-chrome-title" class="order-chrome-title menu-qr-chrome-brand menu-qr-top-brand">
          {order_chrome_title(@order, @confirming?)}
        </h1>

        <span class="menu-basket-header-spacer" aria-hidden="true"></span>
      </header>

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
          class={[
            "order-card order-card--confirm",
            show_qrph_payment?(@order) && "order-card--pay"
          ]}
          phx-hook="OrderConfirm"
          data-order-number={@order.number}
        >
          <p :if={not show_qrph_payment?(@order)} class="order-eyebrow">CoffeeSpot</p>
          <%= if show_qrph_payment?(@order) do %>
            <%!-- Pay screen content is the QRPh section below (header already says Pay at counter). --%>
          <% else %>
            <%= if confirm_payment_processing?(@order) do %>
              <h1 class="order-title" id="order-confirm-title">Payment processing</h1>
              <p class="order-lede" id="order-confirm-lede">
                We’re confirming your payment. This page will update when it’s done.
              </p>
            <% else %>
              <h1 class="order-title" id="order-confirm-title">Order confirmed</h1>
              <p class="order-lede" id="order-confirm-lede">
                {confirm_lede(@order)}
              </p>
            <% end %>
            <p class="order-number order-number--confirm" id="order-confirm-number">{@order.number}</p>
          <% end %>

          <section
            :if={show_qrph_payment?(@order)}
            id="order-confirm-qrph"
            class="order-qrph-payment order-qrph-payment--hero"
            aria-labelledby="order-confirm-qrph-payment-title"
          >
            {qrph_payment_section(assign(assigns, :id_prefix, "order-confirm"))}
          </section>

          <dl
            :if={not confirm_payment_processing?(@order) and not show_qrph_payment?(@order)}
            id="order-confirm-recap"
            class="order-confirm-recap"
          >
            <div class="order-confirm-recap-row">
              <dt>Type</dt>
              <dd>{Orders.fulfillment_label(@order.fulfillment)}</dd>
            </div>
            <div class="order-confirm-recap-row order-confirm-recap-total">
              <dt>Total</dt>
              <dd>{Orders.format_total(@order)}</dd>
            </div>
          </dl>

          <div class="order-actions order-actions--confirm">
            <.link
              navigate={~p"/order/#{@order.number}"}
              class="order-view-link"
              id="order-view-my-order"
            >
              View My Order
            </.link>
            <.link navigate={menu_browse_path()} class="order-more-link" id="order-order-more">
              Order More
            </.link>
          </div>
        </div>

        <div
          :if={@order && !@confirming?}
          class={["order-card", show_qrph_payment?(@order) && "order-card--pay"]}
        >
          <section
            :if={show_qrph_payment?(@order)}
            id="order-qrph-payment"
            class="order-qrph-payment order-qrph-payment--hero"
            aria-labelledby="order-qrph-payment-title"
          >
            {qrph_payment_section(assign(assigns, :id_prefix, "order"))}
          </section>

          <div
            :if={not show_qrph_payment?(@order)}
            class={[
              "order-status-block",
              @order.status == "completed" && "order-status-block--complete"
            ]}
          >
            <div
              :if={@order.status == "completed"}
              id="order-complete-state"
              class="order-complete-state"
              role="status"
            >
              <p class="order-complete-badge">✓ Order complete</p>
              <h1 class="order-status-message" id="order-status-message">Picked up ✓</h1>
              <p class="order-number">{@order.number}</p>
              <p class="order-hint" id="order-hint">
                Your order has been picked up. Thank you for visiting CoffeeSpot.
              </p>
            </div>

            <h1
              :if={@order.status != "completed"}
              class="order-status-message"
              id="order-status-message"
            >
              {customer_status_message(@order)}
            </h1>
            <p
              :if={@order.status != "completed" && @order.payment_status == "paid"}
              id="order-paid-badge"
              class="order-paid-badge"
              role="status"
            >
              Paid ✓
            </p>
            <p :if={@order.status != "completed"} class="order-number">{@order.number}</p>

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

            <p :if={@order.status not in ["completed"]} class="order-hint" id="order-hint">
              {customer_status_hint(@order)}
            </p>
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

  defp order_chrome_title(nil, _confirming?), do: "Order"

  defp order_chrome_title(order, true) do
    cond do
      show_qrph_payment?(order) -> "Pay at counter"
      confirm_payment_processing?(order) -> "Payment"
      true -> "Confirmed"
    end
  end

  defp order_chrome_title(_order, _confirming?), do: "Your order"

  defp page_title(nil, _confirming?), do: "Order not found"

  defp page_title(order, true) do
    cond do
      show_qrph_payment?(order) -> "Pay at counter"
      confirm_payment_processing?(order) -> "Payment processing"
      true -> "Order confirmed"
    end
  end

  defp page_title(order, _confirming?), do: "Order #{order.number}"

  defp confirm_payment_processing?(%{payment_method: "online", payment_status: "awaiting_payment"}),
    do: false

  defp confirm_payment_processing?(%{payment_method: "online", payment_status: status})
       when status != "paid" do
    true
  end

  defp confirm_payment_processing?(_order), do: false

  defp show_qrph_payment?(%{payment_method: "online", payment_status: "awaiting_payment"}), do: true
  defp show_qrph_payment?(_), do: false

  defp qrph_payment_section(assigns) do
    assigns =
      assigns
      |> assign_new(:id_prefix, fn -> "order" end)
      |> assign(:wallet_brand, qrph_wallet_brand(assigns.order))
      |> assign(:open_actions, qrph_open_actions(assigns.order))

    ~H"""
    <div class="order-qrph-hero">
      <p class="order-qrph-order-number" id={"#{@id_prefix}-qrph-number"}>{@order.number}</p>
      <p class="order-qrph-awaiting" id={"#{@id_prefix}-qrph-awaiting"}>
        <span class="order-qrph-chip">Waiting</span>
        <span :if={@wallet_brand} class="order-qrph-awaiting-wallet">· {@wallet_brand}</span>
      </p>
      <h2 id={"#{@id_prefix}-qrph-payment-title"} class="sr-only">
        {qrph_title(@order)}
      </h2>
    </div>

    <div class="order-qrph-amount-block">
      <p class="order-qrph-amount" id={"#{@id_prefix}-qrph-amount"}>
        <span class="order-qrph-amount-label">Amount</span>
        <strong>{Orders.format_total(@order)}</strong>
      </p>
    </div>

    <div :if={@open_actions != []} class="order-qrph-open-actions">
      <a
        :for={action <- @open_actions}
        id={"#{@id_prefix}-qrph-open-#{action.id}"}
        href={action.href}
        class={["order-qrph-open-btn", "order-qrph-open-btn--#{action.id}"]}
      >
        {action.label}
      </a>
    </div>

    <p class="order-qrph-waiting" id={"#{@id_prefix}-qrph-waiting"} role="status">
      Waiting for staff to confirm.
    </p>
    """
  end

  defp qrph_title(%{online_wallet: "gcash"}), do: "Pay with GCash"
  defp qrph_title(%{online_wallet: "maya"}), do: "Pay with Maya"
  defp qrph_title(_), do: "Pay with QRPh"

  defp qrph_wallet_brand(%{online_wallet: "gcash"}), do: "GCash"
  defp qrph_wallet_brand(%{online_wallet: "maya"}), do: "Maya"
  defp qrph_wallet_brand(_), do: nil

  defp qrph_open_actions(%{online_wallet: "gcash"}) do
    [%{id: "gcash", label: "Open GCash", href: wallet_open_href("gcash")}]
  end

  defp qrph_open_actions(%{online_wallet: "maya"}) do
    [%{id: "maya", label: "Open Maya", href: wallet_open_href("maya")}]
  end

  defp qrph_open_actions(_order) do
    [
      %{id: "gcash", label: "Open GCash", href: wallet_open_href("gcash")},
      %{id: "maya", label: "Open Maya", href: wallet_open_href("maya")}
    ]
  end

  # Best-effort app deep links. If the OS can’t open them, guest follows the steps manually.
  defp wallet_open_href("gcash"), do: "gcash://"
  defp wallet_open_href("maya"), do: "maya://"
  defp wallet_open_href(_), do: "#"

  defp confirm_lede(%{fulfillment: "dine_in"}) do
    "Your order is in. Show your order number at the counter for your dine-in order."
  end

  defp confirm_lede(%{fulfillment: "pickup"}) do
    "Your order is in. Takeout — pick it up at the counter when it's ready."
  end

  defp confirm_lede(_order) do
    "Your order is in."
  end

  defp customer_status_message(%{payment_method: "online", payment_status: status})
       when status in ["awaiting_payment", "unpaid"],
       do: "Waiting for payment confirm"

  defp customer_status_message(%{status: "received"}), do: "Received — kitchen has it"
  defp customer_status_message(%{status: "preparing"}), do: "Preparing your order"
  defp customer_status_message(%{status: "ready"}), do: "Ready — please come to counter"
  defp customer_status_message(%{status: "completed"}), do: "Picked up ✓"
  defp customer_status_message(%{status: "cancelled"}), do: "Order cancelled"
  defp customer_status_message(_), do: "Order"

  defp customer_status_hint(%{status: "completed"}),
    do: "Your order has been picked up. Thank you for visiting CoffeeSpot."

  defp customer_status_hint(%{status: "cancelled"}),
    do: "This order was cancelled. You can place a new order from the menu."

  defp customer_status_hint(%{status: "preparing"}),
    do: "We're preparing it — keep this screen for updates."

  defp customer_status_hint(%{status: "ready", payment_status: "paid", number: number}),
    do: "Show #{number} at the counter."

  defp customer_status_hint(%{status: "ready", number: number}),
    do: "Show #{number} at the counter. Payment is due at the counter."

  defp customer_status_hint(%{status: "received", payment_status: "paid"}),
    do: "Keep this screen open for live updates on your order."

  defp customer_status_hint(%{
         status: "received",
         payment_method: "online",
         payment_status: "awaiting_payment",
         online_wallet: "gcash"
       }),
       do: "Keep this screen open — it updates when staff confirms your GCash payment."

  defp customer_status_hint(%{
         status: "received",
         payment_method: "online",
         payment_status: "awaiting_payment",
         online_wallet: "maya"
       }),
       do: "Keep this screen open — it updates when staff confirms your Maya payment."

  defp customer_status_hint(%{
         status: "received",
         payment_method: "online",
         payment_status: "awaiting_payment"
       }),
       do: "Keep this screen open — it updates when staff confirms your payment."

  defp customer_status_hint(%{status: "received", payment_method: "counter"}),
    do: "Pay at counter · show this number."

  defp customer_status_hint(%{status: "received"}),
    do: "Keep this screen open for live updates on your order."

  defp customer_status_hint(_order),
    do: "Keep this screen open for live updates on your order."

  defp show_order_tracker?(status) when status in ["received", "preparing", "ready"], do: true

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

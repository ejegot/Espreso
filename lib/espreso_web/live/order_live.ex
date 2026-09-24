defmodule EspresoWeb.OrderLive do
  use EspresoWeb, :live_view

  alias Espreso.BusinessSettings
  alias Espreso.CustomerPush
  alias Espreso.Loyalty
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.Order

  @return_to_menu_ms 4_000

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    case Orders.get_order_by_number(number) do
      nil ->
        {:ok,
         socket
         |> assign(:page_title, "Order not found")
         |> assign(:order, nil)
         |> assign(:payment_config, BusinessSettings.payment_config())
         |> assign(:confirming?, false)
         |> assign(:complete_return?, false)
         |> assign(:qrph_code_open, nil)
         |> assign_push_prompt(), layout: false}

      order ->
        if connected?(socket), do: Orders.subscribe(order)
        payment_config = BusinessSettings.payment_config()

        {:ok,
         socket
         |> assign(:page_title, "Order #{order.number}")
         |> assign(:order, order)
         |> assign(:payment_config, payment_config)
         |> assign(:confirming?, false)
         |> assign(:complete_return?, false)
         |> assign(:qrph_code_open, nil)
         |> assign_push_prompt(), layout: false}
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
      %{id: ^id, number: number} = previous ->
        order = Orders.get_order_by_number!(number)

        {:noreply,
         socket
         |> assign(:order, order)
         |> assign(:page_title, page_title(order, socket.assigns.confirming?))
         |> maybe_leave_confirm_after_payment(previous)
         |> maybe_begin_complete_return(previous)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(:return_to_menu, socket) do
    {:noreply, push_navigate(socket, to: menu_browse_path())}
  end

  @impl true
  def handle_event("open_qrph_code", %{"id" => id}, socket)
      when id in ["gcash", "maya"] do
    {:noreply, assign(socket, :qrph_code_open, id)}
  end

  def handle_event("open_qrph_code", _params, socket), do: {:noreply, socket}

  def handle_event("close_qrph_code", _params, socket) do
    {:noreply, assign(socket, :qrph_code_open, nil)}
  end

  def handle_event("dismiss_order_push", _params, socket) do
    {:noreply, assign(socket, :push_prompt_dismissed?, true)}
  end

  def handle_event("enable_order_push", params, socket) when is_map(params) do
    case socket.assigns.order do
      %Order{} = order ->
        case CustomerPush.subscribe(order, params) do
          {:ok, _subscription} ->
            {:noreply, assign(socket, :push_subscribed?, true)}

          {:error, _reason} ->
            {:noreply, socket}
        end

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
        <.order_push_prompt
          :if={@order}
          order={@order}
          vapid_public_key={@push_vapid_public_key}
          show={show_order_push_prompt?(@order, assigns)}
        />

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
          <p :if={not show_qrph_payment?(@order)} class="order-eyebrow"><.coffeespot_wordmark /></p>
          <%= if show_qrph_payment?(@order) do %>
            <%!-- Pay screen content is the QRPh section below (header is Pay with GCash / Maya). --%>
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
            <p class="order-number order-number--confirm" id="order-confirm-number">
              {@order.number}
            </p>
          <% end %>

          <.elilai_rewards :if={not show_qrph_payment?(@order)} order={@order} />

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

          <div :if={not show_qrph_payment?(@order)} class="order-actions order-actions--confirm">
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
              data-returning={@complete_return? && "true"}
              role="status"
            >
              <h1 class="order-status-message" id="order-status-message">
                {customer_status_message(@order, @complete_return?)}
              </h1>
              <p class="order-number">{@order.number}</p>
              <p class="order-hint" id="order-hint">
                {customer_status_hint(@order, @complete_return?)}
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

          <.elilai_rewards
            :if={not @complete_return? and not show_qrph_payment?(@order)}
            order={@order}
          />

          <section
            :if={not @complete_return? and not show_qrph_payment?(@order)}
            id="order-receipt"
            class="order-receipt"
            aria-labelledby="order-receipt-title"
          >
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
                  <p
                    :if={meta = Orders.temperature_meta(item)}
                    class={"order-item-temp is-#{meta.tone}"}
                  >
                    {meta.label}
                  </p>
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

          <div :if={not show_qrph_payment?(@order)} class="order-actions">
            <.link navigate={menu_browse_path()} class="order-more-link" id="order-order-more">
              {if(@order.status == "completed", do: "Back to menu", else: "Order More")}
            </.link>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp menu_browse_path, do: ~p"/menu?stage=menu"

  defp assign_push_prompt(socket) do
    socket
    |> assign(:push_vapid_public_key, CustomerPush.vapid_public_key_js())
    |> assign(:push_prompt_dismissed?, false)
    |> assign(:push_subscribed?, false)
  end

  defp show_order_push_prompt?(order, assigns) do
    CustomerPush.promptable?(order) and
      assigns.push_vapid_public_key != "" and
      not assigns.push_prompt_dismissed? and
      not assigns.push_subscribed?
  end

  defp order_push_prompt(assigns) do
    ~H"""
    <section
      :if={@show}
      id="order-push-prompt"
      class="order-push-prompt"
      phx-hook="OrderPushPrompt"
      data-vapid-public-key={@vapid_public_key}
      data-order-number={@order.number}
    >
      <p class="order-push-prompt-title">Get a ping</p>
      <p class="order-push-prompt-lede" data-order-push-lede>
        When it's preparing and ready to pick up.
      </p>
      <p class="order-push-prompt-lede order-push-ios-help" data-order-push-ios hidden>
        iPhone: Share → Add to Home Screen, then open the icon.
      </p>
      <div class="order-push-prompt-actions">
        <button type="button" id="order-push-allow" class="order-push-allow" data-order-push-allow>
          Notify me
        </button>
        <button
          type="button"
          id="order-push-dismiss"
          class="order-push-dismiss"
          phx-click="dismiss_order_push"
        >
          Not now
        </button>
      </div>
    </section>
    """
  end

  defp order_chrome_title(nil, _confirming?), do: "Order"

  defp order_chrome_title(order, true) do
    cond do
      show_qrph_payment?(order) -> qrph_title(order)
      confirm_payment_processing?(order) -> "Payment"
      true -> "Confirmed"
    end
  end

  defp order_chrome_title(_order, _confirming?), do: "Your order"

  defp page_title(nil, _confirming?), do: "Order not found"

  defp page_title(order, true) do
    cond do
      show_qrph_payment?(order) -> qrph_title(order)
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

  defp show_qrph_payment?(%{payment_method: "online", payment_status: "awaiting_payment"}),
    do: true

  defp show_qrph_payment?(_), do: false

  defp qrph_payment_section(assigns) do
    qrph_codes = qrph_codes_for(assigns.order, assigns.payment_config)
    open_id = assigns[:qrph_code_open]

    assigns =
      assigns
      |> assign_new(:id_prefix, fn -> "order" end)
      |> assign(:wallet_brand, qrph_wallet_brand(assigns.order))
      |> assign(:qrph_codes, qrph_codes)
      |> assign(:open_code, Enum.find(qrph_codes, &(&1.id == open_id)))

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

    <p class="order-qrph-amount" id={"#{@id_prefix}-qrph-amount"}>
      <span class="order-qrph-amount-label">Amount</span>
      <strong>{Orders.format_total(@order)}</strong>
    </p>

    <p class="order-qrph-counter-hint" id={"#{@id_prefix}-qrph-counter-hint"}>
      Scan this QR to pay. We'll confirm from {qrph_wallet_brand(@order) || "GCash"}.
    </p>

    <div :if={@qrph_codes != []} class="order-qrph-codes" id={"#{@id_prefix}-qrph-codes"}>
      <p class="order-qrph-or" id={"#{@id_prefix}-qrph-or"}>Scan to pay</p>
      <button
        :for={code <- @qrph_codes}
        type="button"
        id={"#{@id_prefix}-qrph-code-#{code.id}"}
        class="order-qrph-code order-qrph-code--thumb"
        phx-click="open_qrph_code"
        phx-value-id={code.id}
        aria-haspopup="dialog"
      >
        <img src={code.src} alt={"#{code.label} QR"} />
        <span class="order-qrph-code-name">{code.label}</span>
      </button>
    </div>

    <p class="order-qrph-waiting" id={"#{@id_prefix}-qrph-waiting"} role="status">
      Waiting for staff to confirm.
    </p>

    <div
      :if={@open_code}
      id={"#{@id_prefix}-qrph-modal"}
      class="order-qrph-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id_prefix}-qrph-modal-title"}
    >
      <button
        type="button"
        class="order-qrph-modal-backdrop"
        phx-click="close_qrph_code"
        aria-label="Close QR"
      >
      </button>
      <div class="order-qrph-modal-panel">
        <p class="order-qrph-modal-amount">{Orders.format_total(@order)}</p>
        <p class="order-qrph-modal-number">{@order.number}</p>
        <img id={"#{@id_prefix}-qrph-modal-img"} src={@open_code.src} alt={"#{@open_code.label} QR"} />
        <p id={"#{@id_prefix}-qrph-modal-title"} class="order-qrph-modal-name">
          {@open_code.label}
        </p>
        <p class="order-qrph-modal-hint" id={"#{@id_prefix}-qrph-modal-hint"}>
          Scan to pay {Orders.format_total(@order)}.
        </p>
        <button
          type="button"
          id={"#{@id_prefix}-qrph-modal-close"}
          class="order-qrph-modal-close"
          phx-click="close_qrph_code"
        >
          Close
        </button>
      </div>
    </div>
    """
  end

  defp qrph_title(%{payment_intent: "gcash"}), do: "Pay with GCash"
  defp qrph_title(%{payment_intent: "maya"}), do: "Pay with Maya"
  defp qrph_title(_), do: "Pay with QRPh"

  defp qrph_wallet_brand(%{payment_intent: "gcash"}), do: "GCash"
  defp qrph_wallet_brand(%{payment_intent: "maya"}), do: "Maya"
  defp qrph_wallet_brand(_), do: nil

  defp qrph_codes_for(%{payment_intent: "gcash"}, config),
    do: qrph_code_entries(config, [:gcash])

  defp qrph_codes_for(%{payment_intent: "maya"}, config),
    do: qrph_code_entries(config, [:maya])

  defp qrph_codes_for(_order, config), do: qrph_code_entries(config, [:gcash, :maya])

  defp qrph_code_entries(config, wallets) do
    Enum.flat_map(wallets, fn
      :gcash -> qrph_code_entry(config.gcash_qrph_path, "gcash", "GCash")
      :maya -> qrph_code_entry(config.maya_qrph_path, "maya", "Maya")
    end)
  end

  defp qrph_code_entry(path, id, label) when is_binary(path) and path != "" do
    [%{id: id, src: path, label: label}]
  end

  defp qrph_code_entry(_path, _id, _label), do: []

  defp confirm_lede(%{fulfillment: "dine_in"}) do
    "Your order is in. Show your order number at the counter for your dine-in order."
  end

  defp confirm_lede(%{fulfillment: "pickup"}) do
    "Your order is in. Takeout — pick it up at the counter when it's ready."
  end

  defp confirm_lede(_order) do
    "Your order is in."
  end

  defp customer_status_message(order, complete_return? \\ false)

  defp customer_status_message(
         %{payment_method: "online", payment_status: status},
         _complete_return?
       )
       when status in ["awaiting_payment", "unpaid"],
       do: "Waiting for payment confirm"

  defp customer_status_message(%{status: "received"}, _), do: "Received — kitchen has it"
  defp customer_status_message(%{status: "preparing"}, _), do: "Preparing your order"
  defp customer_status_message(%{status: "ready"}, _), do: "Ready for pick up"
  defp customer_status_message(%{status: "completed"}, true), do: "All done"
  defp customer_status_message(%{status: "completed"}, _), do: "Thank you"
  defp customer_status_message(%{status: "cancelled"}, _), do: "Order cancelled"
  defp customer_status_message(_, _), do: "Order"

  defp customer_status_hint(order, complete_return? \\ false)

  defp customer_status_hint(%{status: "completed"}, true),
    do: "Thank you — heading back to the menu."

  defp customer_status_hint(%{status: "completed"}, _),
    do: "This order is done."

  defp customer_status_hint(%{status: "cancelled"}, _),
    do: "This order was cancelled. You can place a new order from the menu."

  defp customer_status_hint(%{status: "preparing"}, _),
    do: "We're preparing it — we'll ping your phone if you allowed notifications."

  defp customer_status_hint(%{status: "ready", payment_status: "paid", number: number}, _),
    do: "Show #{number} at the counter."

  defp customer_status_hint(%{status: "ready", number: number}, _),
    do: "Show #{number} at the counter. Payment is due at the counter."

  defp customer_status_hint(%{status: "received", payment_status: "paid"}, _),
    do: "Keep this screen open for live updates on your order."

  defp customer_status_hint(
         %{
           status: "received",
           payment_method: "online",
           payment_status: "awaiting_payment",
           payment_intent: "gcash"
         },
         _
       ),
       do: "Keep this screen open — it updates when staff confirms your GCash payment."

  defp customer_status_hint(
         %{
           status: "received",
           payment_method: "online",
           payment_status: "awaiting_payment",
           payment_intent: "maya"
         },
         _
       ),
       do: "Keep this screen open — it updates when staff confirms your Maya payment."

  defp customer_status_hint(
         %{
           status: "received",
           payment_method: "online",
           payment_status: "awaiting_payment"
         },
         _
       ),
       do: "Keep this screen open — it updates when staff confirms your payment."

  defp customer_status_hint(%{status: "received", payment_method: "counter"}, _),
    do: "Pay at counter · show this number."

  defp customer_status_hint(%{status: "received"}, _),
    do: "Keep this screen open for live updates on your order."

  defp customer_status_hint(_order, _),
    do: "Keep this screen open for live updates on your order."

  defp show_order_tracker?(status) when status in ["received", "preparing", "ready"], do: true

  defp show_order_tracker?(_status), do: false

  defp tracker_steps(order_status) do
    [
      {"received", "Received"},
      {"preparing", "Preparing"},
      {"ready", "Ready"}
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
  defp tracker_index(_), do: -1

  defp tracker_marker("completed"), do: "✓"
  defp tracker_marker("current"), do: "●"
  defp tracker_marker("upcoming"), do: "○"
  defp tracker_marker(_), do: "○"

  defp tracker_sr_prefix("completed"), do: "Completed: "
  defp tracker_sr_prefix("current"), do: "Current: "
  defp tracker_sr_prefix("upcoming"), do: "Upcoming: "
  defp tracker_sr_prefix(_), do: ""

  defp maybe_leave_confirm_after_payment(socket, previous) do
    order = socket.assigns.order

    cond do
      not socket.assigns.confirming? ->
        socket

      is_nil(order) or is_nil(previous) ->
        socket

      order.payment_status != "paid" ->
        socket

      previous.payment_status == "paid" ->
        socket

      true ->
        socket
        |> assign(:qrph_code_open, nil)
        |> push_patch(to: ~p"/order/#{order.number}")
    end
  end

  defp maybe_begin_complete_return(socket, previous) do
    order = socket.assigns.order

    cond do
      socket.assigns.complete_return? ->
        socket

      is_nil(order) or is_nil(previous) ->
        socket

      previous.status == "completed" or order.status != "completed" ->
        socket

      socket.assigns.confirming? or not connected?(socket) ->
        socket

      true ->
        Process.send_after(self(), :return_to_menu, @return_to_menu_ms)
        assign(socket, :complete_return?, true)
    end
  end

  attr :order, Order, required: true

  defp elilai_rewards(assigns) do
    assigns = assign(assigns, :rewards, guest_rewards(assigns.order))

    ~H"""
    <section
      :if={@rewards}
      id="order-elilai-rewards"
      class="order-elilai-rewards"
      aria-labelledby="order-elilai-rewards-title"
    >
      <h2 id="order-elilai-rewards-title" class="order-elilai-rewards-title">ELIlai Rewards</h2>

      <%= case @rewards do %>
        <% %{kind: :linked} -> %>
          <p class="order-elilai-rewards-body" id="order-elilai-rewards-body">
            Your phone is linked. Points will be added after payment.
          </p>
        <% %{kind: :pending} -> %>
          <p class="order-elilai-rewards-body" id="order-elilai-rewards-body">
            Payment complete · loyalty points will be added shortly.
          </p>
        <% %{kind: :earned, points: points, balance: balance, more: more} -> %>
          <p class="order-elilai-rewards-body" id="order-elilai-rewards-body">
            +{points} {points_word(points)} earned · {balance} pts balance
          </p>
          <p class="order-elilai-rewards-meta" id="order-elilai-rewards-meta">
            {more} more {points_word(more)} to a free coffee.
          </p>
        <% %{kind: :eligible, balance: balance} -> %>
          <p class="order-elilai-rewards-body" id="order-elilai-rewards-body">
            Reward available
          </p>
          <p class="order-elilai-rewards-meta" id="order-elilai-rewards-meta">
            You have {balance} pts. Redeem 1 free HOT or COLD coffee at the counter.
          </p>
      <% end %>
    </section>
    """
  end

  defp guest_rewards(%Order{customer_id: nil}), do: nil

  defp guest_rewards(%Order{customer_id: customer_id, payment_status: "paid"} = order)
       when is_integer(customer_id) do
    case Loyalty.earn_outcome_for_order(order) do
      {:earned, points, balance} ->
        cost = Loyalty.redeem_cost()

        if balance >= cost do
          %{kind: :eligible, points: points, balance: balance}
        else
          %{
            kind: :earned,
            points: points,
            balance: balance,
            more: max(cost - balance, 0)
          }
        end

      :pending ->
        %{kind: :pending}

      :none ->
        nil
    end
  end

  defp guest_rewards(%Order{customer_id: customer_id}) when is_integer(customer_id) do
    %{kind: :linked}
  end

  defp guest_rewards(_), do: nil

  defp points_word(1), do: "point"
  defp points_word(_), do: "points"
end

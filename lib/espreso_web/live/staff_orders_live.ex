defmodule EspresoWeb.StaffOrdersLive do
  use EspresoWeb, :live_view

  alias Espreso.BusinessSettings
  alias Espreso.Orders

  @ready_lane_limit 100

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Orders.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Orders")
     |> assign(:flash_note, nil)
     |> assign(:unpaid_drawer_open, false)
     |> assign(:reconciliation_drawer_open, false)
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

  def handle_event("toggle_unpaid_drawer", _params, socket) do
    {:noreply, assign(socket, :unpaid_drawer_open, !socket.assigns.unpaid_drawer_open)}
  end

  def handle_event("close_unpaid_drawer", _params, socket) do
    {:noreply, assign(socket, :unpaid_drawer_open, false)}
  end

  def handle_event("toggle_reconciliation_drawer", _params, socket) do
    {:noreply, assign(socket, :reconciliation_drawer_open, !socket.assigns.reconciliation_drawer_open)}
  end

  def handle_event("close_reconciliation_drawer", _params, socket) do
    {:noreply, assign(socket, :reconciliation_drawer_open, false)}
  end

  def handle_event("set_status", %{"id" => id, "status" => status}, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)

    case Orders.update_status(order, status) do
      {:ok, _} ->
        {:noreply, load_orders(assign(socket, :flash_note, nil))}

      {:error, :payment_required} ->
        {:noreply,
         assign(
           socket,
           :flash_note,
           "Online payment must be verified before this order can be marked ready."
         )}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not update order status.")}
    end
  end

  def handle_event("mark_paid", %{"id" => id} = params, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)
    paid_via = Map.get(params, "paid_via", "counter")

    case Orders.mark_paid(order, paid_via: paid_via) do
      {:ok, paid} ->
        {:noreply,
         socket
         |> assign(:flash_note, "#{paid.number} marked paid (#{paid_via_label(paid_via)}).")
         |> load_orders()}

      {:error, :cancelled} ->
        {:noreply, assign(socket, :flash_note, "Cancelled orders cannot be marked paid.")}

      {:error, :online_payment_required} ->
        {:noreply,
         assign(
           socket,
           :flash_note,
           "This online order cannot be marked paid manually — wait for PayMongo or switch to QRPh mode."
         )}

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

      {:error, :checkout_in_progress} ->
        {:noreply,
         assign(
           socket,
           :flash_note,
           "Online payment is in progress. This order cannot be cancelled."
         )}

      {:error, :invalid_status} ->
        {:noreply, assign(socket, :flash_note, "This order can no longer be cancelled.")}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not cancel order.")}
    end
  end

  def handle_event("abandon_online_payment", %{"id" => id}, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)

    case Orders.abandon_online_payment(order) do
      {:ok, abandoned} ->
        {:noreply,
         socket
         |> assign(:flash_note, "#{abandoned.number} online payment abandoned.")
         |> load_orders()}

      {:error, :paid} ->
        {:noreply, assign(socket, :flash_note, "Paid orders cannot be abandoned.")}

      {:error, :missing_checkout_session} ->
        {:noreply,
         assign(socket, :flash_note, "No online checkout session to abandon on this order.")}

      {:error, :not_online} ->
        {:noreply, assign(socket, :flash_note, "Only online payments can be abandoned.")}

      {:error, :invalid_status} ->
        {:noreply, assign(socket, :flash_note, "This order can no longer be abandoned.")}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not abandon online payment.")}
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

      {:error, :payment_required} ->
        {:noreply,
         assign(
           socket,
           :flash_note,
           "Online payment must be verified before this order can be picked up."
         )}

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
        <span class="staff-orders-kds-pill staff-orders-kds-pill--new" aria-label="New order count">
          New {length(@received_orders)}
        </span>
        <button type="button" class="staff-shell-tool" phx-click="refresh">Refresh</button>
        <button
          type="button"
          class="staff-shell-tool staff-orders-unpaid-toggle"
          id="unpaid-drawer-toggle"
          phx-click="toggle_unpaid_drawer"
          aria-expanded={to_string(@unpaid_drawer_open)}
          aria-controls="unpaid-orders"
        >
          Unpaid <span class="staff-orders-unpaid-toggle-count">{length(@unpaid_orders)}</span>
        </button>
        <button
          type="button"
          class="staff-shell-tool staff-orders-reconciliation-toggle"
          id="reconciliation-drawer-toggle"
          phx-click="toggle_reconciliation_drawer"
          aria-expanded={to_string(@reconciliation_drawer_open)}
          aria-controls="paymongo-reconciliations"
        >
          Reconciliation
          <span class="staff-orders-reconciliation-toggle-count">
            {length(@paymongo_reconciliations)}
          </span>
        </button>
      </:tools>

      <div class="staff-orders-page staff-orders-shell-root">
        <main class="staff-orders-main">
          <p :if={@flash_note} class="staff-admin-note" id="orders-flash">{@flash_note}</p>

          <div class="staff-orders-board">
            <div
              class="staff-orders-workboard"
              id="orders-kitchen"
              role="region"
              aria-label="Kitchen"
            >
              <section class="staff-orders-kds-new" id="orders-new">
                <header class="staff-orders-kds-head staff-orders-kds-head--new">
                  <div class="staff-orders-kds-head-main">
                    <h2>New Orders</h2>
                    <p class="staff-orders-workflow-hint">Prepare → Ready → Picked up</p>
                  </div>
                  <span class="staff-orders-count">{length(@received_orders)}</span>
                </header>
                <div class="staff-orders-new-grid">
                  <p :if={@received_orders == []} class="staff-empty">No new orders.</p>
                  <.kds_ticket :for={order <- @received_orders} order={order} />
                </div>
              </section>

              <div class="staff-orders-kds-queues">
                <section class="staff-orders-kds-strip" id="orders-preparing">
                  <header class="staff-orders-kds-head staff-orders-kds-head--preparing">
                    <h2>Preparing</h2>
                    <span class="staff-orders-count">{length(@preparing_orders)}</span>
                  </header>
                  <div class="staff-orders-strip-grid">
                    <p :if={@preparing_orders == []} class="staff-empty">Nothing preparing.</p>
                    <.kds_ticket :for={order <- @preparing_orders} order={order} />
                  </div>
                </section>

                <section class="staff-orders-kds-strip" id="orders-ready">
                  <header class="staff-orders-kds-head staff-orders-kds-head--ready">
                    <h2>Ready</h2>
                    <span class="staff-orders-count">{length(@ready_orders)}</span>
                  </header>
                  <div class="staff-orders-strip-grid">
                    <p :if={@ready_orders == []} class="staff-empty">None yet.</p>
                    <.kds_ticket :for={order <- @ready_orders} order={order} />
                  </div>
                </section>
              </div>
            </div>
          </div>
        </main>

        <div
          :if={@unpaid_drawer_open}
          class="staff-orders-drawer-backdrop"
          phx-click="close_unpaid_drawer"
          aria-hidden="true"
        />

        <aside
          class={[
            "staff-orders-unpaid-drawer",
            "staff-orders-section",
            "staff-orders-section--unpaid",
            "staff-orders-collections",
            @unpaid_drawer_open && "staff-orders-unpaid-drawer--open"
          ]}
          id="unpaid-orders"
          role="region"
          aria-label="Unpaid orders"
          aria-hidden={to_string(!@unpaid_drawer_open)}
        >
          <header class="staff-orders-kds-head staff-orders-unpaid-drawer-head">
            <h2>Unpaid Today</h2>
            <span class="staff-orders-count">{length(@unpaid_orders)}</span>
            <button
              type="button"
              class="staff-orders-drawer-close"
              phx-click="close_unpaid_drawer"
              aria-label="Close unpaid drawer"
            >
              ×
            </button>
          </header>
          <p :if={@unpaid_orders == []} class="staff-empty" id="unpaid-orders-empty">
            No unpaid orders today.
          </p>
          <div :if={@unpaid_orders != []} class="staff-orders-unpaid-list">
            <article
              :for={order <- @unpaid_orders}
              class="staff-order-card staff-order-card--unpaid"
              id={"unpaid-order-#{order.id}"}
            >
              <div class="staff-order-unpaid-main">
                <p class="staff-order-number">{order.number}</p>
                <span class="staff-order-unpaid-sep" aria-hidden="true">·</span>
                <p class="staff-order-name">{order.customer_name}</p>
                <span class="staff-order-unpaid-sep" aria-hidden="true">·</span>
                <p class="staff-order-pay">
                  <span class="staff-order-pay-amount">{Orders.format_total(order)}</span>
                  <span class={"staff-badge staff-badge--pay-#{order.payment_status}"}>
                    {payment_state_label(order)}
                  </span>
                </p>
                <span class="staff-order-unpaid-sep" aria-hidden="true">·</span>
                <p class="staff-order-meta">
                  <span class={"staff-badge staff-badge--#{order.status}"}>
                    {Orders.status_label(order.status)}
                  </span>
                </p>
              </div>
              <div class="staff-order-actions">
                {mark_paid_buttons(%{order: order, id_prefix: "unpaid"})}
              </div>
            </article>
          </div>
        </aside>

        <div
          :if={@reconciliation_drawer_open}
          class="staff-orders-drawer-backdrop"
          phx-click="close_reconciliation_drawer"
          aria-hidden="true"
        />

        <aside
          class={[
            "staff-orders-unpaid-drawer",
            "staff-orders-section",
            "staff-orders-section--reconciliation",
            "staff-orders-collections",
            @reconciliation_drawer_open && "staff-orders-unpaid-drawer--open"
          ]}
          id="paymongo-reconciliations"
          role="region"
          aria-label="PayMongo reconciliation"
          aria-hidden={to_string(!@reconciliation_drawer_open)}
        >
          <header class="staff-orders-kds-head staff-orders-unpaid-drawer-head">
            <h2>Reconciliation</h2>
            <span class="staff-orders-count">{length(@paymongo_reconciliations)}</span>
            <button
              type="button"
              class="staff-orders-drawer-close"
              phx-click="close_reconciliation_drawer"
              aria-label="Close reconciliation drawer"
            >
              ×
            </button>
          </header>
          <p :if={@paymongo_reconciliations == []} class="staff-empty" id="paymongo-reconciliations-empty">
            No PayMongo reconciliation items.
          </p>
          <div :if={@paymongo_reconciliations != []} class="staff-orders-unpaid-list">
            <article
              :for={record <- @paymongo_reconciliations}
              class="staff-order-card staff-order-card--reconciliation"
              id={"paymongo-reconciliation-#{record.id}"}
            >
              <div class="staff-order-unpaid-main">
                <p class="staff-order-number">{record.order_number}</p>
                <span class="staff-order-unpaid-sep" aria-hidden="true">·</span>
                <p class="staff-order-pay">
                  <span class="staff-order-pay-amount">
                    {Orders.format_reconciliation_amount(record.amount_centavos)}
                  </span>
                </p>
                <span class="staff-order-unpaid-sep" aria-hidden="true">·</span>
                <p class="staff-order-meta staff-order-meta--session">
                  {truncate_session_id(record.paymongo_checkout_session_id)}
                </p>
              </div>
              <p class="staff-order-reconciliation-note">
                Payment captured at PayMongo — order cancelled locally
              </p>
            </article>
          </div>
        </aside>
      </div>
    </.staff_shell>
    """
  end

  defp kds_ticket(assigns) do
    source = source_badge(assigns.order)
    note = order_note(assigns.order)
    status = assigns.order.status

    assigns =
      assigns
      |> assign(:source_label, source.label)
      |> assign(:source_class, source.class)
      |> assign(:note, note)
      |> assign(:arrived?, freshly_received?(assigns.order))
      |> assign(:compact?, status in ["preparing", "ready"])
      |> assign(:handoff?, status == "ready")

    ~H"""
    <article
      class={[
        "staff-order-card",
        "staff-order-ticket",
        "staff-order-ticket--#{@order.status}",
        @compact? && "staff-order-ticket--compact",
        @handoff? && "staff-order-ticket--handoff",
        @arrived? && "staff-order-card--arrived"
      ]}
      id={"order-card-#{@order.id}"}
    >
      <div class="staff-order-ticket-body" id={"order-detail-#{@order.id}"}>
        <div :if={!@compact?} class="staff-order-ticket-source-row">
          <span
            class={["staff-order-source", @source_class]}
            id={"order-source-#{@order.id}"}
          >
            {@source_label}
          </span>
        </div>

        <div :if={@compact?} class="staff-order-ticket-id-row">
          <p class="staff-order-number">{@order.number}</p>
          <span class={["staff-order-source", @source_class, "staff-order-source--inline"]}>
            {@source_label}
          </span>
        </div>

        <p :if={!@compact?} class="staff-order-number">{@order.number}</p>
        <p class="staff-order-name">{@order.customer_name}</p>

        <ul class="staff-order-items">
          <li :for={item <- @order.items} class="staff-order-item">
            <span class="staff-order-item-qty">{item.quantity} ×</span>
            <span class="staff-order-item-detail">
              <span class="staff-order-item-name">{item.name}</span>
              <span :if={item.size} class="staff-order-item-size">{item.size}</span>
            </span>
          </li>
        </ul>

        <div :if={@note} class="staff-order-note-block">
          <p class="staff-order-note-label">NOTE</p>
          <p class="staff-order-notes">{@note}</p>
        </div>

        <p :if={@handoff? || !@compact?} class="staff-order-meta">{fulfillment_short(@order)}</p>

        <div class="staff-order-ticket-foot">
          <div class="staff-order-pay">
            <span class="staff-order-pay-amount">{Orders.format_total(@order)}</span>
            <span class={"staff-order-pay-state staff-badge--pay-#{@order.payment_status}"}>
              {payment_state_label(@order)}
            </span>
          </div>
          <p class={order_age_class(@order.inserted_at)}>{format_order_age(@order.inserted_at)}</p>
        </div>
      </div>

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
          :if={@order.status == "preparing" and not unpaid_online?(@order)}
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
          :if={@order.status == "ready" and not unpaid_online?(@order)}
          type="button"
          class="staff-action staff-action-primary staff-action-complete"
          id={"ready-complete-#{@order.id}"}
          phx-click="complete_order"
          phx-value-id={@order.id}
        >
          Picked up
        </button>

        <div :if={needs_payment_actions?(@order)} class="staff-order-secondary-actions">
          {mark_paid_buttons(%{order: @order, id_prefix: "ticket"})}
          <button
            :if={
              @order.status in ["received", "preparing"] and not checkout_session_attached?(@order)
            }
            type="button"
            class="staff-action staff-action-muted"
            id={"cancel-order-#{@order.id}"}
            phx-value-id={@order.id}
            phx-click="cancel_order"
          >
            Cancel
          </button>
          <button
            :if={show_abandon_payment?(@order)}
            type="button"
            class="staff-action staff-action-muted"
            id={"abandon-online-payment-#{@order.id}"}
            phx-value-id={@order.id}
            phx-click="abandon_online_payment"
          >
            Abandon payment
          </button>
        </div>
      </div>
    </article>
    """
  end

  defp checkout_session_attached?(%{paymongo_checkout_session_id: session_id})
       when is_binary(session_id) and session_id != "" do
    true
  end

  defp checkout_session_attached?(_order), do: false

  defp unpaid_online?(%{payment_method: "online", payment_status: status})
       when status != "paid",
       do: true

  defp unpaid_online?(_order), do: false

  defp needs_payment_actions?(%{payment_status: status})
       when status in ["unpaid", "awaiting_payment"],
       do: true

  defp needs_payment_actions?(_), do: false

  defp staff_mark_paid?(%{payment_method: "counter", payment_status: status})
       when status in ["unpaid", "awaiting_payment"],
       do: true

  defp staff_mark_paid?(%{payment_method: "online", payment_status: "awaiting_payment"}),
    do: BusinessSettings.qrph_manual?()

  defp staff_mark_paid?(_), do: false

  defp show_abandon_payment?(%{payment_method: "online", payment_status: "unpaid"} = order) do
    checkout_session_attached?(order) and not BusinessSettings.qrph_manual?()
  end

  defp show_abandon_payment?(_), do: false

  defp mark_paid_buttons(assigns) do
    ~H"""
    <div
      :if={staff_mark_paid?(@order)}
      class="staff-order-mark-paid"
      id={"#{@id_prefix}-mark-paid-#{@order.id}"}
    >
      <button
        type="button"
        class="staff-action staff-action-secondary"
        id={"#{@id_prefix}-mark-paid-cash-#{@order.id}"}
        phx-click="mark_paid"
        phx-value-id={@order.id}
        phx-value-paid_via="cash"
      >
        Cash
      </button>
      <button
        type="button"
        class="staff-action staff-action-secondary"
        id={"#{@id_prefix}-mark-paid-gcash-#{@order.id}"}
        phx-click="mark_paid"
        phx-value-id={@order.id}
        phx-value-paid_via="gcash"
      >
        GCash
      </button>
      <button
        type="button"
        class="staff-action staff-action-secondary"
        id={"#{@id_prefix}-mark-paid-maya-#{@order.id}"}
        phx-click="mark_paid"
        phx-value-id={@order.id}
        phx-value-paid_via="maya"
      >
        Maya
      </button>
      <button
        :if={@order.payment_method == "counter"}
        type="button"
        class="staff-action staff-action-secondary"
        id={"#{@id_prefix}-mark-paid-counter-#{@order.id}"}
        phx-click="mark_paid"
        phx-value-id={@order.id}
        phx-value-paid_via="counter"
      >
        Counter
      </button>
    </div>
    """
  end

  defp paid_via_label("cash"), do: "cash"
  defp paid_via_label("gcash"), do: "GCash"
  defp paid_via_label("maya"), do: "Maya"
  defp paid_via_label("counter"), do: "counter"
  defp paid_via_label(other) when is_binary(other), do: other
  defp paid_via_label(_), do: "paid"

  defp source_badge(%{source: "pos"}), do: %{label: "WALK-IN", class: "staff-order-source--pos"}
  defp source_badge(_), do: %{label: "QR", class: "staff-order-source--customer"}

  defp order_note(%{notes: notes}) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: nil, else: trimmed
  end

  defp order_note(_), do: nil

  defp freshly_received?(%{status: "received", inserted_at: %DateTime{} = inserted_at}) do
    DateTime.utc_now(:second)
    |> DateTime.diff(DateTime.truncate(inserted_at, :second), :second)
    |> then(&(&1 >= 0 and &1 < 90))
  end

  defp freshly_received?(_), do: false

  defp payment_state_label(%{payment_status: "paid"}), do: "Paid"
  defp payment_state_label(%{payment_status: "awaiting_payment"}), do: "Await QR"
  defp payment_state_label(_), do: "Unpaid"

  defp fulfillment_short(%{fulfillment: "dine_in", table_number: table})
       when is_binary(table) and table != "",
       do: "Table #{table}"

  defp fulfillment_short(%{fulfillment: "dine_in"}), do: "Dine-in"
  defp fulfillment_short(%{fulfillment: "pickup"}), do: "Pickup"
  defp fulfillment_short(_), do: "Order"

  defp format_order_age(%DateTime{} = inserted_at) do
    seconds =
      DateTime.utc_now(:second)
      |> DateTime.diff(DateTime.truncate(inserted_at, :second), :second)
      |> max(0)

    cond do
      seconds < 60 -> "Just now"
      seconds < 3600 ->
        minutes = div(seconds, 60)
        if minutes == 1, do: "1 min ago", else: "#{minutes} min ago"
      true ->
        hours = div(seconds, 3600)
        if hours == 1, do: "1 hr ago", else: "#{hours} hr ago"
    end
  end

  defp format_order_age(_), do: ""

  defp order_age_class(%DateTime{} = inserted_at) do
    minutes =
      DateTime.utc_now(:second)
      |> DateTime.diff(DateTime.truncate(inserted_at, :second), :second)
      |> max(0)
      |> div(60)

    cond do
      minutes < 3 -> ["staff-order-age"]
      minutes < 8 -> ["staff-order-age", "staff-order-age--attention"]
      minutes < 15 -> ["staff-order-age", "staff-order-age--urgent"]
      true -> ["staff-order-age", "staff-order-age--critical"]
    end
  end

  defp order_age_class(_), do: ["staff-order-age"]

  defp load_orders(socket) do
    socket
    |> assign(:active_orders, Orders.list_active_orders())
    |> assign(:ready_orders, Orders.list_recent_ready(@ready_lane_limit))
    |> assign(:unpaid_orders, Orders.list_todays_unpaid())
    |> assign(:paymongo_reconciliations, Orders.list_open_paymongo_reconciliations())
  end

  defp truncate_session_id(session_id) when is_binary(session_id) do
    if String.length(session_id) > 16 do
      String.slice(session_id, 0, 12) <> "…"
    else
      session_id
    end
  end

  defp truncate_session_id(_), do: ""
end

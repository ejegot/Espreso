defmodule EspresoWeb.StaffOrdersLive do
  use EspresoWeb, :live_view

  alias Espreso.BusinessSettings
  alias Espreso.Orders
  alias Espreso.PhysicalActionCoordinator
  alias Espreso.Printer
  alias Espreso.Repo
  alias EspresoWeb.StaffNotifications

  @ready_lane_limit 100
  @age_tick_ms 60_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Orders.subscribe()
      schedule_age_tick()
    end

    {:ok,
     socket
     |> assign(:page_title, "Orders")
     |> assign(:age_now, DateTime.utc_now(:second))
     |> assign(:flash_note, nil)
     |> assign(:unpaid_drawer_open, false)
     |> assign(:reconciliation_drawer_open, false)
     |> assign(:mark_paid_order, nil)
     |> assign(:mark_paid_recoveries, %{})
     |> assign(:cash_tender_order, nil)
     |> assign(:cash_tendered, "")
     |> assign(:cash_tender_error, nil)
     |> assign(:cash_tender_token, nil)
     |> assign(:alert_banner, nil)
     |> load_orders(), layout: false}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    unpaid_open? = Map.get(params, "unpaid") in ["1", "true"]

    {:noreply,
     assign(socket, :unpaid_drawer_open, unpaid_open? or socket.assigns.unpaid_drawer_open)}
  end

  @impl true
  def handle_info({:order_changed, order}, socket) do
    StaffNotifications.push_order_change(order)

    socket =
      socket
      |> maybe_set_alert_banner(order)
      |> load_orders()

    {:noreply, socket}
  end

  def handle_info(:age_tick, socket) do
    schedule_age_tick()
    {:noreply, assign(socket, :age_now, DateTime.utc_now(:second))}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_orders(socket)}
  end

  def handle_event("dismiss_alert", _params, socket) do
    {:noreply, assign(socket, :alert_banner, nil)}
  end

  def handle_event("toggle_unpaid_drawer", _params, socket) do
    {:noreply, assign(socket, :unpaid_drawer_open, !socket.assigns.unpaid_drawer_open)}
  end

  def handle_event("close_unpaid_drawer", _params, socket) do
    {:noreply, assign(socket, :unpaid_drawer_open, false)}
  end

  def handle_event("toggle_reconciliation_drawer", _params, socket) do
    {:noreply,
     assign(socket, :reconciliation_drawer_open, !socket.assigns.reconciliation_drawer_open)}
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
           "Confirm payment before marking this order ready."
         )}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not update order status.")}
    end
  end

  def handle_event(
        "print_kitchen",
        %{"id" => id, "action" => "kitchen", "permit" => permit},
        socket
      ) do
    result =
      PhysicalActionCoordinator.execute(id, :kitchen, permit,
        staff_name: socket.assigns.current_user.name
      )

    {:noreply,
     socket
     |> assign(:flash_note, physical_action_note(:kitchen, result))
     |> load_orders()}
  end

  def handle_event("print_kitchen", _params, socket) do
    {:noreply, assign(socket, :flash_note, "Kitchen request is stale. No ticket was sent.")}
  end

  def handle_event(
        "reprint_receipt",
        %{"id" => id, "action" => "receipt_reprint", "permit" => permit},
        socket
      ) do
    result =
      PhysicalActionCoordinator.execute_reprint(id, :receipt_reprint, permit,
        staff_name: socket.assigns.current_user.name
      )

    {:noreply,
     socket
     |> assign(:flash_note, reprint_note(result))
     |> load_orders()}
  end

  def handle_event("reprint_receipt", _params, socket) do
    {:noreply, assign(socket, :flash_note, "Reprint request is stale. No receipt was sent.")}
  end

  def handle_event(
        "open_drawer",
        %{"id" => id, "action" => "drawer", "permit" => permit},
        socket
      ) do
    result =
      PhysicalActionCoordinator.execute(id, :drawer, permit,
        staff_name: socket.assigns.current_user.name
      )

    {:noreply,
     socket
     |> assign(:flash_note, physical_action_note(:drawer, result))
     |> load_orders()}
  end

  def handle_event("open_drawer", _params, socket) do
    {:noreply, assign(socket, :flash_note, "Kaha request is stale. Drawer was not opened.")}
  end

  def handle_event("open_mark_paid", %{"id" => id}, socket) do
    with {order_id, ""} <- Integer.parse(id),
         %Espreso.Orders.Order{} = order <- Repo.get(Espreso.Orders.Order, order_id) do
      if modal_payment_action?(order) do
        {:noreply, assign(socket, :mark_paid_order, order)}
      else
        {:noreply, socket}
      end
    else
      _ -> {:noreply, assign(socket, :flash_note, "Could not mark order paid.")}
    end
  end

  def handle_event("close_mark_paid", _params, socket) do
    {:noreply, assign(socket, :mark_paid_order, nil)}
  end

  def handle_event("open_cash_tender", %{"id" => id}, socket) do
    socket = load_orders(socket)

    with {order_id, ""} <- Integer.parse(id),
         %Espreso.Orders.Order{} = order <- Repo.get(Espreso.Orders.Order, order_id),
         true <- cash_payment_action?(order),
         permit when is_binary(permit) <- Map.get(socket.assigns.mark_paid_permits, order_id) do
      {:noreply,
       socket
       |> assign(:mark_paid_order, nil)
       |> assign(:cash_tender_order, order)
       |> assign(:cash_tendered, "")
       |> assign(:cash_tender_error, nil)
       |> assign(:cash_tender_token, new_cash_tender_token())}
    else
      _ ->
        {:noreply,
         socket
         |> close_cash_tender()
         |> assign(:flash_note, "Could not mark order paid.")}
    end
  end

  def handle_event("open_cash_tender", _params, socket) do
    {:noreply, assign(socket, :flash_note, "Could not mark order paid.")}
  end

  def handle_event(
        "set_order_cash_tendered",
        %{"cash_tendered" => amount},
        %{assigns: %{cash_tender_order: %Espreso.Orders.Order{}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:cash_tendered, String.trim(amount))
     |> assign(:cash_tender_error, nil)}
  end

  def handle_event("set_order_cash_tendered", _params, socket), do: {:noreply, socket}

  def handle_event(
        "order_cash_exact",
        _params,
        %{assigns: %{cash_tender_order: %Espreso.Orders.Order{total: total}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:cash_tendered, money_input(total))
     |> assign(:cash_tender_error, nil)}
  end

  def handle_event("order_cash_exact", _params, socket), do: {:noreply, socket}

  def handle_event(
        "order_cash_chip",
        %{"amount" => amount},
        %{assigns: %{cash_tender_order: %Espreso.Orders.Order{}}} = socket
      ) do
    case parse_money(amount) do
      {:ok, tendered} ->
        {:noreply,
         socket
         |> assign(:cash_tendered, money_input(tendered))
         |> assign(:cash_tender_error, nil)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("order_cash_chip", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_order_cash_tender", _params, socket) do
    {:noreply, close_cash_tender(socket)}
  end

  def handle_event("confirm_order_cash_tender", params, socket) do
    tendered = Map.get(params, "cash_tendered", socket.assigns.cash_tendered)
    token = Map.get(params, "cash_tender_token")
    socket = assign(socket, :cash_tendered, String.trim(to_string(tendered)))

    cond do
      is_nil(socket.assigns.cash_tender_order) ->
        {:noreply, socket}

      token != socket.assigns.cash_tender_token ->
        {:noreply, assign(socket, :cash_tender_error, "This cash entry is no longer active.")}

      true ->
        confirm_order_cash_tender(socket)
    end
  end

  def handle_event(
        "mark_paid",
        %{"id" => id, "action" => "mark_paid", "permit" => permit} = params,
        socket
      ) do
    paid_via = Map.get(params, "paid_via", "counter")

    result =
      PhysicalActionCoordinator.execute_mark_paid(id, permit, paid_via,
        staff_name: socket.assigns.current_user.name
      )

    case result do
      {:ok, :transitioned, paid, physical_result} ->
        {:noreply,
         socket
         |> assign(:mark_paid_order, nil)
         |> update_mark_paid_recovery(paid.id, paid.paid_via || paid_via, physical_result)
         |> assign(:flash_note, mark_paid_flash(paid, paid_via, physical_result))
         |> load_orders()}

      {:ok, :already_paid, paid} ->
        {:noreply,
         socket
         |> assign(:mark_paid_order, nil)
         |> assign(:flash_note, mark_paid_flash(paid, paid.paid_via || paid_via, :disabled))
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

      {:ineligible, :cancelled} ->
        {:noreply, assign(socket, :flash_note, "Cancelled orders cannot be marked paid.")}

      {:ineligible, :online_payment_required} ->
        {:noreply,
         assign(
           socket,
           :flash_note,
           "This online order cannot be marked paid manually — wait for PayMongo or switch to QRPh mode."
         )}

      {:ineligible, reason} ->
        if recoverable_payment_choice_error?(reason) do
          {:noreply,
           socket
           |> assign(:flash_note, "Could not mark order paid.")
           |> load_orders()}
        else
          {:noreply, assign(socket, :flash_note, "Could not mark order paid.")}
        end

      _ ->
        {:noreply, assign(socket, :flash_note, "Could not mark order paid.")}
    end
  end

  def handle_event("mark_paid", _params, socket) do
    {:noreply, assign(socket, :flash_note, "Could not mark order paid.")}
  end

  def handle_event(
        "retry_mark_paid",
        %{
          "id" => id,
          "action" => "mark_paid",
          "permit" => permit,
          "paid_via" => paid_via,
          "phase" => phase
        },
        socket
      ) do
    result =
      PhysicalActionCoordinator.execute_mark_paid(id, permit, paid_via,
        staff_name: socket.assigns.current_user.name
      )

    {:noreply,
     socket
     |> handle_mark_paid_recovery_result(id, paid_via, phase, result)
     |> load_orders()}
  end

  def handle_event("retry_mark_paid", _params, socket) do
    {:noreply, assign(socket, :flash_note, "Could not mark order paid.")}
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
           "Confirm payment before marking this order picked up."
         )}

      {:error, _} ->
        {:noreply, assign(socket, :flash_note, "Could not mark order picked up.")}
    end
  end

  @impl true
  def render(assigns) do
    received = Enum.filter(assigns.active_orders, &(&1.status == "received"))
    preparing = Enum.filter(assigns.active_orders, &(&1.status == "preparing"))
    waiting = Enum.count(received, &waiting_for_online_payment?/1)
    actionable = length(received) - waiting

    assigns =
      assigns
      |> assign(:received_orders, received)
      |> assign(:preparing_orders, preparing)
      |> assign(:waiting_received_count, waiting)
      |> assign(:actionable_received_count, actionable)

    ~H"""
    <.staff_shell current={:orders} current_user={@current_user} page_title="Orders">
      <:tools>
        <a
          href="#orders-new"
          class="staff-shell-tool staff-orders-header-tool staff-orders-header-tool--new"
          id="orders-new-header-link"
          aria-label={"New orders: #{length(@received_orders)}"}
        >
          <span>New</span>
          <span
            :if={@received_orders != []}
            class="staff-orders-tool-badge staff-orders-tool-badge--new"
            id="orders-new-header-count"
          >
            {length(@received_orders)}
          </span>
        </a>
        <button
          type="button"
          class="staff-shell-tool staff-orders-header-tool staff-orders-unpaid-toggle"
          id="unpaid-drawer-toggle"
          phx-click="toggle_unpaid_drawer"
          aria-expanded={to_string(@unpaid_drawer_open)}
          aria-controls="unpaid-orders"
          aria-label={"Unpaid orders: #{length(@unpaid_orders)}"}
        >
          <span>Unpaid</span>
          <span
            :if={@unpaid_orders != []}
            class="staff-orders-tool-badge staff-orders-tool-badge--unpaid"
            id="orders-unpaid-header-count"
          >
            {length(@unpaid_orders)}
          </span>
        </button>
        <button
          :if={@paymongo_reconciliations != []}
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
        <button
          type="button"
          class="staff-shell-tool staff-shell-tool--quiet staff-orders-header-icon staff-orders-refresh"
          id="orders-refresh"
          phx-click="refresh"
          title="Refresh board"
          aria-label="Refresh board"
        >
          <.icon name="hero-arrow-path" class="staff-orders-refresh-icon" />
        </button>
      </:tools>

      <div class="staff-orders-page staff-orders-shell-root">
        <main class="staff-orders-main">
          <p :if={@flash_note} class="staff-admin-note" id="orders-flash">{@flash_note}</p>

          <nav class="staff-orders-lane-jumps" aria-label="Jump to order lane">
            <a href="#orders-new" class="staff-orders-lane-jump staff-orders-lane-jump--new">
              New <span>{@actionable_received_count + @waiting_received_count}</span>
            </a>
            <a href="#orders-preparing" class="staff-orders-lane-jump">
              Preparing <span>{length(@preparing_orders)}</span>
            </a>
            <a href="#orders-ready" class="staff-orders-lane-jump">
              Ready <span>{length(@ready_orders)}</span>
            </a>
          </nav>

          <div :if={@alert_banner} class="staff-orders-alert" id="orders-alert-banner" role="status">
            <div class="staff-orders-alert-copy">
              <p class="staff-orders-alert-title">New order {@alert_banner.number}</p>
              <p class="staff-orders-alert-body">
                {@alert_banner.name} · Jump to New lane
              </p>
            </div>
            <div class="staff-orders-alert-actions">
              <a
                href={"#order-card-new-#{@alert_banner.id}"}
                class="staff-orders-alert-jump"
                id="orders-alert-jump"
              >
                View
              </a>
              <button
                type="button"
                class="staff-orders-alert-dismiss"
                id="orders-alert-dismiss"
                phx-click="dismiss_alert"
              >
                Dismiss
              </button>
            </div>
          </div>

          <div class="staff-orders-board">
            <div
              class="staff-orders-workboard"
              id="orders-kitchen"
              phx-hook="StaffOrdersBoard"
              role="region"
              aria-label="Kitchen"
            >
              <section class="staff-orders-kds-lane staff-orders-kds-lane--new" id="orders-new">
                <header class="staff-orders-kds-head staff-orders-kds-head--new">
                  <div class="staff-orders-kds-head-main">
                    <h2>New</h2>
                    <p
                      :if={@waiting_received_count > 0}
                      class="staff-orders-workflow-hint"
                      id="orders-new-workload"
                    >
                      <strong>{@actionable_received_count} need staff</strong>
                      <span>· {@waiting_received_count} waiting online</span>
                    </p>
                  </div>
                  <span class="staff-orders-count">{length(@received_orders)}</span>
                </header>
                <div class="staff-orders-lane-grid">
                  <p :if={@received_orders == []} class="staff-empty">No new orders.</p>
                  <.kds_ticket
                    :for={order <- @received_orders}
                    order={order}
                    lane="new"
                    age_now={@age_now}
                    reprint_permit={Map.get(@reprint_permits, order.id)}
                    kitchen_permit={Map.get(@kitchen_permits, order.id)}
                    drawer_permit={Map.get(@drawer_permits, order.id)}
                    mark_paid_permit={Map.get(@mark_paid_permits, order.id)}
                    mark_paid_recovery={Map.get(@mark_paid_recoveries, order.id)}
                  />
                </div>
              </section>

              <section
                class="staff-orders-kds-lane staff-orders-kds-lane--preparing"
                id="orders-preparing"
              >
                <header class="staff-orders-kds-head staff-orders-kds-head--preparing">
                  <div class="staff-orders-kds-head-main">
                    <h2>Preparing</h2>
                  </div>
                  <span class="staff-orders-count">{length(@preparing_orders)}</span>
                </header>
                <div class="staff-orders-lane-grid">
                  <p :if={@preparing_orders == []} class="staff-empty">Nothing preparing.</p>
                  <.kds_ticket
                    :for={order <- @preparing_orders}
                    order={order}
                    lane="preparing"
                    age_now={@age_now}
                    reprint_permit={Map.get(@reprint_permits, order.id)}
                    kitchen_permit={Map.get(@kitchen_permits, order.id)}
                    drawer_permit={Map.get(@drawer_permits, order.id)}
                    mark_paid_permit={Map.get(@mark_paid_permits, order.id)}
                    mark_paid_recovery={Map.get(@mark_paid_recoveries, order.id)}
                  />
                </div>
              </section>

              <section class="staff-orders-kds-lane staff-orders-kds-lane--ready" id="orders-ready">
                <header class="staff-orders-kds-head staff-orders-kds-head--ready">
                  <div class="staff-orders-kds-head-main">
                    <h2>Ready</h2>
                  </div>
                  <span class="staff-orders-count">{length(@ready_orders)}</span>
                </header>
                <div class="staff-orders-lane-grid">
                  <p :if={@ready_orders == []} class="staff-empty">None yet.</p>
                  <.kds_ticket
                    :for={order <- @ready_orders}
                    order={order}
                    lane="ready"
                    age_now={@age_now}
                    reprint_permit={Map.get(@reprint_permits, order.id)}
                    kitchen_permit={Map.get(@kitchen_permits, order.id)}
                    drawer_permit={Map.get(@drawer_permits, order.id)}
                    mark_paid_permit={Map.get(@mark_paid_permits, order.id)}
                    mark_paid_recovery={Map.get(@mark_paid_recoveries, order.id)}
                  />
                </div>
              </section>
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
                  <span :if={paid_via_badge(order)} class="staff-order-pay-via">
                    {paid_via_badge(order)}
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
                {payment_action_buttons(%{
                  order: order,
                  id_prefix: "unpaid",
                  lane: "drawer",
                  mark_paid_permit: Map.get(@mark_paid_permits, order.id)
                })}
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
          <p
            :if={@paymongo_reconciliations == []}
            class="staff-empty"
            id="paymongo-reconciliations-empty"
          >
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

        {order_cash_tender_modal(assigns)}
        {mark_paid_modal(assigns)}
      </div>
    </.staff_shell>
    """
  end

  attr :order, :map, required: true
  attr :lane, :string, default: "ticket"
  attr :age_now, DateTime, required: true
  attr :reprint_permit, :string, default: nil
  attr :kitchen_permit, :string, default: nil
  attr :drawer_permit, :string, default: nil
  attr :mark_paid_permit, :string, default: nil
  attr :mark_paid_recovery, :map, default: nil

  defp kds_ticket(assigns) do
    source = source_badge(assigns.order)
    note = order_note(assigns.order)
    status = assigns.order.status

    assigns =
      assigns
      |> assign(:source_label, source.label)
      |> assign(:source_class, source.class)
      |> assign(:note, note)
      |> assign(:arrived?, freshly_received?(assigns.order, assigns.age_now))
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
      id={"order-card-#{@lane}-#{@order.id}"}
    >
      <div class="staff-order-ticket-body" id={"order-detail-#{@lane}-#{@order.id}"}>
        <div :if={!@compact?} class="staff-order-ticket-source-row">
          <span
            class={["staff-order-source", @source_class]}
            id={"order-source-#{@lane}-#{@order.id}"}
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
        <p :if={show_customer_name?(@order)} class="staff-order-name">{@order.customer_name}</p>

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

        <p class="staff-order-meta">{fulfillment_short(@order)}</p>

        <div class="staff-order-ticket-foot">
          <div class="staff-order-pay">
            <span class="staff-order-pay-amount">{Orders.format_total(@order)}</span>
            <span class={"staff-order-pay-state staff-badge--pay-#{@order.payment_status}"}>
              {payment_state_label(@order)}
            </span>
            <span :if={paid_via_badge(@order)} class="staff-order-pay-via">
              {paid_via_badge(@order)}
            </span>
          </div>
          <p class={order_age_class(@order.inserted_at, @age_now)}>
            {format_order_age(@order.inserted_at, @age_now)}
          </p>
        </div>
      </div>

      <div class="staff-order-actions">
        <div :if={needs_payment_actions?(@order)} class="staff-order-pay-actions">
          <p :if={waiting_for_online_payment?(@order)} class="staff-order-payment-waiting">
            Waiting for online payment
          </p>
          {payment_action_buttons(%{
            order: @order,
            id_prefix: "ticket",
            lane: @lane,
            mark_paid_permit: @mark_paid_permit
          })}
        </div>

        <button
          :if={@order.status == "received" and not Orders.unpaid?(@order)}
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
          :if={@order.status == "preparing" and not Orders.unpaid?(@order)}
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
          :if={@order.status == "ready" and not Orders.unpaid?(@order)}
          type="button"
          class="staff-action staff-action-primary staff-action-complete"
          id={"ready-complete-#{@order.id}"}
          phx-click="complete_order"
          phx-value-id={@order.id}
        >
          Picked up
        </button>

        <div
          :if={show_cancel_action?(@order) or ticket_overflow_actions?(@order)}
          class="staff-order-secondary-row"
        >
          <button
            :if={show_cancel_action?(@order)}
            type="button"
            class="staff-action staff-action-cancel"
            id={"cancel-order-#{@order.id}"}
            phx-value-id={@order.id}
            phx-click="cancel_order"
          >
            Cancel
          </button>

          <details
            :if={ticket_overflow_actions?(@order)}
            class="staff-order-more"
            id={"order-more-#{@order.id}"}
          >
            <summary class="staff-order-more-summary" aria-label="More actions">⋯</summary>
            <div class="staff-order-more-panel">
              <button
                :if={show_abandon_payment?(@order)}
                type="button"
                class="staff-action staff-action-muted"
                id={"abandon-online-payment-#{@order.id}"}
                phx-value-id={@order.id}
                phx-click="abandon_online_payment"
              >
                Abandon
              </button>
              <button
                :if={
                  Printer.enabled?() and @order.status in ["received", "preparing", "ready"] and
                    is_binary(@kitchen_permit)
                }
                type="button"
                class="staff-action staff-action-muted"
                id={"kitchen-#{@order.id}"}
                phx-click="print_kitchen"
                phx-value-id={@order.id}
                phx-value-action="kitchen"
                phx-value-permit={@kitchen_permit}
              >
                Kitchen
              </button>
              <button
                :if={
                  @order.payment_status == "paid" and Printer.enabled?() and
                    (is_binary(@reprint_permit) or
                       match?(%{phase: :receipt}, @mark_paid_recovery))
                }
                type="button"
                class="staff-action staff-action-muted"
                id={"reprint-#{@order.id}"}
                phx-click={
                  if match?(%{phase: :receipt}, @mark_paid_recovery),
                    do: "retry_mark_paid",
                    else: "reprint_receipt"
                }
                phx-value-id={@order.id}
                phx-value-action={
                  if match?(%{phase: :receipt}, @mark_paid_recovery),
                    do: "mark_paid",
                    else: "receipt_reprint"
                }
                phx-value-permit={
                  if match?(
                       %{phase: :receipt, permit: permit} when is_binary(permit),
                       @mark_paid_recovery
                     ),
                     do: @mark_paid_recovery.permit,
                     else: @reprint_permit
                }
                phx-value-paid_via={
                  if @mark_paid_recovery, do: @mark_paid_recovery.paid_via, else: nil
                }
                phx-value-phase="receipt"
              >
                Reprint
              </button>
              <button
                :if={
                  @order.payment_status == "paid" and Printer.enabled?() and
                    Printer.cash_like?(@order.paid_via || "counter") and
                    (is_binary(@drawer_permit) or
                       match?(%{phase: :drawer}, @mark_paid_recovery))
                }
                type="button"
                class="staff-action staff-action-muted"
                id={"open-drawer-#{@order.id}"}
                phx-click={
                  if match?(%{phase: :drawer}, @mark_paid_recovery),
                    do: "retry_mark_paid",
                    else: "open_drawer"
                }
                phx-value-id={@order.id}
                phx-value-action={
                  if match?(%{phase: :drawer}, @mark_paid_recovery),
                    do: "mark_paid",
                    else: "drawer"
                }
                phx-value-permit={
                  if match?(
                       %{phase: :drawer, permit: permit} when is_binary(permit),
                       @mark_paid_recovery
                     ),
                     do: @mark_paid_recovery.permit,
                     else: @drawer_permit
                }
                phx-value-paid_via={
                  if @mark_paid_recovery, do: @mark_paid_recovery.paid_via, else: nil
                }
                phx-value-phase="drawer"
              >
                Kaha
              </button>
            </div>
          </details>
        </div>
      </div>
    </article>
    """
  end

  defp show_cancel_action?(order) do
    order.status in ["received", "preparing"] and not checkout_session_attached?(order) and
      needs_payment_actions?(order)
  end

  defp ticket_overflow_actions?(order) do
    abandon? = show_abandon_payment?(order)

    kitchen? =
      Printer.enabled?() and order.status in ["received", "preparing", "ready"]

    paid_print? = order.payment_status == "paid" and Printer.enabled?()

    abandon? or kitchen? or paid_print?
  end

  defp checkout_session_attached?(%{paymongo_checkout_session_id: session_id})
       when is_binary(session_id) and session_id != "" do
    true
  end

  defp checkout_session_attached?(_order), do: false

  defp needs_payment_actions?(%{payment_status: status})
       when status in ["unpaid", "awaiting_payment"],
       do: true

  defp needs_payment_actions?(_), do: false

  defp waiting_for_online_payment?(order), do: payment_action_projection(order) == :waiting

  defp staff_mark_paid?(order),
    do: match?({kind, _options} when kind in [:inline, :modal], payment_action_projection(order))

  defp modal_payment_action?(order),
    do: match?({:modal, _options}, payment_action_projection(order))

  defp show_abandon_payment?(%{payment_method: "online", payment_status: "unpaid"} = order) do
    checkout_session_attached?(order) and not BusinessSettings.qrph_manual?()
  end

  defp show_abandon_payment?(_), do: false

  defp payment_action_buttons(assigns) do
    case payment_action_projection(assigns.order) do
      {:inline, options} ->
        assigns = Map.put(assigns, :options, options)

        ~H"""
        <div class="staff-order-paid-via-row" role="group" aria-label="Confirm payment method">
          <button
            :for={{paid_via, label} <- @options}
            type="button"
            class="staff-action staff-action-primary staff-action-paid-via"
            id={"#{@id_prefix}-#{@lane}-paid-via-#{paid_via}-#{@order.id}"}
            phx-click={if(paid_via == "cash", do: "open_cash_tender", else: "mark_paid")}
            phx-value-id={@order.id}
            phx-value-paid_via={paid_via}
            phx-value-action="mark_paid"
            phx-value-permit={@mark_paid_permit}
          >
            {label}
          </button>
        </div>
        """

      {:modal, _options} ->
        ~H"""
        <button
          type="button"
          class="staff-action staff-action-primary staff-action-mark-paid"
          id={"#{@id_prefix}-#{@lane}-mark-paid-#{@order.id}"}
          phx-click="open_mark_paid"
          phx-value-id={@order.id}
        >
          Confirm payment
        </button>
        """

      _ ->
        ""
    end
  end

  defp payment_action_projection(%{status: "cancelled"}), do: :none

  defp payment_action_projection(%{payment_status: status})
       when status not in ["unpaid", "awaiting_payment"],
       do: :none

  defp payment_action_projection(%{payment_method: "counter", payment_intent: "cash"}),
    do: {:inline, [{"cash", "Cash"}]}

  defp payment_action_projection(%{payment_method: "counter", payment_intent: nil}),
    do: {:inline, legacy_counter_payment_options()}

  defp payment_action_projection(%{
         payment_method: "online",
         payment_intent: wallet,
         payment_status: "awaiting_payment"
       })
       when wallet in ["gcash", "maya"] do
    if BusinessSettings.qrph_manual?() do
      {:modal, [{wallet, wallet_label(wallet), :primary}]}
    else
      :waiting
    end
  end

  defp payment_action_projection(%{
         payment_method: "online",
         payment_intent: nil,
         payment_status: "awaiting_payment"
       }) do
    if BusinessSettings.qrph_manual?() do
      {:modal, legacy_online_payment_options()}
    else
      :waiting
    end
  end

  defp payment_action_projection(%{
         payment_method: "online",
         payment_intent: wallet
       })
       when wallet in [nil, "gcash", "maya"],
       do: :waiting

  defp payment_action_projection(_order), do: :none

  defp cash_payment_action?(order) do
    case payment_action_projection(order) do
      {:inline, options} ->
        Enum.any?(options, fn {paid_via, _label} -> paid_via == "cash" end)

      {:modal, options} ->
        Enum.any?(options, fn {paid_via, _label, _kind} -> paid_via == "cash" end)

      _ ->
        false
    end
  end

  defp legacy_counter_payment_options do
    [{"cash", "Cash"}, {"gcash", "GCash"}, {"maya", "Maya"}]
  end

  defp legacy_online_payment_options do
    [
      {"gcash", "GCash", :primary},
      {"maya", "Maya", :primary},
      {"cash", "Paid cash instead", :escape}
    ]
  end

  defp order_cash_tender_modal(%{cash_tender_order: nil}), do: nil

  defp order_cash_tender_modal(assigns) do
    order = assigns.cash_tender_order
    total = Decimal.round(order.total, 2)
    tender_state = cash_tender_state(assigns.cash_tendered, total)

    assigns =
      assigns
      |> assign(:order, order)
      |> assign(:total, total)
      |> assign(:tender_state, tender_state)
      |> assign(:quick_tenders, cash_quick_tenders(total))
      |> assign(:confirm_enabled?, cash_tender_valid?(tender_state))
      |> assign(:mark_paid_permit, Map.get(assigns.mark_paid_permits, order.id))

    ~H"""
    <div
      class="staff-mark-paid-modal"
      id="orders-cash-tender-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="orders-cash-tender-modal-title"
    >
      <button
        type="button"
        class="staff-mark-paid-modal-backdrop"
        phx-click="cancel_order_cash_tender"
        aria-label="Close Cash Received dialog"
      />
      <div class="staff-mark-paid-modal-panel staff-pos-cash-modal">
        <header class="staff-mark-paid-modal-head staff-pos-cash-modal-head">
          <div>
            <p class="staff-mark-paid-modal-eyebrow">Cash payment</p>
            <h2 id="orders-cash-tender-modal-title" class="staff-mark-paid-modal-title">
              Cash Received
            </h2>
            <p class="staff-mark-paid-modal-sub">
              {@order.number} · {@order.customer_name}
            </p>
          </div>
          <button
            type="button"
            class="staff-mark-paid-modal-close"
            phx-click="cancel_order_cash_tender"
            aria-label="Close Cash Received dialog"
          >
            ×
          </button>
        </header>

        <div class="staff-pos-cash-total" id="orders-cash-total">
          <span>Order total</span>
          <strong>{Orders.format_total(@order)}</strong>
        </div>

        <form
          id="orders-cash-tender-form"
          phx-change="set_order_cash_tendered"
          phx-submit="confirm_order_cash_tender"
        >
          <input type="hidden" name="cash_tender_token" value={@cash_tender_token} />

          <label class="staff-pos-cash-field" for="orders-cash-tendered">
            <span>Cash received</span>
            <span class="staff-pos-cash-input-wrap">
              <span aria-hidden="true">₱</span>
              <input
                type="text"
                inputmode="decimal"
                autocomplete="off"
                id="orders-cash-tendered"
                name="cash_tendered"
                value={@cash_tendered}
                placeholder="0.00"
                aria-describedby="orders-cash-tender-feedback"
                aria-invalid={to_string(@tender_state == :invalid or not is_nil(@cash_tender_error))}
              />
            </span>
          </label>

          <div class="staff-pos-cash-quick" id="orders-cash-quick-tenders">
            <button
              type="button"
              id="orders-cash-exact"
              phx-click="order_cash_exact"
              aria-label="Set cash received to the exact order total"
            >
              Exact
            </button>
            <button
              :for={amount <- @quick_tenders}
              type="button"
              id={"orders-cash-preset-#{Decimal.to_integer(amount)}"}
              phx-click="order_cash_chip"
              phx-value-amount={Decimal.to_string(amount, :normal)}
              aria-label={"Set cash received to #{format_money(amount)}"}
            >
              {format_money(amount)}
            </button>
          </div>

          <div
            class={[
              "staff-pos-cash-feedback",
              match?({:short, _, _}, @tender_state) && "is-short",
              (@tender_state == :invalid or not is_nil(@cash_tender_error)) && "is-error"
            ]}
            id="orders-cash-tender-feedback"
            aria-live="polite"
          >
            <%= case @tender_state do %>
              <% {:exact, _tendered, change} -> %>
                <span>Exact</span>
                <strong>{format_money(change)} change</strong>
              <% {:change, _tendered, change} -> %>
                <span>Change</span>
                <strong>{format_money(change)}</strong>
              <% {:short, _tendered, needed} -> %>
                <span>Still needed</span>
                <strong>{format_money(needed)}</strong>
              <% :invalid -> %>
                <span>Enter a valid amount with up to 2 decimal places.</span>
              <% :blank -> %>
                <span>Enter cash received or choose a quick amount.</span>
            <% end %>
            <span :if={@cash_tender_error} class="staff-pos-cash-feedback-error">
              {@cash_tender_error}
            </span>
          </div>

          <div class="staff-pos-cash-modal-actions">
            <button
              type="button"
              class="staff-action"
              id="orders-cancel-cash"
              phx-click="cancel_order_cash_tender"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="staff-action staff-action-primary"
              id="orders-confirm-cash"
              disabled={!@confirm_enabled? or not is_binary(@mark_paid_permit)}
              phx-disable-with="Processing…"
            >
              Confirm Cash
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp mark_paid_modal(%{mark_paid_order: nil}), do: nil

  defp mark_paid_modal(assigns) do
    order = assigns.mark_paid_order
    {:modal, options} = payment_action_projection(order)

    assigns =
      assigns
      |> assign(:order, order)
      |> assign(:mark_paid_permit, Map.get(assigns.mark_paid_permits, order.id))
      |> assign(:suggested_paid_via, suggested_paid_via(order))
      |> assign(:mark_paid_options, options)
      |> assign(:mark_paid_note, mark_paid_note(order))

    ~H"""
    <div class="staff-mark-paid-modal" id="mark-paid-modal" role="dialog" aria-modal="true">
      <button
        type="button"
        class="staff-mark-paid-modal-backdrop"
        phx-click="close_mark_paid"
        aria-label="Close payment dialog"
      />
      <div class="staff-mark-paid-modal-panel">
        <header class="staff-mark-paid-modal-head">
          <div>
            <p class="staff-mark-paid-modal-eyebrow">Confirm payment</p>
            <h2 class="staff-mark-paid-modal-title">{@order.number}</h2>
            <p class="staff-mark-paid-modal-sub">
              {@order.customer_name} · {Orders.format_total(@order)}
            </p>
          </div>
          <button type="button" class="staff-mark-paid-modal-close" phx-click="close_mark_paid">
            ×
          </button>
        </header>

        <p class="staff-mark-paid-modal-note">{@mark_paid_note}</p>

        <div class="staff-mark-paid-modal-options">
          <button
            :for={{paid_via, label, kind} <- @mark_paid_options}
            type="button"
            class={[
              "staff-mark-paid-option",
              kind == :escape && "staff-mark-paid-option--escape",
              @suggested_paid_via == paid_via && "is-suggested"
            ]}
            id={"mark-paid-modal-#{paid_via}"}
            phx-click={if(paid_via == "cash", do: "open_cash_tender", else: "mark_paid")}
            phx-value-id={@order.id}
            phx-value-paid_via={paid_via}
            phx-value-action="mark_paid"
            phx-value-permit={@mark_paid_permit}
          >
            {label}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp mark_paid_note(%{payment_method: "online", payment_intent: wallet})
       when wallet in ["gcash", "maya"] do
    "Expected #{wallet_label(wallet)}. Confirm that payment was received."
  end

  defp mark_paid_note(%{payment_method: "online"}) do
    "Confirm GCash or Maya. Use cash only if they paid at the counter instead."
  end

  defp mark_paid_note(_order) do
    "How did they pay? This clears unpaid and updates today’s totals."
  end

  defp suggested_paid_via(%{payment_method: "online", payment_intent: wallet})
       when wallet in ["gcash", "maya"],
       do: wallet

  defp suggested_paid_via(%{payment_method: "online"}), do: "gcash"

  defp suggested_paid_via(_), do: "cash"

  defp wallet_label("gcash"), do: "GCash"
  defp wallet_label("maya"), do: "Maya"
  defp wallet_label(_), do: "QR"

  defp paid_via_label("cash"), do: "cash"
  defp paid_via_label("gcash"), do: "GCash"
  defp paid_via_label("maya"), do: "Maya"
  defp paid_via_label("counter"), do: "counter"
  defp paid_via_label(other) when is_binary(other), do: other
  defp paid_via_label(_), do: "paid"

  defp mark_paid_flash(%{number: number, status: status}, paid_via, result) do
    base = "#{number} marked paid (#{paid_via_label(paid_via)})."

    base =
      if status == "preparing" do
        String.trim_trailing(base, ".") <> " · Preparing."
      else
        base
      end

    case result do
      :ok ->
        if Printer.cash_like?(paid_via) do
          base <> " Receipt printed · kaha opened."
        else
          base <> " Receipt printed."
        end

      {:dispatched, :receipt_and_drawer} ->
        base <> " Receipt printed · kaha opened."

      {:dispatched, :receipt} ->
        base <> " Receipt printed."

      {:definite_failure, _phase, :printer_disabled, _permit} ->
        base

      {:definite_failure, _phase, reason, _permit} ->
        base <> " Print failed (#{inspect(reason)})."

      {:uncertain, _phase, reason} ->
        base <> " Print failed (#{inspect(reason)})."

      :disabled ->
        base

      {:error, reason} ->
        base <> " Print failed (#{inspect(reason)})."
    end
  end

  defp recoverable_payment_choice_error?(:invalid_paid_via), do: true
  defp recoverable_payment_choice_error?(:paymongo_authority_required), do: true
  defp recoverable_payment_choice_error?(:payment_channel_mismatch), do: true

  defp recoverable_payment_choice_error?({
         :payment_intent_mismatch,
         _payment_intent,
         _paid_via
       }),
       do: true

  defp recoverable_payment_choice_error?(_reason), do: false

  defp confirm_order_cash_tender(socket) do
    order_id = socket.assigns.cash_tender_order.id
    socket = load_orders(socket)

    with %Espreso.Orders.Order{} = order <- Repo.get(Espreso.Orders.Order, order_id),
         true <- cash_payment_action?(order),
         {:ok, _tendered, _change} <-
           valid_cash_tender(socket.assigns.cash_tendered, order.total),
         permit when is_binary(permit) <- Map.get(socket.assigns.mark_paid_permits, order.id) do
      socket
      |> close_cash_tender()
      |> then(
        &handle_event(
          "mark_paid",
          %{
            "id" => Integer.to_string(order.id),
            "action" => "mark_paid",
            "permit" => permit,
            "paid_via" => "cash"
          },
          &1
        )
      )
    else
      {:error, message} ->
        {:noreply, assign(socket, :cash_tender_error, message)}

      _ ->
        {:noreply,
         socket
         |> close_cash_tender()
         |> load_orders()
         |> assign(:flash_note, "Could not mark order paid.")}
    end
  end

  defp close_cash_tender(socket) do
    socket
    |> assign(:cash_tender_order, nil)
    |> assign(:cash_tendered, "")
    |> assign(:cash_tender_error, nil)
    |> assign(:cash_tender_token, nil)
  end

  defp valid_cash_tender(amount, total) do
    case cash_tender_state(amount, total) do
      {:exact, tendered, change} ->
        {:ok, tendered, change}

      {:change, tendered, change} ->
        {:ok, tendered, change}

      {:short, _tendered, needed} ->
        {:error, "Cash received is short by #{format_money(needed)}."}

      :blank ->
        {:error, "Enter the cash received."}

      :invalid ->
        {:error, "Enter a valid cash amount with up to 2 decimal places."}
    end
  end

  defp parse_money(amount) when is_binary(amount) do
    amount = String.trim(amount)

    if Regex.match?(~r/^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$|^\.\d{1,2}$/, amount) do
      cleaned = String.replace(amount, ",", "")

      case Decimal.parse(cleaned) do
        {decimal, ""} ->
          if Decimal.compare(decimal, Decimal.new(0)) == :gt do
            {:ok, Decimal.round(decimal, 2)}
          else
            :error
          end

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp parse_money(_), do: :error

  defp cash_tender_state(amount, total) do
    total = Decimal.round(total, 2)

    if is_binary(amount) and String.trim(amount) == "" do
      :blank
    else
      case parse_money(amount) do
        {:ok, tendered} ->
          case Decimal.compare(tendered, total) do
            :lt -> {:short, tendered, Decimal.sub(total, tendered)}
            :eq -> {:exact, tendered, Decimal.new("0.00")}
            :gt -> {:change, tendered, Decimal.sub(tendered, total)}
          end

        :error ->
          :invalid
      end
    end
  end

  defp cash_tender_valid?({kind, _tendered, _change}) when kind in [:exact, :change], do: true
  defp cash_tender_valid?(_state), do: false

  defp cash_quick_tenders(total) do
    ["100", "200", "500", "1000"]
    |> Enum.map(&Decimal.new/1)
    |> Enum.filter(&(Decimal.compare(&1, total) in [:eq, :gt]))
  end

  defp money_input(value), do: value |> Decimal.round(2) |> Decimal.to_string(:normal)
  defp format_money(value), do: Espreso.Menu.format_price(value)
  defp new_cash_tender_token, do: Integer.to_string(System.unique_integer([:positive]))

  defp source_badge(%{source: "pos"}), do: %{label: "WALK-IN", class: "staff-order-source--pos"}
  defp source_badge(_), do: %{label: "QR", class: "staff-order-source--customer"}

  defp order_note(%{notes: notes}) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: nil, else: trimmed
  end

  defp order_note(_), do: nil

  defp freshly_received?(
         %{status: "received", inserted_at: %DateTime{} = inserted_at},
         %DateTime{} = now
       ) do
    now
    |> DateTime.diff(DateTime.truncate(inserted_at, :second), :second)
    |> then(&(&1 >= 0 and &1 < 90))
  end

  defp freshly_received?(_, _), do: false

  defp payment_state_label(%{payment_status: "paid"}), do: "PAID"
  defp payment_state_label(%{payment_status: "awaiting_payment"}), do: "AWAITING PAYMENT"
  defp payment_state_label(_), do: "UNPAID"

  defp paid_via_badge(%{payment_status: "paid", paid_via: "cash"}), do: "CASH"
  defp paid_via_badge(%{payment_status: "paid", paid_via: "gcash"}), do: "GCASH"
  defp paid_via_badge(%{payment_status: "paid", paid_via: "maya"}), do: "MAYA"
  defp paid_via_badge(%{payment_status: "paid", paid_via: "paymongo"}), do: "PAYMONGO"
  defp paid_via_badge(%{payment_status: "paid", paid_via: "counter"}), do: "COUNTER"
  defp paid_via_badge(_), do: nil

  defp fulfillment_short(%{fulfillment: "dine_in"}), do: "Dine-in"
  defp fulfillment_short(%{fulfillment: "pickup"}), do: "Takeout"
  defp fulfillment_short(_), do: "Order"

  defp show_customer_name?(%{customer_name: name}) when is_binary(name) do
    trimmed = String.trim(name)
    trimmed != "" and String.downcase(trimmed) not in ["walk-in", "walk in"]
  end

  defp show_customer_name?(_), do: false

  defp format_order_age(%DateTime{} = inserted_at, %DateTime{} = now) do
    seconds =
      now
      |> DateTime.diff(DateTime.truncate(inserted_at, :second), :second)
      |> max(0)

    cond do
      seconds < 60 ->
        "Just now"

      seconds < 3600 ->
        minutes = div(seconds, 60)
        if minutes == 1, do: "1 min ago", else: "#{minutes} min ago"

      true ->
        hours = div(seconds, 3600)
        if hours == 1, do: "1 hr ago", else: "#{hours} hr ago"
    end
  end

  defp format_order_age(_, _), do: ""

  defp order_age_class(%DateTime{} = inserted_at, %DateTime{} = now) do
    minutes =
      now
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

  defp order_age_class(_, _), do: ["staff-order-age"]

  defp schedule_age_tick do
    Process.send_after(self(), :age_tick, @age_tick_ms)
  end

  defp load_orders(socket) do
    active_orders = Orders.list_active_orders()
    ready_orders = Orders.list_recent_ready(@ready_lane_limit)
    unpaid_orders = Orders.list_todays_unpaid()

    operational_orders =
      (active_orders ++ ready_orders)
      |> Enum.uniq_by(& &1.id)

    reprint_order_ids =
      operational_orders
      |> Enum.filter(&(&1.payment_status == "paid"))
      |> Enum.map(& &1.id)

    kitchen_order_ids = Enum.map(operational_orders, & &1.id)

    drawer_order_ids =
      operational_orders
      |> Enum.filter(
        &(&1.payment_status == "paid" and Printer.cash_like?(&1.paid_via || "counter"))
      )
      |> Enum.map(& &1.id)

    mark_paid_order_ids =
      unpaid_orders
      |> Enum.filter(&staff_mark_paid?/1)
      |> Enum.map(& &1.id)

    {reprint_permits, kitchen_permits, drawer_permits} =
      if Printer.enabled?() do
        {
          PhysicalActionCoordinator.reprint_permits(reprint_order_ids),
          PhysicalActionCoordinator.permits(:kitchen, kitchen_order_ids),
          PhysicalActionCoordinator.permits(:drawer, drawer_order_ids)
        }
      else
        {%{}, %{}, %{}}
      end

    mark_paid_permits =
      PhysicalActionCoordinator.permits(:mark_paid, mark_paid_order_ids)

    socket
    |> assign(:active_orders, active_orders)
    |> assign(:ready_orders, ready_orders)
    |> assign(:reprint_permits, reprint_permits)
    |> assign(:kitchen_permits, kitchen_permits)
    |> assign(:drawer_permits, drawer_permits)
    |> assign(:mark_paid_permits, mark_paid_permits)
    |> assign(:unpaid_orders, unpaid_orders)
    |> assign(:paymongo_reconciliations, Orders.list_open_paymongo_reconciliations())
  end

  defp update_mark_paid_recovery(socket, order_id, paid_via, physical_result) do
    case physical_result do
      {:definite_failure, phase, _reason, permit} ->
        update(
          socket,
          :mark_paid_recoveries,
          &Map.put(&1, order_id, %{phase: phase, permit: permit, paid_via: paid_via})
        )

      _ ->
        update(socket, :mark_paid_recoveries, &Map.delete(&1, order_id))
    end
  end

  defp handle_mark_paid_recovery_result(socket, id, paid_via, phase, result) do
    order_id =
      case Integer.parse(id) do
        {parsed, ""} -> parsed
        _ -> nil
      end

    case result do
      {:ok, :recovery, paid, physical_result} ->
        socket
        |> update_mark_paid_recovery(paid.id, paid.paid_via || paid_via, physical_result)
        |> assign(:flash_note, mark_paid_recovery_note(phase, physical_result))

      _ ->
        socket
        |> then(fn current ->
          if order_id do
            update(current, :mark_paid_recoveries, &Map.delete(&1, order_id))
          else
            current
          end
        end)
        |> assign(:flash_note, "Could not mark order paid.")
    end
  end

  defp mark_paid_recovery_note("receipt", {:dispatched, _phase}),
    do: reprint_note({:dispatched, nil})

  defp mark_paid_recovery_note("drawer", {:dispatched, _phase}),
    do: physical_action_note(:drawer, {:dispatched, nil})

  defp mark_paid_recovery_note(_phase, {:definite_failure, :receipt, reason, _permit}),
    do: reprint_note({:definite_failure, reason, nil})

  defp mark_paid_recovery_note(_phase, {:definite_failure, :drawer, reason, _permit}),
    do: physical_action_note(:drawer, {:definite_failure, reason, nil})

  defp mark_paid_recovery_note(_phase, {:uncertain, :receipt, reason}),
    do: reprint_note({:uncertain, reason})

  defp mark_paid_recovery_note(_phase, {:uncertain, :drawer, reason}),
    do: physical_action_note(:drawer, {:uncertain, reason})

  defp reprint_note({:dispatched, _next_permit}),
    do: "Receipt command dispatched."

  defp reprint_note({:definite_failure, reason, _retry_permit}),
    do: "Reprint could not connect to the printer (#{inspect(reason)}). Try again."

  defp reprint_note({:uncertain, reason}),
    do:
      "Receipt outcome uncertain (#{inspect(reason)}). It may already have printed; do not retry automatically."

  defp reprint_note({:duplicate, _result}),
    do: "This Reprint request was already handled. No additional receipt was sent."

  defp reprint_note({:stale, _reason}),
    do: "Reprint request is stale. No receipt was sent."

  defp reprint_note({:recovery_required, _reason}),
    do:
      "Reprint recovery acknowledgement is required after a printer coordinator restart. No receipt was sent."

  defp reprint_note({:ineligible, :order_not_found}),
    do: "Order no longer exists. No receipt was sent."

  defp reprint_note({:ineligible, :order_not_paid}),
    do: "Only paid orders can be reprinted. No receipt was sent."

  defp reprint_note({:ineligible, :order_not_eligible}),
    do: "This order is no longer eligible for Reprint. No receipt was sent."

  defp reprint_note({:ineligible, :printer_disabled}),
    do: "Printer is not enabled on this server. No receipt was sent."

  defp physical_action_note(:kitchen, {:dispatched, _next_permit}),
    do: "Kitchen ticket command dispatched."

  defp physical_action_note(:drawer, {:dispatched, _next_permit}),
    do: "Kaha command dispatched."

  defp physical_action_note(:kitchen, {:definite_failure, reason, _retry_permit}),
    do: "Kitchen could not connect to the printer (#{inspect(reason)}). Try again."

  defp physical_action_note(:drawer, {:definite_failure, reason, _retry_permit}),
    do: "Kaha could not connect to the printer (#{inspect(reason)}). Try again."

  defp physical_action_note(:kitchen, {:uncertain, reason}),
    do:
      "Kitchen ticket outcome uncertain (#{inspect(reason)}). It may already have printed; do not retry automatically."

  defp physical_action_note(:drawer, {:uncertain, reason}),
    do:
      "Kaha outcome uncertain (#{inspect(reason)}). The drawer may already have opened; do not retry automatically."

  defp physical_action_note(:kitchen, {:duplicate, _result}),
    do: "This Kitchen request was already handled. No additional ticket was sent."

  defp physical_action_note(:drawer, {:duplicate, _result}),
    do: "This Kaha request was already handled. Drawer was not opened again."

  defp physical_action_note(:kitchen, {:stale, _reason}),
    do: "Kitchen request is stale. No ticket was sent."

  defp physical_action_note(:drawer, {:stale, _reason}),
    do: "Kaha request is stale. Drawer was not opened."

  defp physical_action_note(action, {:recovery_required, _reason})
       when action in [:kitchen, :drawer],
       do: "Printer recovery acknowledgement is required. No physical command was sent."

  defp physical_action_note(:kitchen, {:ineligible, :order_not_found}),
    do: "Order no longer exists. No kitchen ticket was sent."

  defp physical_action_note(:drawer, {:ineligible, :order_not_found}),
    do: "Order no longer exists. Drawer was not opened."

  defp physical_action_note(:drawer, {:ineligible, :order_not_paid}),
    do: "Only paid orders can open Kaha. Drawer was not opened."

  defp physical_action_note(:drawer, {:ineligible, :payment_not_cash_like}),
    do: "Kaha is only available for cash-like payments. Drawer was not opened."

  defp physical_action_note(:kitchen, {:ineligible, :order_not_eligible}),
    do: "This order is no longer eligible for Kitchen. No ticket was sent."

  defp physical_action_note(:drawer, {:ineligible, :order_not_eligible}),
    do: "This order is no longer eligible for Kaha. Drawer was not opened."

  defp physical_action_note(:kitchen, {:ineligible, :printer_disabled}),
    do: "Printer is not enabled on this server. No kitchen ticket was sent."

  defp physical_action_note(:drawer, {:ineligible, :printer_disabled}),
    do: "Printer is not enabled on this server. Drawer was not opened."

  defp maybe_set_alert_banner(socket, %{status: "received"} = order) do
    prev_received_ids =
      socket.assigns
      |> Map.get(:active_orders, [])
      |> Enum.filter(&(&1.status == "received"))
      |> MapSet.new(& &1.id)

    if MapSet.member?(prev_received_ids, order.id) do
      socket
    else
      assign(socket, :alert_banner, %{
        id: order.id,
        number: order.number,
        name: order.customer_name || "Customer"
      })
    end
  end

  defp maybe_set_alert_banner(socket, _order), do: socket

  defp truncate_session_id(session_id) when is_binary(session_id) do
    if String.length(session_id) > 16 do
      String.slice(session_id, 0, 12) <> "…"
    else
      session_id
    end
  end

  defp truncate_session_id(_), do: ""
end

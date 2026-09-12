defmodule EspresoWeb.StaffTransactionsLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.PhysicalActionCoordinator
  alias Espreso.Printer

  @reprintable_statuses ~w(received preparing ready completed)
  # Coalesce rapid {:order_changed, _} transaction list/summary reloads.
  @pubsub_reload_debounce_ms 300

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: Orders.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Transactions")
     |> assign(:show_totals?, Authorization.can?(socket.assigns.current_user, :reports))
     |> assign(:reprintable_statuses, @reprintable_statuses)
     |> assign(:selected_transaction, nil)
     |> assign(:reprint_transaction, nil)
     |> assign(:reprint_permit, nil)
     |> assign(:action_note, nil)
     |> assign(:pubsub_reload_timer, nil)
     |> assign(:pubsub_reload_token, nil)
     |> assign(:transactions_has_next?, false)
     |> assign(:transactions_next_cursor, nil)
     |> load_transactions(params), layout: false}
  end

  @impl true
  def handle_info({:order_changed, _order}, socket) do
    {:noreply, schedule_pubsub_reload(socket)}
  end

  def handle_info({:coalesced_transactions_reload, token}, socket) do
    if socket.assigns.pubsub_reload_token == token do
      {:noreply,
       socket
       |> assign(:pubsub_reload_timer, nil)
       |> assign(:pubsub_reload_token, nil)
       |> load_transactions(socket.assigns.filters)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:selected_transaction, nil)
     |> close_reprint()
     |> load_transactions(filters)}
  end

  def handle_event("load_more_transactions", _params, socket) do
    {:noreply, append_transactions(socket)}
  end

  def handle_event("select_transaction", %{"id" => id}, socket) do
    selected =
      with {id, ""} <- Integer.parse(id) do
        Enum.find(socket.assigns.transactions, &(&1.id == id))
      else
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(:selected_transaction, selected)
     |> assign(:action_note, nil)
     |> close_reprint()}
  end

  def handle_event("close_transaction", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_transaction, nil)
     |> close_reprint()}
  end

  def handle_event("open_reprint", %{"id" => id}, socket) do
    with %Order{} = order <- socket.assigns.selected_transaction,
         true <- Integer.to_string(order.id) == id,
         true <- order.status in @reprintable_statuses,
         true <- Printer.enabled?(),
         permit when is_binary(permit) <-
           PhysicalActionCoordinator.reprint_permits([order.id]) |> Map.get(order.id) do
      {:noreply,
       socket
       |> assign(:reprint_transaction, order)
       |> assign(:reprint_permit, permit)
       |> assign(:action_note, nil)}
    else
      _ ->
        {:noreply,
         assign(socket, :action_note, "Receipt reprint is unavailable. No receipt was sent.")}
    end
  end

  def handle_event("open_reprint", _params, socket) do
    {:noreply, assign(socket, :action_note, "Reprint request is stale. No receipt was sent.")}
  end

  def handle_event("cancel_reprint", _params, socket), do: {:noreply, close_reprint(socket)}

  def handle_event("confirm_reprint", _params, socket) do
    with %Order{} = order <- socket.assigns.reprint_transaction,
         permit when is_binary(permit) <- socket.assigns.reprint_permit do
      result =
        PhysicalActionCoordinator.execute_reprint(order.id, :receipt_reprint, permit,
          staff_name: socket.assigns.current_user.name
        )

      {:noreply, handle_reprint_result(socket, result)}
    else
      _ ->
        {:noreply,
         socket
         |> close_reprint()
         |> assign(:action_note, "Reprint request is stale. No receipt was sent.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:transactions} current_user={@current_user} page_title="Transactions">
      <main class="staff-transactions" id="staff-transactions">
        <header class="staff-transactions-head">
          <div>
            <p class="staff-transactions-eyebrow">Paid receipts</p>
            <h2>Transactions</h2>
            <p id="transactions-scope">
              Paid receipts for {format_shop_date(@filters.date)}
            </p>
          </div>

          <%= if @show_totals? do %>
            <section class="staff-transactions-summary" id="transactions-summary" aria-label="Totals">
              <span>Paid total</span>
              <strong>{Menu.format_price(@summary.total)}</strong>
              <small>{@summary.count} receipts</small>
            </section>
          <% else %>
            <p class="staff-transactions-count" id="transactions-count">
              {@summary.count} paid receipts
            </p>
          <% end %>
        </header>

        <form class="staff-transactions-filters" id="transactions-filters" phx-change="filter">
          <label>
            <span>Shop date</span>
            <input
              type="date"
              name="filters[date]"
              value={Date.to_iso8601(@filters.date)}
              id="transactions-date"
            />
          </label>
          <label class="staff-transactions-search">
            <span>Search</span>
            <input
              type="search"
              name="filters[search]"
              value={@filters.search}
              placeholder="Order number or customer"
              phx-debounce="250"
              id="transactions-search"
            />
          </label>
          <label>
            <span>Payment</span>
            <select name="filters[payment]" id="transactions-payment">
              <option value="all" selected={@filters.payment == "all"}>All payments</option>
              <option
                :for={via <- ~w(cash gcash maya counter paymongo)}
                value={via}
                selected={@filters.payment == via}
              >
                {Orders.paid_via_label(via)}
              </option>
            </select>
          </label>
          <label>
            <span>Order status</span>
            <select name="filters[status]" id="transactions-status">
              <option value="all" selected={@filters.status == "all"}>All statuses</option>
              <option
                :for={status <- ~w(received preparing ready completed)}
                value={status}
                selected={@filters.status == status}
              >
                {Orders.status_label(status)}
              </option>
            </select>
          </label>
          <label>
            <span>Settled via</span>
            <select name="filters[source]" id="transactions-source">
              <option value="all" selected={@filters.source == "all"}>All sources</option>
              <option
                :for={source <- ~w(pos staff_orders api paymongo manual legacy)}
                value={source}
                selected={@filters.source == source}
              >
                {source_label(source)}
              </option>
            </select>
          </label>
        </form>

        <section
          :if={@show_totals? and @summary.count > 0}
          class="staff-transactions-breakdown"
          id="transactions-breakdown"
        >
          <span :for={row <- nonzero_payment_rows(@summary)}>
            {row.label} · {Menu.format_price(row.total)} · {row.count}
          </span>
        </section>

        <p
          :if={@action_note}
          class="staff-transactions-note"
          id="transactions-action-note"
          role="status"
        >
          {@action_note}
        </p>

        <div class={["staff-transactions-workspace", @selected_transaction && "has-detail"]}>
          <section class="staff-transactions-list" id="transactions-list" aria-label="Paid receipts">
            <div class="staff-transactions-list-head" aria-hidden="true">
              <span>Total</span>
              <span>Payment</span>
              <span>Time / receipt</span>
              <span>Customer</span>
            </div>

            <button
              :for={order <- @transactions}
              type="button"
              class={[
                "staff-transaction-row",
                @selected_transaction && @selected_transaction.id == order.id && "is-selected"
              ]}
              id={"transaction-#{order.id}"}
              phx-click="select_transaction"
              phx-value-id={order.id}
            >
              <strong class="staff-transaction-total">{Menu.format_price(order.total)}</strong>
              <span class={[
                "staff-transaction-payment",
                "staff-transaction-payment--#{order.paid_via || "other"}"
              ]}>
                {Orders.paid_via_label(order.paid_via)}
              </span>
              <span class="staff-transaction-receipt">
                <strong>{format_shop_time(order.settled_at)}</strong>
                <small>{order.number}</small>
              </span>
              <span class="staff-transaction-customer">{order.customer_name || "Walk-in"}</span>
            </button>

            <div :if={@transactions == []} class="staff-transactions-empty" id="transactions-empty">
              <strong>No paid receipts found</strong>
              <span>Try another date or clear the filters.</span>
              <span class="staff-transactions-empty-hint">
                Unpaid orders and payment exceptions are handled in Orders.
              </span>
            </div>

            <button
              :if={@transactions_has_next?}
              type="button"
              id="transactions-load-more"
              class="staff-transactions-load-more"
              phx-click="load_more_transactions"
            >
              Load more
            </button>
          </section>

          <aside :if={@selected_transaction} class="staff-transaction-detail" id="transaction-detail">
            <header>
              <div>
                <p>Receipt</p>
                <h3>{@selected_transaction.number}</h3>
              </div>
              <button
                type="button"
                phx-click="close_transaction"
                aria-label="Close transaction details"
              >
                <.icon name="hero-x-mark" />
              </button>
            </header>

            <section class="staff-transaction-section staff-transaction-section--payment">
              <h4 class="staff-transaction-section-title">Payment</h4>
              <dl class="staff-transaction-meta staff-transaction-meta--payment">
                <div>
                  <dt>Payment</dt>
                  <dd class={[
                    "staff-transaction-payment",
                    "staff-transaction-payment--#{@selected_transaction.paid_via || "other"}"
                  ]}>
                    {Orders.paid_via_label(@selected_transaction.paid_via)}
                  </dd>
                </div>
                <div>
                  <dt>Settled</dt>
                  <dd>{format_shop_datetime(@selected_transaction.settled_at)}</dd>
                </div>
                <div>
                  <dt>Settled via</dt>
                  <dd>{source_label(@selected_transaction.settlement_source)}</dd>
                </div>
                <div>
                  <dt>Settled by</dt>
                  <dd>{settled_by_name(@selected_transaction)}</dd>
                </div>
              </dl>
            </section>

            <div class="staff-transaction-money">
              <p class="staff-transaction-money-total">
                <span>Total</span>
                <strong>{Menu.format_price(@selected_transaction.total)}</strong>
              </p>
              <p :if={@selected_transaction.cash_tendered} class="staff-transaction-money-cash">
                <span>Cash received</span>
                <strong>{Menu.format_price(@selected_transaction.cash_tendered)}</strong>
              </p>
              <p :if={@selected_transaction.change_due} class="staff-transaction-money-change">
                <span>Change</span>
                <strong>{Menu.format_price(@selected_transaction.change_due)}</strong>
              </p>
            </div>

            <section class="staff-transaction-section staff-transaction-section--order">
              <h4 class="staff-transaction-section-title">Order</h4>
              <dl class="staff-transaction-meta staff-transaction-meta--order">
                <div>
                  <dt>Customer</dt>
                  <dd>{@selected_transaction.customer_name || "Walk-in"}</dd>
                </div>
                <div>
                  <dt>Order status</dt>
                  <dd>{Orders.status_label(@selected_transaction.status)}</dd>
                </div>
                <div :if={fulfillment_label(@selected_transaction)}>
                  <dt>Fulfillment</dt>
                  <dd>
                    {fulfillment_label(@selected_transaction)}
                    <span :if={table_label(@selected_transaction)}>
                      · {table_label(@selected_transaction)}
                    </span>
                  </dd>
                </div>
              </dl>
            </section>

            <ul class="staff-transaction-items">
              <li :for={item <- @selected_transaction.items}>
                <span>{item.quantity}× {item.name}{if item.size, do: " · #{item.size}"}</span>
                <strong>{Menu.format_price(item.line_total)}</strong>
              </li>
            </ul>

            <div class="staff-transaction-actions">
              <button
                :if={@selected_transaction.status in @reprintable_statuses}
                type="button"
                class="staff-transaction-reprint"
                id="transaction-open-reprint"
                phx-click="open_reprint"
                phx-value-id={@selected_transaction.id}
                disabled={!@printer_enabled?}
              >
                {if @printer_enabled?, do: "Reprint receipt", else: "Printer disabled"}
              </button>
              <.link
                navigate={~p"/orders"}
                class="staff-transaction-orders-link"
                id="transaction-view-orders"
              >
                View on Orders
              </.link>
            </div>
          </aside>
        </div>

        <div
          :if={@reprint_transaction}
          class="staff-transaction-modal-layer"
          id="transaction-reprint-modal"
        >
          <button
            class="staff-transaction-modal-scrim"
            phx-click="cancel_reprint"
            aria-label="Cancel reprint"
          >
          </button>
          <section
            class="staff-transaction-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="transaction-reprint-title"
          >
            <p class="staff-transactions-eyebrow">Physical action</p>
            <h3 id="transaction-reprint-title">Reprint {@reprint_transaction.number}?</h3>
            <p>One receipt will be sent to the printer. The cash drawer will not open.</p>
            <div>
              <button type="button" id="transaction-cancel-reprint" phx-click="cancel_reprint">
                Cancel
              </button>
              <button type="button" id="transaction-confirm-reprint" phx-click="confirm_reprint">
                Print receipt
              </button>
            </div>
          </section>
        </div>
      </main>
    </.staff_shell>
    """
  end

  defp load_transactions(socket, filters) do
    socket = cancel_pubsub_reload(socket)

    %{
      orders: orders,
      filters: normalized,
      has_next_page: has_next_page?,
      next_cursor: next_cursor
    } = Orders.list_transactions(filters)

    summary = Orders.transaction_summary(normalized)
    selected_id = socket.assigns[:selected_transaction] && socket.assigns.selected_transaction.id
    selected = if selected_id, do: Enum.find(orders, &(&1.id == selected_id))

    socket
    |> assign(:transactions, orders)
    |> assign(:transactions_has_next?, has_next_page?)
    |> assign(:transactions_next_cursor, next_cursor)
    |> assign(:filters, normalized)
    |> assign(:summary, summary)
    |> assign(:selected_transaction, selected)
    |> assign(:printer_enabled?, Printer.enabled?())
  end

  defp append_transactions(socket) do
    cursor = socket.assigns.transactions_next_cursor

    if socket.assigns.transactions_has_next? and not is_nil(cursor) do
      %{
        orders: more,
        has_next_page: has_next_page?,
        next_cursor: next_cursor
      } = Orders.list_transactions(socket.assigns.filters, cursor: cursor)

      existing_ids = MapSet.new(Enum.map(socket.assigns.transactions, & &1.id))
      more = Enum.reject(more, &MapSet.member?(existing_ids, &1.id))

      socket
      |> assign(:transactions, socket.assigns.transactions ++ more)
      |> assign(:transactions_has_next?, has_next_page?)
      |> assign(:transactions_next_cursor, next_cursor)
    else
      socket
    end
  end

  defp schedule_pubsub_reload(socket) do
    socket = cancel_pubsub_reload(socket)
    ms = pubsub_reload_debounce_ms()

    if ms <= 0 do
      load_transactions(socket, socket.assigns.filters)
    else
      token = make_ref()
      timer = Process.send_after(self(), {:coalesced_transactions_reload, token}, ms)

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

  defp handle_reprint_result(socket, {:dispatched, _next_permit}) do
    socket
    |> close_reprint()
    |> assign(:action_note, "Receipt sent to printer.")
  end

  defp handle_reprint_result(socket, {:definite_failure, reason, retry_permit}) do
    socket
    |> assign(:reprint_permit, retry_permit)
    |> assign(:action_note, "Print failed (#{inspect(reason)}). You may try again.")
  end

  defp handle_reprint_result(socket, {:uncertain, reason}) do
    socket
    |> close_reprint()
    |> assign(
      :action_note,
      "Printer result is uncertain (#{inspect(reason)}). Check before retrying."
    )
  end

  defp handle_reprint_result(socket, {:ineligible, :printer_disabled}) do
    socket
    |> close_reprint()
    |> assign(:printer_enabled?, false)
    |> assign(:action_note, "Printer is disabled. No receipt was sent.")
  end

  defp handle_reprint_result(socket, _result) do
    socket
    |> close_reprint()
    |> assign(:action_note, "Reprint request could not be completed. No receipt was sent.")
  end

  defp close_reprint(socket) do
    socket
    |> assign(:reprint_transaction, nil)
    |> assign(:reprint_permit, nil)
  end

  defp nonzero_payment_rows(summary) do
    summary
    |> Orders.paid_via_rows()
    |> Enum.filter(&(&1.count > 0))
  end

  defp settled_by_name(%Order{settled_by_user: %{name: name}}), do: name
  defp settled_by_name(%Order{settlement_time_estimated: true}), do: "Legacy record"
  defp settled_by_name(_), do: "Not recorded"

  defp source_label("pos"), do: "POS"
  defp source_label("staff_orders"), do: "Orders board"
  defp source_label("api"), do: "Staff API"
  defp source_label("paymongo"), do: "PayMongo"
  defp source_label("legacy"), do: "Legacy"
  defp source_label("manual"), do: "Manual"
  defp source_label(_), do: "Not recorded"

  defp fulfillment_label(%Order{fulfillment: "dine_in"}), do: "Dine-in"
  defp fulfillment_label(%Order{fulfillment: "pickup"}), do: "Takeout"
  defp fulfillment_label(_), do: nil

  defp table_label(%Order{table_number: n}) when is_binary(n) do
    case String.trim(n) do
      "" -> nil
      trimmed -> "Table ##{trimmed}"
    end
  end

  defp table_label(_), do: nil

  defp format_shop_date(%Date{} = date), do: Calendar.strftime(date, "%B %-d, %Y")

  defp format_shop_time(%DateTime{} = at),
    do: at |> manila_time() |> Calendar.strftime("%-I:%M %p")

  defp format_shop_time(_), do: "—"

  defp format_shop_datetime(%DateTime{} = at),
    do: at |> manila_time() |> Calendar.strftime("%b %-d, %Y · %-I:%M %p")

  defp format_shop_datetime(_), do: "Not recorded"
  defp manila_time(at), do: DateTime.add(at, 8 * 60 * 60, :second)
end

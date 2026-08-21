defmodule EspresoWeb.StaffOrdersLive do
  use EspresoWeb, :live_view

  alias Espreso.Orders
  alias Espreso.Menu

  @impl true
  def mount(_params, _session, socket) do
    authed? = false

    socket =
      socket
      |> assign(:page_title, "Orders")
      |> assign(:authed?, authed?)
      |> assign(:password, "")
      |> assign(:auth_error, nil)
      |> assign(:active_orders, [])
      |> assign(:ready_orders, [])

    socket = if authed?, do: load_orders(socket), else: socket

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("auth", %{"password" => password}, socket) do
    if password_ok?(password) do
      {:noreply,
       socket
       |> assign(:authed?, true)
       |> assign(:auth_error, nil)
       |> assign(:password, "")
       |> load_orders()}
    else
      {:noreply, assign(socket, :auth_error, "Wrong password")}
    end
  end

  def handle_event("refresh", _params, socket) do
    if socket.assigns.authed? do
      {:noreply, load_orders(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_status", %{"id" => id, "status" => status}, socket) do
    if socket.assigns.authed? do
      order = Espreso.Repo.get!(Espreso.Orders.Order, id)

      case Orders.update_status(order, status) do
        {:ok, _} -> {:noreply, load_orders(socket)}
        {:error, _} -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_paid", %{"id" => id}, socket) do
    if socket.assigns.authed? do
      order = Espreso.Repo.get!(Espreso.Orders.Order, id)

      case Orders.mark_paid(order) do
        {:ok, _} -> {:noreply, load_orders(socket)}
        {:error, _} -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-orders-page">
      <header class="staff-orders-top">
        <p class="staff-orders-brand">CoffeeSpot</p>
        <h1 class="staff-orders-title">Orders</h1>
        <button :if={@authed?} type="button" class="staff-refresh" phx-click="refresh">Refresh</button>
      </header>

      <main class="staff-orders-main">
        <section :if={!@authed?} class="staff-auth-card">
          <p class="staff-auth-lede">Staff only — enter the orders password.</p>
          <form phx-submit="auth" class="staff-auth-form">
            <label class="menu-checkout-label" for="staff-password">Password</label>
            <input
              id="staff-password"
              type="password"
              name="password"
              value={@password}
              class="menu-checkout-input"
              autocomplete="current-password"
            />
            <p :if={@auth_error} class="menu-checkout-error">{@auth_error}</p>
            <button type="submit" class="menu-basket-checkout">Open orders</button>
          </form>
        </section>

        <div :if={@authed?} class="staff-orders-board">
          <section class="staff-orders-section">
            <h2>Active</h2>
            <p :if={@active_orders == []} class="staff-empty">No active orders.</p>
            <article :for={order <- @active_orders} class="staff-order-card">
              <header class="staff-order-head">
                <div>
                  <p class="staff-order-number">{order.number}</p>
                  <p class="staff-order-name">{order.customer_name}</p>
                </div>
                <div class="staff-order-badges">
                  <span class={"staff-badge staff-badge--#{order.status}"}>
                    {Orders.status_label(order.status)}
                  </span>
                  <span class={"staff-badge staff-badge--pay-#{order.payment_status}"}>
                    {Orders.payment_label(order)}
                  </span>
                </div>
              </header>

              <p class="staff-order-meta">
                {Orders.fulfillment_label(order.fulfillment)}
                <span :if={order.table_number}> · Table {order.table_number}</span>
              </p>
              <p :if={order.notes} class="staff-order-notes">Notes: {order.notes}</p>

              <ul class="staff-order-items">
                <li :for={item <- order.items}>
                  {item.quantity}× {item.name}
                  <span :if={item.size}>({item.size})</span>
                  — {Menu.format_price(item.line_total)}
                </li>
              </ul>

              <p class="staff-order-total">Total {Orders.format_total(order)}</p>

              <div class="staff-order-actions">
                <button
                  :if={order.payment_status == "unpaid"}
                  type="button"
                  class="staff-action"
                  phx-click="mark_paid"
                  phx-value-id={order.id}
                >
                  Mark paid
                </button>
                <button
                  :if={order.status == "received"}
                  type="button"
                  class="staff-action staff-action-primary"
                  phx-click="set_status"
                  phx-value-id={order.id}
                  phx-value-status="preparing"
                >
                  Preparing
                </button>
                <button
                  :if={order.status in ["received", "preparing"]}
                  type="button"
                  class="staff-action staff-action-primary"
                  phx-click="set_status"
                  phx-value-id={order.id}
                  phx-value-status="ready"
                >
                  Ready
                </button>
              </div>
            </article>
          </section>

          <section class="staff-orders-section">
            <h2>Recently ready</h2>
            <p :if={@ready_orders == []} class="staff-empty">None yet.</p>
            <article :for={order <- @ready_orders} class="staff-order-card staff-order-card-muted">
              <p class="staff-order-number">{order.number} · {order.customer_name}</p>
              <p class="staff-order-meta">
                {Orders.fulfillment_label(order.fulfillment)}
                <span :if={order.table_number}> · Table {order.table_number}</span>
                · {Orders.payment_label(order)}
              </p>
            </article>
          </section>
        </div>
      </main>
    </div>
    """
  end

  defp load_orders(socket) do
    socket
    |> assign(:active_orders, Orders.list_active_orders())
    |> assign(:ready_orders, Orders.list_recent_ready())
  end

  defp password_ok?(password) do
    expected =
      Application.get_env(:espreso, :staff_orders_password) ||
        System.get_env("STAFF_ORDERS_PASSWORD") ||
        "coffeespot"

    Plug.Crypto.secure_compare(to_string(password), to_string(expected))
  end
end

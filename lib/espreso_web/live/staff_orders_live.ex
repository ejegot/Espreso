defmodule EspresoWeb.StaffOrdersLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User
  alias Espreso.Orders
  alias Espreso.Menu

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Orders")
     |> load_orders(), layout: false}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_orders(socket)}
  end

  def handle_event("set_status", %{"id" => id, "status" => status}, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)

    case Orders.update_status(order, status) do
      {:ok, _} -> {:noreply, load_orders(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("mark_paid", %{"id" => id}, socket) do
    order = Espreso.Repo.get!(Espreso.Orders.Order, id)

    case Orders.mark_paid(order) do
      {:ok, _} -> {:noreply, load_orders(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-orders-page">
      <header class="staff-orders-top">
        <div>
          <p class="staff-orders-brand">CoffeeSpot</p>
          <h1 class="staff-orders-title">Orders</h1>
          <p class="staff-orders-user">
            {@current_user.name} · {User.role_label(@current_user.role)}
          </p>
        </div>
        <div class="staff-top-actions">
          <.link navigate={~p"/staff"} class="staff-refresh">Home</.link>
          <button type="button" class="staff-refresh" phx-click="refresh">Refresh</button>
          <.link
            :if={User.can_manage_users?(@current_user)}
            navigate={~p"/admin/users"}
            class="staff-refresh"
          >
            Staff
          </.link>
          <.link href={~p"/logout"} method="delete" class="staff-refresh">Log out</.link>
        </div>
      </header>

      <main class="staff-orders-main">
        <div class="staff-orders-board">
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
                <span :if={order.table_number}>· Table {order.table_number}</span>
              </p>
              <p :if={order.notes} class="staff-order-notes">Notes: {order.notes}</p>

              <ul class="staff-order-items">
                <li :for={item <- order.items}>
                  {item.quantity}× {item.name}
                  <span :if={item.size}>({item.size})</span> — {Menu.format_price(item.line_total)}
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
                <span :if={order.table_number}>· Table {order.table_number}</span>
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
end

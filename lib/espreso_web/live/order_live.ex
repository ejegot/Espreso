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
         |> assign(:order, nil), layout: false}

      order ->
        if connected?(socket), do: Orders.subscribe(order)

        {:ok,
         socket
         |> assign(:page_title, "Order #{order.number}")
         |> assign(:order, order), layout: false}
    end
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
          <.link navigate={~p"/menu"} class="brune-primary-btn">Back to menu</.link>
        </div>

        <div :if={@order} class="order-card">
          <p class="order-status-message" id="order-status-message">
            {customer_status_message(@order.status)}
          </p>
          <h1 class="order-number">{@order.number}</h1>
          <p class="order-payment">{Orders.payment_label(@order)}</p>

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
            <div :if={@order.notes}>
              <dt>Notes</dt>
              <dd>{@order.notes}</dd>
            </div>
          </dl>

          <ul class="order-items">
            <li :for={item <- @order.items} class="order-item">
              <div>
                <p class="order-item-name">
                  {item.quantity}× {item.name}
                  <span :if={item.size} class="order-item-size">({item.size})</span>
                </p>
              </div>
              <p class="order-item-price">{Menu.format_price(item.line_total)}</p>
            </li>
          </ul>

          <div class="order-total">
            <span>Total</span>
            <strong>{Orders.format_total(@order)}</strong>
          </div>

          <p class="order-hint">
            <%= if @order.payment_method == "counter" do %>
              Show this screen at the counter to pay and claim your order.
            <% else %>
              Keep this screen — we’ll update your status as we prepare your order.
            <% end %>
          </p>

          <div class="order-actions">
            <.link navigate={~p"/menu"} class="brune-primary-btn">Order more</.link>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp customer_status_message("received"), do: "Order received"
  defp customer_status_message("preparing"), do: "We're preparing your order"
  defp customer_status_message("ready"), do: "Your order is ready"
  defp customer_status_message("completed"), do: "Order picked up"
  defp customer_status_message("cancelled"), do: "Order cancelled"
  defp customer_status_message(_), do: "Order"
end

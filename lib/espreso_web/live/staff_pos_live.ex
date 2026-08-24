defmodule EspresoWeb.StaffPosLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User
  alias Espreso.Menu
  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    categories = Menu.list_menu()
    selected = categories |> List.first() |> then(&(&1 && &1.name))

    {:ok,
     socket
     |> assign(:page_title, "POS")
     |> assign(:categories, categories)
     |> assign(:selected_category, selected)
     |> assign(:cart, [])
     |> assign(:customer_name, "Walk-in")
     |> assign(:size_picker, nil)
     |> assign(:last_order, nil)
     |> assign(:error, nil), layout: false}
  end

  @impl true
  def handle_event("select_category", %{"name" => name}, socket) do
    {:noreply,
     socket
     |> assign(:selected_category, name)
     |> assign(:size_picker, nil)
     |> assign(:error, nil)}
  end

  def handle_event("add_product", %{"product-id" => product_id}, socket) do
    product_id = String.to_integer(product_id)

    case find_product(socket.assigns.categories, product_id) do
      %{product_prices: [price]} = product ->
        {:noreply,
         socket
         |> assign(:cart, add_line(socket.assigns.cart, product, price))
         |> assign(:size_picker, nil)
         |> assign(:error, nil)
         |> assign(:last_order, nil)}

      %{product_prices: prices} = product when length(prices) > 1 ->
        {:noreply,
         socket
         |> assign(:size_picker, product)
         |> assign(:error, nil)}

      _ ->
        {:noreply, assign(socket, :error, "Product is unavailable.")}
    end
  end

  def handle_event("select_size", %{"product-id" => product_id, "price-id" => price_id}, socket) do
    product_id = String.to_integer(product_id)
    price_id = String.to_integer(price_id)

    with %{product_prices: prices} = product <-
           find_product(socket.assigns.categories, product_id),
         %{} = price <- Enum.find(prices, &(&1.id == price_id)) do
      {:noreply,
       socket
       |> assign(:cart, add_line(socket.assigns.cart, product, price))
       |> assign(:size_picker, nil)
       |> assign(:error, nil)
       |> assign(:last_order, nil)}
    else
      _ ->
        {:noreply, assign(socket, :error, "Selected size is unavailable.")}
    end
  end

  def handle_event("cancel_size", _params, socket) do
    {:noreply, assign(socket, :size_picker, nil)}
  end

  def handle_event("inc", %{"key" => key}, socket) do
    {:noreply, assign(socket, :cart, update_qty(socket.assigns.cart, key, 1))}
  end

  def handle_event("dec", %{"key" => key}, socket) do
    {:noreply, assign(socket, :cart, update_qty(socket.assigns.cart, key, -1))}
  end

  def handle_event("remove", %{"key" => key}, socket) do
    {:noreply, assign(socket, :cart, Enum.reject(socket.assigns.cart, &(&1.key == key)))}
  end

  def handle_event("place_order", _params, socket) do
    cart = socket.assigns.cart

    if cart == [] do
      {:noreply, assign(socket, :error, "Add at least one item before placing an order.")}
    else
      lines =
        Enum.map(cart, fn line ->
          %{
            name: line.name,
            size: line.size,
            quantity: line.quantity,
            price: line.price
          }
        end)

      attrs = %{
        customer_name: socket.assigns.customer_name,
        fulfillment: :pickup,
        payment_method: :counter,
        source: :pos
      }

      case Orders.create_order(lines, attrs) do
        {:ok, order} ->
          {:noreply,
           socket
           |> assign(:cart, [])
           |> assign(:size_picker, nil)
           |> assign(:error, nil)
           |> assign(:last_order, order)
           |> assign(:categories, Menu.list_menu())}

        {:error, :empty_cart} ->
          {:noreply, assign(socket, :error, "Add at least one item before placing an order.")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :error, "Could not place order. Check items and try again.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-pos-page">
      <header class="staff-orders-top">
        <div>
          <p class="staff-orders-brand">CoffeeSpot POS</p>
          <h1 class="staff-orders-title">POS</h1>
          <p class="staff-orders-user">
            {@current_user.name} · {User.role_label(@current_user.role)}
          </p>
        </div>
        <div class="staff-top-actions">
          <.link navigate={~p"/staff"} class="staff-refresh">Home</.link>
          <.link navigate={~p"/orders"} class="staff-refresh">Orders</.link>
          <.link href={~p"/logout"} method="delete" class="staff-refresh">Log out</.link>
        </div>
      </header>

      <main class="staff-pos-main">
        <p :if={@error} class="staff-admin-note" id="pos-error">{@error}</p>

        <div :if={@last_order} class="staff-auth-card staff-pos-confirm" id="pos-confirmation">
          <p class="staff-home-card-eyebrow">Order placed</p>
          <p class="staff-order-number">{@last_order.number}</p>
          <p class="staff-order-meta">
            Status: {Orders.status_label(@last_order.status)} · {@last_order.customer_name}
          </p>
          <.link navigate={~p"/orders"} class="staff-refresh">Open order queue</.link>
        </div>

        <div class="staff-pos-layout">
          <section class="staff-pos-catalog" id="pos-catalog">
            <nav class="staff-pos-categories" aria-label="Categories">
              <button
                :for={category <- @categories}
                type="button"
                class={[
                  "staff-pos-category",
                  @selected_category == category.name && "is-active"
                ]}
                phx-click="select_category"
                phx-value-name={category.name}
                id={"pos-category-#{category.name}"}
              >
                {category.name}
              </button>
            </nav>

            <div :if={@size_picker} class="staff-pos-size-picker" id="pos-size-picker">
              <div class="staff-pos-size-picker-head">
                <p>Select size — {@size_picker.name}</p>
                <button type="button" class="staff-action" phx-click="cancel_size">Cancel</button>
              </div>
              <div class="staff-pos-size-options">
                <button
                  :for={price <- @size_picker.product_prices}
                  type="button"
                  class="staff-pos-product"
                  id={"pos-size-#{price.id}"}
                  phx-click="select_size"
                  phx-value-product-id={@size_picker.id}
                  phx-value-price-id={price.id}
                >
                  <span>{price.size || "Regular"}</span>
                  <span>{Menu.format_price(price.price)}</span>
                </button>
              </div>
            </div>

            <div class="staff-pos-products" id="pos-products">
              <button
                :for={product <- products_for(@categories, @selected_category)}
                type="button"
                class="staff-pos-product"
                id={"pos-product-#{product.id}"}
                phx-click="add_product"
                phx-value-product-id={product.id}
              >
                <span class="staff-pos-product-name">{product.name}</span>
                <span class="staff-pos-product-price">
                  {price_label(product)}
                </span>
              </button>
              <p :if={products_for(@categories, @selected_category) == []} class="staff-empty">
                No available products in this category.
              </p>
            </div>
          </section>

          <aside class="staff-pos-ticket" id="pos-ticket">
            <h2>Current Order</h2>
            <p class="staff-pos-customer">Customer: {@customer_name}</p>

            <p :if={@cart == []} class="staff-empty" id="pos-cart-empty">No items yet.</p>

            <ul class="staff-pos-cart" id="pos-cart-lines">
              <li :for={line <- @cart} class="staff-pos-cart-line" id={"pos-line-#{line.key}"}>
                <div class="staff-pos-cart-info">
                  <p class="staff-pos-cart-name">
                    {line.name}
                    <span :if={line.size} class="staff-pos-cart-size">· {line.size}</span>
                  </p>
                  <p class="staff-pos-cart-amount">
                    {Menu.format_price(Decimal.mult(line.price, line.quantity))}
                  </p>
                </div>
                <div class="staff-pos-cart-actions">
                  <button
                    type="button"
                    class="staff-action"
                    phx-click="dec"
                    phx-value-key={line.key}
                    aria-label={"Decrease #{line.name}"}
                  >
                    −
                  </button>
                  <span class="staff-pos-qty">{line.quantity}</span>
                  <button
                    type="button"
                    class="staff-action"
                    phx-click="inc"
                    phx-value-key={line.key}
                    aria-label={"Increase #{line.name}"}
                  >
                    +
                  </button>
                  <button
                    type="button"
                    class="staff-action"
                    phx-click="remove"
                    phx-value-key={line.key}
                    aria-label={"Remove #{line.name}"}
                  >
                    Remove
                  </button>
                </div>
              </li>
            </ul>

            <div class="staff-pos-totals">
              <div class="staff-pos-total-row">
                <span>Subtotal</span>
                <span id="pos-subtotal">{Menu.format_price(cart_total(@cart))}</span>
              </div>
              <div class="staff-pos-total-row staff-pos-total-row--grand">
                <span>Total</span>
                <span id="pos-total">{Menu.format_price(cart_total(@cart))}</span>
              </div>
            </div>

            <button
              type="button"
              class="menu-basket-checkout staff-pos-place"
              id="pos-place-order"
              phx-click="place_order"
            >
              Place Order
            </button>
          </aside>
        </div>
      </main>
    </div>
    """
  end

  defp products_for(categories, selected) do
    case Enum.find(categories, &(&1.name == selected)) do
      %{products: products} -> products
      _ -> []
    end
  end

  defp find_product(categories, product_id) do
    categories
    |> Enum.flat_map(& &1.products)
    |> Enum.find(&(&1.id == product_id))
  end

  defp price_label(%{product_prices: [price]}), do: Menu.format_price(price.price)

  defp price_label(%{product_prices: prices}) do
    prices
    |> Enum.map(& &1.price)
    |> Enum.min(Decimal)
    |> Menu.format_price()
    |> then(&"from #{&1}")
  end

  defp add_line(cart, product, price) do
    key = "#{product.id}-#{price.id}"

    case Enum.find_index(cart, &(&1.key == key)) do
      nil ->
        cart ++
          [
            %{
              key: key,
              product_id: product.id,
              price_id: price.id,
              name: product.name,
              size: price.size,
              price: price.price,
              quantity: 1
            }
          ]

      index ->
        List.update_at(cart, index, fn line ->
          %{line | quantity: line.quantity + 1}
        end)
    end
  end

  defp update_qty(cart, key, delta) do
    cart
    |> Enum.map(fn
      %{key: ^key} = line ->
        qty = line.quantity + delta
        if qty < 1, do: nil, else: %{line | quantity: qty}

      line ->
        line
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp cart_total(cart) do
    Enum.reduce(cart, Decimal.new(0), fn line, acc ->
      Decimal.add(acc, Decimal.mult(line.price, line.quantity))
    end)
  end
end

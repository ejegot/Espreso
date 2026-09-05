defmodule EspresoWeb.StaffPosLive do
  use EspresoWeb, :live_view

  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Printer
  alias EspresoWeb.StaffNotifications

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Orders.subscribe()

    categories = Menu.list_menu()
    selected = categories |> List.first() |> then(&(&1 && &1.name))

    {:ok,
     socket
     |> assign(:page_title, "POS")
     |> assign(:categories, categories)
     |> assign(:selected_category, selected)
     |> assign(:search, "")
     |> assign(:cart, [])
     |> assign(:customer_name, "Walk-in")
     |> assign(:notes, "")
     |> assign(:fulfillment, :pickup)
     |> assign(:table_number, "")
     |> assign(:payment_choice, :unpaid)
     |> assign(:paid_via, "cash")
     |> assign(:placing_order?, false)
     |> assign(:size_picker, nil)
     |> assign(:last_order, nil)
     |> assign(:print_note, nil)
     |> assign(:error, nil), layout: false}
  end

  @impl true
  def handle_info({:order_changed, order}, socket) do
    StaffNotifications.push_order_change(order)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_category", %{"name" => name}, socket) do
    {:noreply,
     socket
     |> assign(:selected_category, name)
     |> assign(:size_picker, nil)
     |> assign(:error, nil)}
  end

  def handle_event("search", params, socket) do
    {:noreply, assign(socket, :search, Map.get(params, "q", ""))}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, :search, "")}
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
         |> assign(:last_order, nil)
         |> assign(:print_note, nil)}

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
       |> assign(:last_order, nil)
       |> assign(:print_note, nil)}
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

  def handle_event("new_order", _params, socket) do
    {:noreply,
     socket
     |> assign(:cart, [])
     |> assign(:size_picker, nil)
     |> assign(:last_order, nil)
     |> assign(:print_note, nil)
     |> assign(:error, nil)
     |> assign(:payment_choice, :unpaid)
     |> assign(:paid_via, "cash")
     |> assign(:fulfillment, :pickup)
     |> assign(:table_number, "")
     |> assign(:placing_order?, false)
     |> assign(:customer_name, "Walk-in")
     |> assign(:notes, "")}
  end

  def handle_event("set_customer_name", %{"customer_name" => name}, socket) do
    {:noreply, assign(socket, :customer_name, String.trim(name))}
  end

  def handle_event("set_notes", %{"notes" => notes}, socket) do
    {:noreply, assign(socket, :notes, notes)}
  end

  def handle_event("set_fulfillment", %{"fulfillment" => fulfillment}, socket) do
    fulfillment =
      case fulfillment do
        "dine_in" -> :dine_in
        _ -> :pickup
      end

    socket =
      socket
      |> assign(:fulfillment, fulfillment)
      |> then(fn s ->
        if fulfillment == :pickup, do: assign(s, :table_number, ""), else: s
      end)

    {:noreply, socket}
  end

  def handle_event("set_table_number", %{"table_number" => table}, socket) do
    {:noreply, assign(socket, :table_number, String.trim(table))}
  end

  def handle_event("set_payment_choice", %{"choice" => choice}, socket) do
    choice =
      case choice do
        "paid" -> :paid
        _ -> :unpaid
      end

    {:noreply, assign(socket, :payment_choice, choice)}
  end

  def handle_event("set_paid_via", %{"paid_via" => paid_via}, socket)
      when paid_via in ["cash", "gcash", "maya"] do
    {:noreply, assign(socket, :paid_via, paid_via)}
  end

  def handle_event("set_paid_via", _params, socket), do: {:noreply, socket}

  def handle_event("reprint_receipt", _params, socket) do
    case socket.assigns.last_order do
      nil ->
        {:noreply, socket}

      order ->
        order = Espreso.Repo.preload(order, :items)

        note =
          case Printer.print_receipt(order, staff_name: socket.assigns.current_user.name) do
            :ok -> "Receipt reprinted."
            :disabled -> "Printer is not enabled on this server."
            {:error, reason} -> "Reprint failed (#{inspect(reason)})."
          end

        {:noreply, assign(socket, :print_note, note)}
    end
  end

  def handle_event("open_drawer", _params, socket) do
    note =
      case Printer.open_drawer() do
        :ok -> "Kaha opened."
        :disabled -> "Printer is not enabled on this server."
        {:error, reason} -> "Could not open kaha (#{inspect(reason)})."
      end

    {:noreply, assign(socket, :print_note, note)}
  end

  def handle_event("place_order", _params, socket) do
    cond do
      socket.assigns.placing_order? ->
        {:noreply, socket}

      socket.assigns.cart == [] ->
        {:noreply, assign(socket, :error, "Add at least one item before placing an order.")}

      String.trim(socket.assigns.customer_name) == "" ||
          String.length(String.trim(socket.assigns.customer_name)) < 2 ->
        {:noreply,
         assign(socket, :error, "Enter a customer name (at least 2 characters).")}

      socket.assigns.fulfillment == :dine_in and not valid_table?(socket.assigns.table_number) ->
        {:noreply, assign(socket, :error, "Enter a table number from 1 to 99.")}

      true ->
        customer_name = String.trim(socket.assigns.customer_name)
        paid? = socket.assigns.payment_choice == :paid
        paid_via = if paid?, do: socket.assigns.paid_via, else: nil

        lines =
          Enum.map(socket.assigns.cart, fn line ->
            %{
              product_id: line.product_id,
              name: line.name,
              size: line.size,
              quantity: line.quantity,
              price: line.price
            }
          end)

        attrs = %{
          customer_name: customer_name,
          notes: blank_notes(socket.assigns.notes),
          fulfillment: socket.assigns.fulfillment,
          table_number:
            if(socket.assigns.fulfillment == :dine_in,
              do: socket.assigns.table_number,
              else: nil
            ),
          payment_method: :counter,
          payment_status: socket.assigns.payment_choice,
          paid_via: paid_via,
          source: :pos
        }

        socket = assign(socket, :placing_order?, true)

        case Orders.create_order(lines, attrs) do
          {:ok, order} ->
            print_result =
              if paid? do
                Printer.after_paid(order, order.paid_via || paid_via || "cash",
                  staff_name: socket.assigns.current_user.name
                )
              else
                :disabled
              end

            {:noreply,
             socket
             |> assign(:cart, [])
             |> assign(:size_picker, nil)
             |> assign(:error, nil)
             |> assign(:last_order, order)
             |> assign(:print_note, print_note(print_result, order.paid_via || paid_via))
             |> assign(:payment_choice, :unpaid)
             |> assign(:paid_via, "cash")
             |> assign(:fulfillment, :pickup)
             |> assign(:table_number, "")
             |> assign(:placing_order?, false)
             |> assign(:notes, "")
             |> assign(:categories, Menu.list_menu())}

          {:error, :empty_cart} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:error, "Add at least one item before placing an order.")}

          {:error, {:unavailable, names}} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:error, unavailable_error(names))}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:error, "Could not place order. Check items and try again.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:pos} current_user={@current_user} page_title="POS">
      <div class="staff-pos-page staff-pos-shell-root">
        <main class="staff-pos-main">
          <p :if={@error} class="staff-pos-flash" id="pos-error">{@error}</p>

          <div class="staff-pos-layout">
            <section class="staff-pos-catalog" id="pos-catalog">
              <div class="staff-pos-catalog-layout">
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

                <div class="staff-pos-catalog-main">
                  <header class="staff-pos-catalog-head">
                    <div>
                      <p class="staff-pos-catalog-eyebrow">Choose menu</p>
                      <h2 class="staff-pos-catalog-title">{@selected_category || "Products"}</h2>
                    </div>
                    <span class="staff-pos-catalog-count">
                      {length(visible_products(@categories, @selected_category, @search))} items
                    </span>
                  </header>

                  <form class="staff-pos-search" id="pos-search" phx-change="search" phx-submit="search">
                    <label class="staff-pos-search-label" for="pos-search-input">Search</label>
                    <div class="staff-pos-search-row">
                      <input
                        type="search"
                        class="staff-pos-search-input"
                        id="pos-search-input"
                        name="q"
                        value={@search}
                        placeholder="Search menu…"
                        autocomplete="off"
                        phx-debounce="200"
                      />
                      <button
                        :if={String.trim(@search) != ""}
                        type="button"
                        class="staff-pos-search-clear"
                        id="pos-search-clear"
                        phx-click="clear_search"
                      >
                        Clear
                      </button>
                    </div>
                  </form>

                  <div class="staff-pos-products" id="pos-products">
                    <button
                      :for={{product, img} <-
                        product_cards(@categories, @selected_category, @search)}
                      type="button"
                      class="staff-pos-product"
                      id={"pos-product-#{product.id}"}
                      phx-click="add_product"
                      phx-value-product-id={product.id}
                    >
                      <span class="staff-pos-product-media" aria-hidden="true">
                        <img
                          src={img.src}
                          alt=""
                          class={["staff-pos-product-img", img.packshot? && "is-packshot"]}
                          loading="lazy"
                        />
                      </span>
                      <span class="staff-pos-product-copy">
                        <span class="staff-pos-product-name">{product.name}</span>
                        <span class="staff-pos-product-price">
                          {price_label(product)}
                        </span>
                      </span>
                    </button>
                    <p
                      :if={visible_products(@categories, @selected_category, @search) == []}
                      class="staff-empty"
                      id="pos-products-empty"
                    >
                      <%= if String.trim(@search) != "" do %>
                        No products match “{@search}”.
                      <% else %>
                        No available products in this category.
                      <% end %>
                    </p>
                  </div>
                </div>
              </div>
            </section>

            <aside class="staff-pos-ticket" id="pos-ticket">
              <%= if @last_order do %>
                <div class="staff-pos-success" id="pos-confirmation">
                  <div class="staff-pos-success-badge" aria-hidden="true">✓</div>
                  <p class="staff-pos-success-eyebrow">Order placed</p>
                  <p class="staff-order-number">{@last_order.number}</p>
                  <p class="staff-order-meta">
                    Status: {Orders.status_label(@last_order.status)} · {@last_order.customer_name}
                    · {Orders.payment_label(@last_order)}
                  </p>
                  <p :if={@print_note} class="staff-pos-success-note" id="pos-print-note">
                    {@print_note}
                  </p>
                  <p :if={order_note(@last_order)} class="staff-pos-success-note">
                    Note: {order_note(@last_order)}
                  </p>
                  <div class="staff-pos-success-actions">
                    <button
                      :if={Printer.enabled?() and @last_order.payment_status == "paid"}
                      type="button"
                      class="staff-pos-place staff-pos-place--secondary"
                      id="pos-reprint"
                      phx-click="reprint_receipt"
                    >
                      Reprint
                    </button>
                    <button
                      :if={
                        Printer.enabled?() and @last_order.payment_status == "paid" and
                          Printer.cash_like?(@last_order.paid_via || "cash")
                      }
                      type="button"
                      class="staff-pos-place staff-pos-place--secondary"
                      id="pos-open-kaha"
                      phx-click="open_drawer"
                    >
                      Open kaha
                    </button>
                    <button
                      type="button"
                      class="staff-pos-place staff-pos-place--secondary"
                      id="pos-new-order"
                      phx-click="new_order"
                    >
                      New Order
                    </button>
                    <.link navigate={~p"/orders"} class="staff-pos-view-orders">
                      View Orders
                    </.link>
                  </div>
                </div>
              <% else %>
                <div class="staff-pos-ticket-head">
                  <div class="staff-pos-ticket-title-row">
                    <h2>Current Order</h2>
                    <span :if={cart_item_count(@cart) > 0} class="staff-pos-cart-count">
                      {cart_item_count(@cart)}
                    </span>
                  </div>

                  <div class="staff-pos-panel-section">
                    <p class="staff-pos-section-label">Customer</p>
                    <label class="staff-pos-field" for="pos-customer-name">
                      <span class="staff-pos-field-label">Name</span>
                      <input
                        type="text"
                        class="staff-pos-field-input"
                        id="pos-customer-name"
                        name="customer_name"
                        value={@customer_name}
                        phx-change="set_customer_name"
                        phx-debounce="300"
                        autocomplete="off"
                        maxlength="60"
                        placeholder="Walk-in or customer name"
                      />
                    </label>

                    <p class="staff-pos-section-label">Fulfillment</p>
                    <div
                      class="menu-checkout-options staff-pos-payment"
                      id="pos-fulfillment"
                      role="radiogroup"
                      aria-label="Fulfillment"
                    >
                      <button
                        type="button"
                        class={["menu-checkout-option", @fulfillment == :pickup && "is-active"]}
                        id="pos-fulfillment-pickup"
                        phx-click="set_fulfillment"
                        phx-value-fulfillment="pickup"
                        aria-pressed={to_string(@fulfillment == :pickup)}
                      >
                        Pickup
                      </button>
                      <button
                        type="button"
                        class={["menu-checkout-option", @fulfillment == :dine_in && "is-active"]}
                        id="pos-fulfillment-dine-in"
                        phx-click="set_fulfillment"
                        phx-value-fulfillment="dine_in"
                        aria-pressed={to_string(@fulfillment == :dine_in)}
                      >
                        Dine-in
                      </button>
                    </div>
                    <label
                      :if={@fulfillment == :dine_in}
                      class="staff-pos-field"
                      for="pos-table-number"
                    >
                      <span class="staff-pos-field-label">Table</span>
                      <input
                        type="text"
                        inputmode="numeric"
                        class="staff-pos-field-input"
                        id="pos-table-number"
                        name="table_number"
                        value={@table_number}
                        phx-change="set_table_number"
                        phx-debounce="200"
                        autocomplete="off"
                        maxlength="2"
                        placeholder="1–99"
                      />
                    </label>

                    <label class="staff-pos-field staff-pos-field--notes" for="pos-notes">
                      <span class="staff-pos-field-label">Notes</span>
                      <textarea
                        class="staff-pos-field-textarea"
                        id="pos-notes"
                        name="notes"
                        phx-change="set_notes"
                        phx-debounce="300"
                        rows="1"
                        placeholder="Less ice, oat milk, etc."
                      >{@notes}</textarea>
                    </label>
                  </div>
                </div>

                <div class="staff-pos-ticket-body">
                  <p class="staff-pos-section-label">Items</p>
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
                      <div class="staff-pos-qty-controls">
                        <button
                          type="button"
                          class="staff-pos-qty-btn"
                          phx-click="dec"
                          phx-value-key={line.key}
                          aria-label={"Decrease #{line.name}"}
                        >
                          −
                        </button>
                        <span class="staff-pos-qty">{line.quantity}</span>
                        <button
                          type="button"
                          class="staff-pos-qty-btn"
                          phx-click="inc"
                          phx-value-key={line.key}
                          aria-label={"Increase #{line.name}"}
                        >
                          +
                        </button>
                      </div>
                      <button
                        type="button"
                        class="staff-pos-remove"
                        phx-click="remove"
                        phx-value-key={line.key}
                        aria-label={"Remove #{line.name}"}
                        title="Remove"
                      >
                        ×
                      </button>
                    </div>
                  </li>
                </ul>
              </div>

              <div class="staff-pos-ticket-footer">
                <p class="staff-pos-section-label">Payment</p>
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

                <div
                  class="menu-checkout-options staff-pos-payment"
                  id="pos-payment-choice"
                  role="radiogroup"
                  aria-label="Payment"
                >
                  <button
                    type="button"
                    class={["menu-checkout-option", @payment_choice == :unpaid && "is-active"]}
                    id="pos-payment-unpaid"
                    phx-click="set_payment_choice"
                    phx-value-choice="unpaid"
                    aria-pressed={to_string(@payment_choice == :unpaid)}
                  >
                    Unpaid
                  </button>
                  <button
                    type="button"
                    class={["menu-checkout-option", @payment_choice == :paid && "is-active"]}
                    id="pos-payment-paid"
                    phx-click="set_payment_choice"
                    phx-value-choice="paid"
                    aria-pressed={to_string(@payment_choice == :paid)}
                  >
                    Paid
                  </button>
                </div>

                <div
                  :if={@payment_choice == :paid}
                  class="menu-checkout-options staff-pos-payment staff-pos-tender"
                  id="pos-paid-via"
                  role="radiogroup"
                  aria-label="Tender"
                >
                  <button
                    :for={{via, label} <- [{"cash", "Cash"}, {"gcash", "GCash"}, {"maya", "Maya"}]}
                    type="button"
                    class={["menu-checkout-option", @paid_via == via && "is-active"]}
                    id={"pos-paid-via-#{via}"}
                    phx-click="set_paid_via"
                    phx-value-paid_via={via}
                    aria-pressed={to_string(@paid_via == via)}
                  >
                    {label}
                  </button>
                </div>

                <button
                  type="button"
                  class={[
                    "staff-pos-place",
                    (@cart == [] or @placing_order?) && "is-disabled"
                  ]}
                  id="pos-place-order"
                  phx-click="place_order"
                  disabled={@cart == [] or @placing_order?}
                >
                  Process Order
                </button>
              </div>
            <% end %>
          </aside>
          </div>
        </main>

        <div
          :if={@size_picker}
          class="staff-pos-modal"
        id="pos-size-picker"
        phx-window-keydown="cancel_size"
        phx-key="Escape"
      >
        <div class="staff-pos-modal-backdrop" phx-click="cancel_size" aria-hidden="true"></div>
        <div
          class="staff-pos-modal-panel"
          role="dialog"
          aria-modal="true"
          aria-labelledby="pos-size-title"
        >
          <div class="staff-pos-size-picker-head">
            <p id="pos-size-title">Select size — {@size_picker.name}</p>
            <button type="button" class="staff-action" phx-click="cancel_size">Cancel</button>
          </div>
          <div class="staff-pos-size-options">
            <button
              :for={price <- @size_picker.product_prices}
              type="button"
              class="staff-pos-size-option"
              id={"pos-size-#{price.id}"}
              phx-click="select_size"
              phx-value-product-id={@size_picker.id}
              phx-value-price-id={price.id}
            >
              <span class="staff-pos-product-name">{price.size || "Regular"}</span>
              <span class="staff-pos-product-price">{Menu.format_price(price.price)}</span>
            </button>
          </div>
        </div>
      </div>
      </div>
    </.staff_shell>
    """
  end

  defp products_for(categories, selected) do
    case Enum.find(categories, &(&1.name == selected)) do
      %{products: products} -> products
      _ -> []
    end
  end

  defp visible_products(categories, selected, search) do
    query = search |> to_string() |> String.trim() |> String.downcase()

    products_for(categories, selected)
    |> Enum.filter(fn product ->
      query == "" or String.contains?(String.downcase(product.name), query)
    end)
  end

  defp product_cards(categories, selected, search) do
    Enum.map(visible_products(categories, selected, search), fn product ->
      {product, Menu.product_image_meta(selected || "", product.name)}
    end)
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

  defp cart_item_count(cart) do
    Enum.reduce(cart, 0, fn line, acc -> acc + line.quantity end)
  end

  defp unavailable_error([name]), do: "#{name} is no longer available. Remove it or choose something else."

  defp unavailable_error(names) when is_list(names) do
    "#{Enum.join(names, ", ")} are no longer available. Remove them or choose something else."
  end

  defp blank_notes(notes) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank_notes(_), do: nil

  defp valid_table?(table) when is_binary(table) do
    case Integer.parse(String.trim(table)) do
      {n, ""} when n in 1..99 -> true
      _ -> false
    end
  end

  defp valid_table?(_), do: false

  defp order_note(%{notes: notes}) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: nil, else: trimmed
  end

  defp order_note(_), do: nil

  defp print_note(:ok, paid_via) do
    if Printer.cash_like?(paid_via || "cash") do
      "Receipt printed · kaha opened"
    else
      "Receipt printed"
    end
  end

  defp print_note(:disabled, _), do: nil
  defp print_note({:error, reason}, _), do: "Order saved · print failed (#{inspect(reason)})"
  defp print_note(_, _), do: nil
end

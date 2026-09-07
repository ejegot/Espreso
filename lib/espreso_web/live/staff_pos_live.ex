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
    selected = default_pos_category(categories)

    {:ok,
     socket
     |> assign(:page_title, "POS")
     |> assign(:categories, categories)
     |> assign(:selected_category, selected)
     |> assign(:menu_filter, nil)
     |> assign(:search, "")
     |> assign(:cart, [])
     |> assign(:customer_name, "Walk-in")
     |> assign(:notes, "")
     |> assign(:fulfillment, :pickup)
     |> assign(:table_number, "")
     |> assign(:payment_choice, :paid)
     |> assign(:paid_via, "cash")
     |> assign(:cash_tendered, "")
     |> assign(:last_cash_change, nil)
     |> assign(:print_failed?, false)
     |> assign(:place_flash, nil)
     |> assign(:notes_open?, false)
     |> assign(:placing_order?, false)
     |> assign(:card_sizes, %{})
     |> assign(:added_product_id, nil)
     |> assign(:last_order, nil)
     |> assign(:print_note, nil)
     |> assign(:error, nil), layout: false}
  end

  @impl true
  def handle_info({:order_changed, order}, socket) do
    StaffNotifications.push_order_change(order)
    {:noreply, socket}
  end

  def handle_info(:clear_place_flash, socket) do
    {:noreply, assign(socket, :place_flash, nil)}
  end

  def handle_info(:clear_added_product, socket) do
    {:noreply, assign(socket, :added_product_id, nil)}
  end

  @impl true
  def handle_event("select_category", %{"name" => name}, socket) when name != "ALL" do
    {:noreply,
     socket
     |> assign(:selected_category, name)
     |> assign(:menu_filter, nil)
     |> assign(:error, nil)}
  end

  def handle_event("select_category", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("select_filter", %{"filter" => "matcha"}, socket) do
    {:noreply,
     socket
     |> assign(:selected_category, nil)
     |> assign(:menu_filter, :matcha)
     |> assign(:error, nil)}
  end

  def handle_event("select_filter", %{"filter" => "sweets"}, socket) do
    {:noreply,
     socket
     |> assign(:selected_category, nil)
     |> assign(:menu_filter, :sweets)
     |> assign(:error, nil)}
  end

  def handle_event("search", params, socket) do
    {:noreply, assign(socket, :search, Map.get(params, "q", ""))}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, :search, "")}
  end

  def handle_event("select_card_size", %{"product-id" => product_id, "price-id" => price_id}, socket) do
    product_id = String.to_integer(product_id)
    price_id = String.to_integer(price_id)

    {:noreply,
     assign(socket, :card_sizes, Map.put(socket.assigns.card_sizes, product_id, price_id))}
  end

  def handle_event("add_to_cart", %{"product-id" => product_id}, socket) do
    product_id = String.to_integer(product_id)

    with {category_name, %{product_prices: prices} = product} <-
           find_product_entry(socket.assigns.categories, product_id),
         %{} = price <- selected_price(product, prices, socket.assigns.card_sizes) do
      if connected?(socket), do: Process.send_after(self(), :clear_added_product, 1_200)

      {:noreply,
       socket
       |> assign(:cart, add_line(socket.assigns.cart, product, price, category_name, 1))
       |> assign(:added_product_id, product_id)
       |> assign(:error, nil)
       |> assign(:last_order, nil)
       |> assign(:print_note, nil)
       |> assign(:place_flash, nil)}
    else
      _ ->
        {:noreply, assign(socket, :error, "Product is unavailable.")}
    end
  end

  # Legacy: tapping old add_product / select_size paths still work.
  def handle_event("add_product", params, socket) do
    handle_event("add_to_cart", params, socket)
  end

  def handle_event("select_size", params, socket) do
    {:noreply, socket} = handle_event("select_card_size", params, socket)
    handle_event("add_to_cart", %{"product-id" => params["product-id"]}, socket)
  end

  def handle_event("cancel_size", _params, socket), do: {:noreply, socket}

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
    {:noreply, reset_ticket(socket)}
  end

  def handle_event("dismiss_place_flash", _params, socket) do
    {:noreply, assign(socket, :place_flash, nil)}
  end

  def handle_event("toggle_notes", _params, socket) do
    {:noreply, assign(socket, :notes_open?, !socket.assigns[:notes_open?])}
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

    {:noreply,
     socket
     |> assign(:fulfillment, fulfillment)
     |> assign(:table_number, "")}
  end

  def handle_event("set_payment_method", %{"method" => paid_via}, socket)
      when paid_via in ["cash", "gcash"] do
    {:noreply,
     socket
     |> assign(:payment_choice, :paid)
     |> assign(:paid_via, paid_via)
     |> assign(:cash_tendered, "")}
  end

  def handle_event("set_payment_method", _params, socket), do: {:noreply, socket}

  # Legacy aliases kept for older clients / tests during transition.
  def handle_event("set_payment_choice", %{"choice" => "unpaid"}, socket) do
    handle_event("set_payment_method", %{"method" => "unpaid"}, socket)
  end

  def handle_event("set_payment_choice", %{"choice" => "paid"}, socket) do
    handle_event("set_payment_method", %{"method" => socket.assigns.paid_via || "cash"}, socket)
  end

  def handle_event("set_paid_via", %{"paid_via" => paid_via}, socket) do
    handle_event("set_payment_method", %{"method" => paid_via}, socket)
  end

  def handle_event("set_cash_tendered", %{"cash_tendered" => amount}, socket) do
    {:noreply, assign(socket, :cash_tendered, String.trim(amount))}
  end

  def handle_event("cash_exact", _params, socket) do
    total = cart_total(socket.assigns.cart) |> Decimal.round(2) |> Decimal.to_string(:normal)
    {:noreply, assign(socket, :cash_tendered, total)}
  end

  def handle_event("cash_chip", %{"amount" => amount}, socket) do
    case parse_money(amount) do
      {:ok, chip} ->
        current =
          case parse_money(socket.assigns.cash_tendered) do
            {:ok, value} -> value
            :error -> Decimal.new(0)
          end

        next = Decimal.add(current, chip) |> Decimal.round(2) |> Decimal.to_string(:normal)
        {:noreply, assign(socket, :cash_tendered, next)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("reprint_receipt", _params, socket) do
    case socket.assigns.last_order do
      nil ->
        {:noreply, socket}

      order ->
        order = Espreso.Repo.preload(order, :items)
        opts = print_opts(socket, order)

        {note, failed?} =
          case Printer.after_paid(order, order.paid_via || "cash", opts) do
            :ok ->
              if Printer.cash_like?(order.paid_via || "cash") do
                {"Receipt printed · kaha opened.", false}
              else
                {"Receipt printed.", false}
              end

            :disabled ->
              {"Printer is not enabled on this server.", false}

            {:error, reason} ->
              {"Print failed (#{inspect(reason)}). Tap Retry.", true}
          end

        {:noreply,
         socket
         |> assign(:print_note, note)
         |> assign(:print_failed?, failed?)}
    end
  end

  def handle_event("print_kitchen", _params, socket) do
    case socket.assigns.last_order do
      nil ->
        {:noreply, socket}

      order ->
        order = Espreso.Repo.preload(order, :items)

        note =
          case Printer.print_kitchen(order, staff_name: socket.assigns.current_user.name) do
            :ok -> "Kitchen ticket printed."
            :disabled -> "Printer is not enabled on this server."
            {:error, reason} -> "Kitchen print failed (#{inspect(reason)})."
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

      cash_short?(socket) ->
        {:noreply, assign(socket, :error, "Cash tendered is less than the total.")}

      true ->
        customer_name = String.trim(socket.assigns.customer_name)
        paid? = socket.assigns.payment_choice == :paid
        paid_via = if paid?, do: socket.assigns.paid_via, else: nil
        {tendered, change} = cash_amounts(socket)

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
          table_number: nil,
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
                opts =
                  [staff_name: socket.assigns.current_user.name] ++
                    if(tendered, do: [cash_tendered: tendered, change: change], else: [])

                Printer.after_paid(order, order.paid_via || paid_via || "cash", opts)
              else
                :disabled
              end

            {note, failed?} = print_note_result(print_result, order.paid_via || paid_via)

            cash_change = if(change, do: %{tendered: tendered, change: change})

            socket =
              socket
              |> assign(:cart, [])
              |> assign(:card_sizes, %{})
              |> assign(:added_product_id, nil)
              |> assign(:error, nil)
              |> assign(:payment_choice, :paid)
              |> assign(:paid_via, "cash")
              |> assign(:cash_tendered, "")
              |> assign(:fulfillment, :pickup)
              |> assign(:table_number, "")
              |> assign(:placing_order?, false)
              |> assign(:notes, "")
              |> assign(:notes_open?, false)
              |> assign(:categories, Menu.list_menu())
              |> assign(:last_cash_change, cash_change)
              |> assign(:print_note, note)
              |> assign(:print_failed?, failed?)

            socket =
              if failed? do
                assign(socket, :last_order, order)
                |> assign(:place_flash, nil)
              else
                flash = place_flash_message(order, note, cash_change)

                if connected?(socket), do: Process.send_after(self(), :clear_place_flash, 4_000)

                socket
                |> assign(:last_order, nil)
                |> assign(:place_flash, flash)
              end

            {:noreply, socket}

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
    <.staff_shell current={:pos} current_user={@current_user} page_title="POS" chrome={:rail}>
      <div class="staff-pos-page staff-pos-shell-root staff-pos-page--cafe">
        <main class="staff-pos-main">
          <p :if={@error} class="staff-pos-flash" id="pos-error">{@error}</p>
          <p :if={@place_flash} class="staff-pos-place-flash" id="pos-place-flash">
            <span>{@place_flash}</span>
            <button
              type="button"
              class="staff-pos-place-flash-dismiss"
              id="pos-place-flash-dismiss"
              phx-click="dismiss_place_flash"
              aria-label="Dismiss"
            >
              ×
            </button>
          </p>

          <div class="staff-pos-layout staff-pos-layout--cafe">
            <section class="staff-pos-catalog" id="pos-catalog">
              <div class="staff-pos-catalog-toolbar">
                <form class="staff-pos-search" id="pos-search" phx-change="search" phx-submit="search">
                  <label class="staff-pos-search-label" for="pos-search-input">Search</label>
                  <div class="staff-pos-search-row">
                    <input
                      type="search"
                      class="staff-pos-search-input"
                      id="pos-search-input"
                      name="q"
                      value={@search}
                      placeholder="Search menu"
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

                <header class="staff-pos-catalog-head">
                  <div>
                    <h2 class="staff-pos-catalog-title" id="pos-catalog-title">
                      Categories
                    </h2>
                  </div>
                  <span class="staff-pos-catalog-count" id="pos-catalog-count">
                    {length(
                      visible_product_entries(
                        @categories,
                        @selected_category,
                        @menu_filter,
                        @search
                      )
                    )}
                  </span>
                </header>

                <nav class="staff-pos-categories staff-pos-categories--pills" aria-label="Categories">
                  <button
                    :for={chip <- pos_category_chips(@categories)}
                    type="button"
                    class={[
                      "staff-pos-category",
                      chip_active?(chip, @selected_category, @menu_filter) && "is-active"
                    ]}
                    phx-click={chip.event}
                    phx-value-name={chip[:name]}
                    phx-value-filter={chip[:filter]}
                    id={"pos-category-#{chip.key}"}
                  >
                    <span class="staff-pos-category-label">{chip.label}</span>
                  </button>
                </nav>
              </div>

              <div class="staff-pos-products staff-pos-products--rows" id="pos-products">
                <article
                  :for={{product, img} <-
                    product_cards(
                      @categories,
                      @selected_category,
                      @menu_filter,
                      @search
                    )}
                  class={[
                    "staff-pos-product-card",
                    @added_product_id == product.id && "is-added"
                  ]}
                  id={"pos-product-#{product.id}"}
                  role="button"
                  tabindex="0"
                  phx-click="add_to_cart"
                  phx-value-product-id={product.id}
                  aria-label={
                    if @added_product_id == product.id,
                      do: "Added #{product.name}",
                      else: "Add #{product.name}"
                  }
                >
                  <div class="staff-pos-product-card-media" aria-hidden="true">
                    <img
                      src={img.src}
                      alt=""
                      class={["staff-pos-product-img", img.packshot? && "is-packshot"]}
                      loading="lazy"
                    />
                  </div>
                  <div class="staff-pos-product-card-body">
                    <h3 class="staff-pos-product-name">{product.name}</h3>
                    <div
                      class="staff-pos-product-sizes"
                      role="radiogroup"
                      aria-label={"Size for #{product.name}"}
                    >
                      <div class="staff-pos-size-chips">
                        <button
                          :for={price <- product.product_prices}
                          type="button"
                          class={[
                            "staff-pos-size-chip",
                            selected_price_id(product, @card_sizes) == price.id && "is-active"
                          ]}
                          id={"pos-size-#{price.id}"}
                          phx-click="select_card_size"
                          phx-value-product-id={product.id}
                          phx-value-price-id={price.id}
                          aria-pressed={
                            to_string(selected_price_id(product, @card_sizes) == price.id)
                          }
                        >
                          {size_label(price.size)}
                        </button>
                      </div>
                    </div>
                    <p class="staff-pos-product-price">
                      {displayed_price_label(product, @card_sizes)}
                    </p>
                  </div>
                </article>
                <p
                  :if={
                    visible_product_entries(
                      @categories,
                      @selected_category,
                      @menu_filter,
                      @search
                    ) == []
                  }
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
            </section>

            <aside
              class={["staff-pos-ticket", @cart == [] && !@last_order && "is-empty"]}
              id="pos-ticket"
            >
              <%= if @last_order do %>
                <div class="staff-pos-success" id="pos-confirmation">
                  <div class="staff-pos-success-badge" aria-hidden="true">!</div>
                  <p class="staff-pos-success-eyebrow">Print failed · order saved</p>
                  <p class="staff-order-number">{@last_order.number}</p>
                  <p class="staff-order-meta">
                    {Orders.status_label(@last_order.status)} · {@last_order.customer_name}
                    · {Orders.payment_label(@last_order)}
                  </p>
                  <p
                    :if={@print_note}
                    class="staff-pos-success-note is-error"
                    id="pos-print-note"
                  >
                    {@print_note}
                  </p>
                  <div class="staff-pos-success-actions">
                    <button
                      :if={Printer.enabled?()}
                      type="button"
                      class="staff-pos-place"
                      id="pos-retry-print"
                      phx-click="reprint_receipt"
                    >
                      Retry print
                    </button>
                    <div class="staff-pos-success-secondary">
                      <button
                        :if={Printer.enabled?()}
                        type="button"
                        class="staff-pos-mini"
                        id="pos-print-kitchen"
                        phx-click="print_kitchen"
                      >
                        Kitchen
                      </button>
                      <button
                        :if={
                          Printer.enabled?() and
                            Printer.cash_like?(@last_order.paid_via || "cash")
                        }
                        type="button"
                        class="staff-pos-mini"
                        id="pos-open-kaha"
                        phx-click="open_drawer"
                      >
                        Kaha
                      </button>
                    </div>
                    <button
                      type="button"
                      class="staff-pos-place"
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
                  <div class="staff-pos-staff" id="pos-staff">
                    <div class="staff-pos-staff-avatar" aria-hidden="true">
                      {staff_initials(@current_user.name)}
                    </div>
                    <div class="staff-pos-staff-copy">
                      <p class="staff-pos-staff-name">{@current_user.name}</p>
                      <p class="staff-pos-staff-meta">{@current_user.email}</p>
                    </div>
                  </div>

                  <div class="staff-pos-ticket-title-row">
                    <h2>Cart</h2>
                    <span :if={cart_item_count(@cart) > 0} class="staff-pos-cart-count">
                      {cart_item_count(@cart)} items
                    </span>
                  </div>

                  <div
                    class="staff-pos-fulfillment staff-pos-fulfillment--pills"
                    id="pos-fulfillment"
                    role="radiogroup"
                    aria-label="Fulfillment"
                  >
                    <button
                      type="button"
                      class={["staff-pos-fulfill-chip", @fulfillment == :dine_in && "is-active"]}
                      id="pos-fulfillment-dine-in"
                      phx-click="set_fulfillment"
                      phx-value-fulfillment="dine_in"
                      aria-pressed={to_string(@fulfillment == :dine_in)}
                    >
                      Dine-in
                    </button>
                    <button
                      type="button"
                      class={["staff-pos-fulfill-chip", @fulfillment == :pickup && "is-active"]}
                      id="pos-fulfillment-pickup"
                      phx-click="set_fulfillment"
                      phx-value-fulfillment="pickup"
                      aria-pressed={to_string(@fulfillment == :pickup)}
                    >
                      Takeout
                    </button>
                  </div>

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
                      placeholder="Walk-in"
                    />
                  </label>

                  <button
                    :if={
                      @cart != [] or @notes_open? or order_note(%{notes: @notes}) != nil
                    }
                    type="button"
                    class="staff-pos-notes-toggle"
                    id="pos-notes-toggle"
                    phx-click="toggle_notes"
                    aria-expanded={to_string(@notes_open? or order_note(%{notes: @notes}) != nil)}
                  >
                    {if @notes_open? or order_note(%{notes: @notes}),
                      do: "Notes ▴",
                      else: "Notes ▾"}
                  </button>
                  <label
                    :if={@notes_open? or order_note(%{notes: @notes}) != nil}
                    class="staff-pos-field staff-pos-field--notes"
                    for="pos-notes"
                  >
                    <textarea
                      class="staff-pos-field-textarea"
                      id="pos-notes"
                      name="notes"
                      phx-change="set_notes"
                      phx-debounce="300"
                      rows="2"
                      placeholder="Less ice, oat milk…"
                    >{@notes}</textarea>
                  </label>
                </div>

                <div class="staff-pos-ticket-body">
                  <p :if={@cart == []} class="staff-empty" id="pos-cart-empty">No items yet.</p>

                  <ul class="staff-pos-cart" id="pos-cart-lines">
                    <li :for={line <- @cart} class="staff-pos-cart-line" id={"pos-line-#{line.key}"}>
                      <div class="staff-pos-cart-thumb" aria-hidden="true">
                        <img
                          :if={line[:image]}
                          src={line.image}
                          alt=""
                          class="staff-pos-cart-thumb-img"
                          loading="lazy"
                        />
                      </div>
                      <div class="staff-pos-cart-main">
                        <div class="staff-pos-cart-copy">
                          <p class="staff-pos-cart-name">{line.name}</p>
                          <p class="staff-pos-cart-size">{size_label(line.size)}</p>
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
                              class="staff-pos-qty-btn staff-pos-qty-btn--plus"
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
                      </div>
                    </li>
                  </ul>
                </div>

                <div class="staff-pos-ticket-footer">
                  <div class="staff-pos-totals">
                    <div class="staff-pos-total-row">
                      <span>Items</span>
                      <span>{Menu.format_price(cart_total(@cart))}</span>
                    </div>
                    <div class="staff-pos-total-row staff-pos-total-row--grand">
                      <span>Total</span>
                      <span id="pos-total">{Menu.format_price(cart_total(@cart))}</span>
                    </div>
                  </div>

                  <p class="staff-pos-section-label">Payment method</p>
                  <div
                    class="staff-pos-payment staff-pos-tender staff-pos-tender--methods"
                    id="pos-payment-methods"
                    role="radiogroup"
                    aria-label="Payment method"
                  >
                    <button
                      type="button"
                      class={[
                        "staff-pos-pay-chip",
                        @payment_choice == :paid and @paid_via == "cash" && "is-active"
                      ]}
                      id="pos-pay-cash"
                      phx-click="set_payment_method"
                      phx-value-method="cash"
                      aria-pressed={to_string(@payment_choice == :paid and @paid_via == "cash")}
                    >
                      Cash
                    </button>
                    <button
                      type="button"
                      class={[
                        "staff-pos-pay-chip",
                        @payment_choice == :paid and @paid_via == "gcash" && "is-active"
                      ]}
                      id="pos-pay-gcash"
                      phx-click="set_payment_method"
                      phx-value-method="gcash"
                      aria-pressed={to_string(@payment_choice == :paid and @paid_via == "gcash")}
                    >
                      GCash
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
      </div>
    </.staff_shell>
    """
  end

  defp default_pos_category(categories) do
    cond do
      Enum.any?(categories, &(&1.name == "HOT")) -> "HOT"
      true -> categories |> List.first() |> then(&(&1 && &1.name))
    end
  end

  defp pos_category_chips(categories) do
    category_chips =
      for category <- categories do
        %{
          key: category.name,
          label: category_nav_label(category.name),
          event: "select_category",
          name: category.name,
          count: length(category.products)
        }
      end

    matcha_count = matcha_entries(categories) |> length()
    sweets_count = sweets_entries(categories) |> length()

    filter_chips =
      []
      |> then(fn chips ->
        if matcha_count > 0 do
          chips ++
            [
              %{
                key: "matcha",
                label: "Matcha",
                event: "select_filter",
                filter: "matcha",
                count: matcha_count
              }
            ]
        else
          chips
        end
      end)
      |> then(fn chips ->
        if sweets_count > 0 do
          chips ++
            [
              %{
                key: "sweets",
                label: "Sweets",
                event: "select_filter",
                filter: "sweets",
                count: sweets_count
              }
            ]
        else
          chips
        end
      end)

    category_chips ++ filter_chips
  end

  defp chip_active?(%{key: "matcha"}, _selected, :matcha), do: true
  defp chip_active?(%{key: "sweets"}, _selected, :sweets), do: true
  defp chip_active?(%{name: name}, selected, nil) when is_binary(name), do: selected == name
  defp chip_active?(_chip, _selected, _filter), do: false

  defp category_nav_label("HOT"), do: "Hot coffee"
  defp category_nav_label("COLD"), do: "Iced coffee"
  defp category_nav_label("FRAPPE"), do: "Frappe"
  defp category_nav_label("SODA"), do: "Soda"
  defp category_nav_label("FOOD"), do: "Food"
  defp category_nav_label(name) when is_binary(name), do: name
  defp category_nav_label(_), do: "Products"

  defp visible_product_entries(categories, selected, filter, search) do
    query = search |> to_string() |> String.trim() |> String.downcase()

    entries =
      case filter do
        :matcha -> matcha_entries(categories)
        :sweets -> sweets_entries(categories)
        _ -> category_entries(categories, selected)
      end

    Enum.filter(entries, fn {_category_name, product} ->
      query == "" or String.contains?(String.downcase(product.name), query)
    end)
  end

  defp category_entries(categories, "ALL") do
    Enum.flat_map(categories, fn category ->
      Enum.map(category.products, &{category.name, &1})
    end)
  end

  defp category_entries(categories, selected) do
    case Enum.find(categories, &(&1.name == selected)) do
      %{products: products, name: name} -> Enum.map(products, &{name, &1})
      _ -> []
    end
  end

  defp matcha_entries(categories) do
    Enum.flat_map(categories, fn category ->
      category.products
      |> Enum.filter(&matcha_product?/1)
      |> Enum.map(&{category.name, &1})
    end)
  end

  defp sweets_entries(categories) do
    Enum.flat_map(categories, fn category ->
      category.products
      |> Enum.filter(&sweets_product?/1)
      |> Enum.map(&{category.name, &1})
    end)
  end

  defp matcha_product?(%{name: name}) when is_binary(name) do
    String.contains?(String.downcase(name), "matcha")
  end

  defp matcha_product?(_), do: false

  defp sweets_product?(%{name: name}), do: Menu.sweets_product_name?(name)
  defp sweets_product?(_), do: false

  defp product_cards(categories, selected, filter, search) do
    Enum.map(visible_product_entries(categories, selected, filter, search), fn {category_name, product} ->
      {product, Menu.product_image_meta(category_name || "", product.name)}
    end)
  end

  defp find_product_entry(categories, product_id) do
    Enum.find_value(categories, fn category ->
      case Enum.find(category.products, &(&1.id == product_id)) do
        nil -> nil
        product -> {category.name, product}
      end
    end)
  end

  defp size_label(nil), do: "Regular"
  defp size_label(""), do: "Regular"
  defp size_label(size) when is_binary(size), do: size
  defp size_label(_), do: "Regular"

  defp selected_price_id(%{product_prices: [price]}, _card_sizes), do: price.id

  defp selected_price_id(%{id: product_id, product_prices: prices}, card_sizes) do
    case Map.get(card_sizes, product_id) do
      nil ->
        prices |> List.first() |> then(&(&1 && &1.id))

      price_id ->
        if Enum.any?(prices, &(&1.id == price_id)), do: price_id, else: List.first(prices).id
    end
  end

  defp selected_price(product, prices, card_sizes) do
    price_id = selected_price_id(product, card_sizes)
    Enum.find(prices, &(&1.id == price_id)) || List.first(prices)
  end

  defp displayed_price_label(%{product_prices: prices} = product, card_sizes) do
    case selected_price(product, prices, card_sizes) do
      %{price: price} -> Menu.format_price(price)
      _ -> price_label(product)
    end
  end

  defp price_label(%{product_prices: [price]}), do: Menu.format_price(price.price)

  defp price_label(%{product_prices: prices}) do
    prices
    |> Enum.map(& &1.price)
    |> Enum.min(Decimal)
    |> Menu.format_price()
    |> then(&"from #{&1}")
  end

  defp add_line(cart, product, price, category_name, quantity) do
    key = "#{product.id}-#{price.id}"
    image = Menu.product_image_meta(category_name || "", product.name).src
    quantity = max(quantity, 1)

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
              quantity: quantity,
              image: image
            }
          ]

      index ->
        List.update_at(cart, index, fn line ->
          %{line | quantity: line.quantity + quantity}
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

  defp reset_ticket(socket) do
    socket
    |> assign(:cart, [])
    |> assign(:card_sizes, %{})
    |> assign(:added_product_id, nil)
    |> assign(:last_order, nil)
    |> assign(:print_note, nil)
    |> assign(:print_failed?, false)
    |> assign(:last_cash_change, nil)
    |> assign(:place_flash, nil)
    |> assign(:error, nil)
    |> assign(:payment_choice, :paid)
    |> assign(:paid_via, "cash")
    |> assign(:cash_tendered, "")
    |> assign(:fulfillment, :pickup)
    |> assign(:table_number, "")
    |> assign(:placing_order?, false)
    |> assign(:customer_name, "Walk-in")
    |> assign(:notes, "")
    |> assign(:notes_open?, false)
  end

  defp place_flash_message(order, print_note, cash_change) do
    base =
      "#{order.number} · #{order.customer_name} · #{Orders.status_label(order.status)} · #{Orders.payment_label(order)}"

    extras =
      [
        print_note,
        if(cash_change,
          do: "Change #{Menu.format_price(cash_change.change)}",
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)

    case extras do
      [] -> base
      list -> Enum.join([base | list], " · ")
    end
  end

  defp blank_notes(notes) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank_notes(_), do: nil

  defp parse_money(amount) when is_binary(amount) do
    cleaned =
      amount
      |> String.trim()
      |> String.replace(",", "")

    case Decimal.parse(cleaned) do
      {decimal, ""} -> {:ok, Decimal.round(decimal, 2)}
      _ -> :error
    end
  end

  defp parse_money(_), do: :error

  defp cash_short?(_socket), do: false

  defp cash_amounts(_socket), do: {nil, nil}

  defp staff_initials(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(fn part -> part |> String.first() |> to_string() |> String.upcase() end)
    |> Enum.join()
    |> case do
      "" -> "CS"
      initials -> initials
    end
  end

  defp staff_initials(_), do: "CS"

  defp print_opts(socket, order) do
    base = [staff_name: socket.assigns.current_user.name]
    paid_via = order.paid_via || "cash"

    case socket.assigns.last_cash_change do
      %{tendered: tendered, change: change}
      when not is_nil(tendered) and not is_nil(change) ->
        if Printer.cash_like?(paid_via) do
          base ++ [cash_tendered: tendered, change: change]
        else
          base
        end

      _ ->
        base
    end
  end

  defp print_note_result(:ok, paid_via) do
    note =
      if Printer.cash_like?(paid_via || "cash") do
        "Receipt printed · kaha opened"
      else
        "Receipt printed"
      end

    {note, false}
  end

  defp print_note_result(:disabled, _), do: {nil, false}

  defp print_note_result({:error, reason}, _) do
    {"Order saved · print failed (#{inspect(reason)}). Tap Retry.", true}
  end

  defp print_note_result(_, _), do: {nil, false}

  defp order_note(%{notes: notes}) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: nil, else: trimmed
  end

  defp order_note(_), do: nil
end

defmodule EspresoWeb.StaffPosLive do
  use EspresoWeb, :live_view

  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Printer
  alias EspresoWeb.StaffNotifications
  alias Phoenix.LiveView.JS

  @cart_undo_timeout_ms 4_000

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
     |> assign(:cash_tender_open?, false)
     |> assign(:cash_tender_error, nil)
     |> assign(:cash_tender_token, nil)
     |> assign(:last_cash_change, nil)
     |> assign(:print_failed?, false)
     |> assign(:print_retry_token, nil)
     |> assign(:print_note_error?, false)
     |> assign(:place_flash, nil)
     |> assign(:place_flash_token, nil)
     |> assign(:place_flash_timer, nil)
     |> assign(:notes_open?, false)
     |> assign(:placing_order?, false)
     |> assign(:cart_undo, nil)
     |> assign(:cart_undo_timer, nil)
     |> assign(:variant_editor_key, nil)
     |> assign(:card_sizes, %{})
     |> assign(:added_product_id, nil)
     |> assign(:last_order, nil)
     |> assign(:print_note, nil)
     |> assign(:error, nil)
     |> assign(:submission_error, nil), layout: false}
  end

  @impl true
  def handle_info({:order_changed, order}, socket) do
    StaffNotifications.push_order_change(order)
    {:noreply, socket}
  end

  def handle_info(
        {:clear_place_flash, token},
        %{assigns: %{place_flash_token: token}} = socket
      ) do
    {:noreply, clear_place_flash(socket)}
  end

  def handle_info({:clear_place_flash, _token}, socket), do: {:noreply, socket}

  def handle_info(:clear_added_product, socket) do
    {:noreply, assign(socket, :added_product_id, nil)}
  end

  def handle_info(
        {:expire_cart_undo, token},
        %{assigns: %{cart_undo: %{token: token}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:cart_undo, nil)
     |> assign(:cart_undo_timer, nil)}
  end

  def handle_info({:expire_cart_undo, _token}, socket), do: {:noreply, socket}

  @impl true
  def handle_event(event, _params, %{assigns: %{cash_tender_open?: true}} = socket)
      when event in [
             "toggle_cart_variant",
             "change_cart_variant",
             "select_card_size",
             "add_to_cart",
             "add_product",
             "select_size",
             "inc",
             "dec",
             "remove",
             "clear_ticket",
             "undo_cart",
             "set_customer_name",
             "set_notes",
             "set_fulfillment",
             "set_payment_method",
             "set_payment_choice",
             "set_paid_via"
           ] do
    {:noreply, socket}
  end

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

  def handle_event(
        "toggle_cart_variant",
        _params,
        %{assigns: %{last_order: last_order}} = socket
      )
      when not is_nil(last_order) do
    {:noreply, socket}
  end

  def handle_event("toggle_cart_variant", %{"key" => key}, socket) do
    editor_key =
      case uniquely_find_cart_line(socket.assigns.cart, key) do
        {:ok, line, _index} ->
          if length(cart_variant_options(socket.assigns.categories, line)) > 1 do
            if socket.assigns.variant_editor_key == key, do: nil, else: key
          else
            nil
          end

        :error ->
          socket.assigns.variant_editor_key
      end

    {:noreply, assign(socket, :variant_editor_key, editor_key)}
  end

  def handle_event("toggle_cart_variant", _params, socket), do: {:noreply, socket}

  def handle_event(
        "change_cart_variant",
        _params,
        %{assigns: %{last_order: last_order}} = socket
      )
      when not is_nil(last_order) do
    {:noreply, socket}
  end

  def handle_event("change_cart_variant", params, socket) do
    key = Map.get(params, "key")
    price_id = Map.get(params, "price-id") || Map.get(params, "price_id")

    socket =
      with key when is_binary(key) <- key,
           {:ok, price_id} <- parse_positive_id(price_id),
           {:ok, line, _index} <- uniquely_find_cart_line(socket.assigns.cart, key) do
        if line.price_id == price_id do
          assign(socket, :variant_editor_key, nil)
        else
          change_cart_line_variant(socket, line, key, price_id)
        end
      else
        _ -> socket
      end

    {:noreply, socket}
  end

  def handle_event("select_card_size", %{"product-id" => product_id, "price-id" => price_id}, socket) do
    product_id = String.to_integer(product_id)
    price_id = String.to_integer(price_id)

    {:noreply,
     assign(socket, :card_sizes, Map.put(socket.assigns.card_sizes, product_id, price_id))}
  end

  def handle_event(
        "add_to_cart",
        _params,
        %{assigns: %{last_order: last_order}} = socket
      )
      when not is_nil(last_order) do
    {:noreply, socket}
  end

  def handle_event("add_to_cart", %{"product-id" => product_id}, socket) do
    product_id = String.to_integer(product_id)

    with {category_name, %{product_prices: prices} = product} <-
           find_product_entry(socket.assigns.categories, product_id),
         %{} = price <- selected_price(product, prices, socket.assigns.card_sizes) do
      if connected?(socket), do: Process.send_after(self(), :clear_added_product, 1_200)

      {:noreply,
       socket
       |> clear_cart_undo()
       |> assign(:variant_editor_key, nil)
       |> assign(:cart, add_line(socket.assigns.cart, product, price, category_name, 1))
       |> assign(:added_product_id, product_id)
       |> assign(:error, nil)
       |> assign(:last_order, nil)
       |> assign(:print_note, nil)
       |> assign(:print_note_error?, false)
       |> clear_place_flash()}
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
    socket =
      case Enum.find(socket.assigns.cart, &(&1.key == key)) do
        %{quantity: 1} -> remove_cart_line(socket, key)
        %{} -> socket |> clear_cart_undo() |> assign(:cart, update_qty(socket.assigns.cart, key, -1))
        nil -> socket
      end

    {:noreply, socket}
  end

  def handle_event("remove", %{"key" => key}, socket) do
    {:noreply, remove_cart_line(socket, key)}
  end

  def handle_event("clear_ticket", _params, %{assigns: %{cart: []}} = socket) do
    {:noreply, socket}
  end

  def handle_event("clear_ticket", _params, socket) do
    draft = ticket_draft(socket.assigns)

    {:noreply,
     socket
     |> reset_ticket()
     |> put_cart_undo(%{kind: :ticket, draft: draft})}
  end

  def handle_event("undo_cart", _params, socket) do
    socket =
      case socket.assigns.cart_undo do
        %{kind: :line, line: line, index: index} ->
          socket
          |> clear_cart_undo()
          |> assign(:cart, List.insert_at(socket.assigns.cart, index, line))

        %{kind: :ticket, draft: draft} ->
          socket
          |> clear_cart_undo()
          |> restore_ticket_draft(draft)

        %{kind: :variant, draft: draft} ->
          socket
          |> clear_cart_undo()
          |> restore_ticket_draft(draft)

        nil ->
          socket
      end

    {:noreply, assign(socket, :variant_editor_key, nil)}
  end

  def handle_event("new_order", _params, socket) do
    {:noreply, reset_ticket(socket)}
  end

  def handle_event("dismiss_place_flash", _params, socket) do
    {:noreply, clear_place_flash(socket)}
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
     |> assign(:cash_tendered, "")
     |> assign(:cash_tender_error, nil)}
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

  def handle_event(
        "set_cash_tendered",
        %{"cash_tendered" => amount},
        %{assigns: %{cash_tender_open?: true}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:cash_tendered, String.trim(amount))
     |> assign(:cash_tender_error, nil)}
  end

  def handle_event("set_cash_tendered", _params, socket), do: {:noreply, socket}

  def handle_event("cash_exact", _params, %{assigns: %{cash_tender_open?: true}} = socket) do
    total = cart_total(socket.assigns.cart) |> Decimal.round(2) |> Decimal.to_string(:normal)

    {:noreply,
     socket
     |> assign(:cash_tendered, total)
     |> assign(:cash_tender_error, nil)}
  end

  def handle_event("cash_exact", _params, socket), do: {:noreply, socket}

  def handle_event(
        "cash_chip",
        %{"amount" => amount},
        %{assigns: %{cash_tender_open?: true}} = socket
      ) do
    case parse_money(amount) do
      {:ok, tendered} ->
        amount = tendered |> Decimal.round(2) |> Decimal.to_string(:normal)

        {:noreply,
         socket
         |> assign(:cash_tendered, amount)
         |> assign(:cash_tender_error, nil)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("cash_chip", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_cash_tender", _params, socket) do
    {:noreply, close_cash_tender(socket)}
  end

  def handle_event("confirm_cash_tender", params, socket) do
    tendered = Map.get(params, "cash_tendered", socket.assigns.cash_tendered)
    token = Map.get(params, "cash_tender_token")
    socket = assign(socket, :cash_tendered, String.trim(to_string(tendered)))

    cond do
      not socket.assigns.cash_tender_open? ->
        {:noreply, socket}

      token != socket.assigns.cash_tender_token ->
        {:noreply, assign(socket, :cash_tender_error, "This cash entry is no longer active.")}

      socket.assigns.payment_choice != :paid or socket.assigns.paid_via != "cash" ->
        {:noreply, assign(socket, :cash_tender_error, "Cash payment is no longer selected.")}

      socket.assigns.placing_order? ->
        {:noreply, socket}

      true ->
        case order_preflight(socket) do
          :ignore ->
            {:noreply, socket}

          {:error, message} ->
            {:noreply, assign(socket, :cash_tender_error, message)}

          :ok ->
            case cash_tender_state(socket.assigns.cash_tendered, cart_total(socket.assigns.cart)) do
              {:exact, _tendered, _change} ->
                socket
                |> consume_cash_tender()
                |> create_pos_order()

              {:change, _tendered, _change} ->
                socket
                |> consume_cash_tender()
                |> create_pos_order()

              {:short, _tendered, needed} ->
                {:noreply,
                 assign(
                   socket,
                   :cash_tender_error,
                   "Cash received is short by #{Menu.format_price(needed)}."
                 )}

              :blank ->
                {:noreply, assign(socket, :cash_tender_error, "Enter the cash received.")}

              :invalid ->
                {:noreply,
                 assign(socket, :cash_tender_error, "Enter a valid cash amount with up to 2 decimal places.")}
            end
        end
    end
  end

  def handle_event(
        "reprint_receipt",
        %{"token" => token},
        %{
          assigns: %{
            last_order: order,
            print_failed?: true,
            print_retry_token: token
          }
        } = socket
      )
      when not is_nil(order) and not is_nil(token) do
    socket = assign(socket, :print_retry_token, nil)
    order = Espreso.Repo.preload(order, :items)
    opts = print_opts(socket, order)

    {note, failed?, note_error?} =
      case Printer.after_paid(order, order.paid_via || "cash", opts) do
        :ok ->
          if Printer.cash_like?(order.paid_via || "cash") do
            {"Receipt printed · kaha opened.", false, false}
          else
            {"Receipt printed.", false, false}
          end

        :disabled ->
          {"Printer is not enabled on this server.", true, false}

        {:error, reason} ->
          {"Print failed (#{inspect(reason)}). Tap Retry.", true, true}
      end

    {:noreply,
     socket
     |> assign(:print_note, note)
     |> assign(:print_failed?, failed?)
     |> assign(:print_retry_token, if(failed?, do: new_print_retry_token()))
     |> assign(:print_note_error?, note_error?)}
  end

  def handle_event("reprint_receipt", _params, socket), do: {:noreply, socket}

  def handle_event("print_kitchen", _params, socket) do
    case socket.assigns.last_order do
      nil ->
        {:noreply, socket}

      order ->
        order = Espreso.Repo.preload(order, :items)

        {note, note_error?} =
          case Printer.print_kitchen(order, staff_name: socket.assigns.current_user.name) do
            :ok -> {"Kitchen ticket printed.", false}
            :disabled -> {"Printer is not enabled on this server.", false}
            {:error, reason} -> {"Kitchen print failed (#{inspect(reason)}).", true}
          end

        {:noreply,
         socket
         |> assign(:print_note, note)
         |> assign(:print_note_error?, note_error?)}
    end
  end

  def handle_event("open_drawer", _params, socket) do
    {note, note_error?} =
      case Printer.open_drawer() do
        :ok -> {"Kaha opened.", false}
        :disabled -> {"Printer is not enabled on this server.", false}
        {:error, reason} -> {"Could not open kaha (#{inspect(reason)}).", true}
      end

    {:noreply,
     socket
     |> assign(:print_note, note)
     |> assign(:print_note_error?, note_error?)}
  end

  def handle_event("place_order", params, socket) do
    socket =
      socket
      |> assign(:customer_name, Map.get(params, "customer_name", socket.assigns.customer_name))
      |> assign(:notes, Map.get(params, "notes", socket.assigns.notes))
      |> assign(:submission_error, nil)

    if socket.assigns.cash_tender_open? do
      {:noreply, socket}
    else
      case order_preflight(socket) do
        :ignore ->
          {:noreply, socket}

        {:error, message} ->
          {:noreply, assign(socket, :submission_error, message)}

        :ok
        when socket.assigns.payment_choice == :paid and socket.assigns.paid_via == "cash" ->
          {:noreply, open_cash_tender(socket)}

        :ok ->
          create_pos_order(socket)
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
              <div
                :if={@place_flash}
                class="staff-pos-place-flash"
                id="pos-place-flash"
                role="status"
                aria-live="polite"
                aria-atomic="true"
              >
                <span>{@place_flash}</span>
                <.link navigate={~p"/orders"} class="staff-pos-place-flash-orders">
                  View Orders
                </.link>
                <button
                  type="button"
                  class="staff-pos-place-flash-dismiss"
                  id="pos-place-flash-dismiss"
                  phx-click="dismiss_place_flash"
                  aria-label="Dismiss"
                >
                  ×
                </button>
              </div>

              <%= if @last_order do %>
                <div
                  class={[
                    "staff-pos-success",
                    @print_failed? && "is-error",
                    !@print_failed? && "is-success"
                  ]}
                  id="pos-confirmation"
                >
                  <div class="staff-pos-success-badge" aria-hidden="true">
                    {if @print_failed?, do: "!", else: "✓"}
                  </div>
                  <p class="staff-pos-success-eyebrow">
                    {if @print_failed?,
                      do: "Print failed · order saved",
                      else: "Print complete · order saved"}
                  </p>
                  <p class="staff-order-number">{@last_order.number}</p>
                  <p class="staff-order-meta">
                    {Orders.status_label(@last_order.status)} · {@last_order.customer_name}
                    · {Orders.payment_label(@last_order)}
                  </p>
                  <p
                    :if={@print_note}
                    class={["staff-pos-success-note", @print_note_error? && "is-error"]}
                    id="pos-print-note"
                  >
                    {@print_note}
                  </p>
                  <div class="staff-pos-success-actions">
                    <button
                      :if={Printer.enabled?() and @print_failed?}
                      type="button"
                      class="staff-pos-place"
                      id="pos-retry-print"
                      phx-click="reprint_receipt"
                      phx-value-token={@print_retry_token}
                      phx-disable-with="Retrying…"
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
                <form
                  class="staff-pos-order-form"
                  id="pos-order-form"
                  phx-submit="place_order"
                >
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
                    <div class="staff-pos-ticket-title-actions">
                      <span :if={cart_item_count(@cart) > 0} class="staff-pos-cart-count">
                        {cart_item_count(@cart)} items
                      </span>
                      <button
                        :if={@cart != []}
                        type="button"
                        class="staff-pos-clear-ticket"
                        id="pos-clear-ticket"
                        phx-click="clear_ticket"
                      >
                        Clear Ticket
                      </button>
                    </div>
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

                <div :if={@cart_undo} class="staff-pos-cart-undo" id="pos-cart-undo" role="status">
                  <span>{cart_undo_label(@cart_undo)}</span>
                  <button type="button" id="pos-cart-undo-action" phx-click="undo_cart">
                    Undo
                  </button>
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
                          <%= if length(cart_variant_options(@categories, line)) > 1 do %>
                            <button
                              type="button"
                              class="staff-pos-cart-variant-trigger"
                              id={"pos-cart-variant-trigger-#{line.key}"}
                              phx-click="toggle_cart_variant"
                              phx-value-key={line.key}
                              aria-expanded={to_string(@variant_editor_key == line.key)}
                              aria-controls={"pos-cart-variant-chooser-#{line.key}"}
                              aria-label={"Change #{line.name} size, currently #{size_label(line.size)}"}
                            >
                              {size_label(line.size)} <span aria-hidden="true">▾</span>
                            </button>
                          <% else %>
                            <p class="staff-pos-cart-size">{size_label(line.size)}</p>
                          <% end %>
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
                        <div
                          :if={@variant_editor_key == line.key}
                          class="staff-pos-cart-variant-chooser"
                          id={"pos-cart-variant-chooser-#{line.key}"}
                          role="group"
                          aria-label={"Choose size for #{line.name}"}
                        >
                          <button
                            :for={price <- cart_variant_options(@categories, line)}
                            type="button"
                            class={[
                              "staff-pos-cart-variant-option",
                              price.id == line.price_id && "is-active"
                            ]}
                            id={"pos-cart-variant-#{line.key}-#{price.id}"}
                            phx-click="change_cart_variant"
                            phx-value-key={line.key}
                            phx-value-price-id={price.id}
                            aria-pressed={to_string(price.id == line.price_id)}
                          >
                            {size_label(price.size)} · {Menu.format_price(price.price)}
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
                      aria-describedby={
                        if @payment_choice == :paid and @paid_via == "gcash",
                          do: "pos-gcash-confirmation-cue",
                          else: nil
                      }
                    >
                      GCash
                    </button>
                  </div>

                  <p
                    :if={@payment_choice == :paid and @paid_via == "gcash"}
                    class="staff-pos-payment-cue"
                    id="pos-gcash-confirmation-cue"
                  >
                    Confirm payment was received before processing.
                  </p>

                  <p
                    :if={@submission_error}
                    class="staff-pos-flash"
                    id="pos-submission-error"
                    role="alert"
                  >
                    {@submission_error}
                  </p>

                  <button
                    type="submit"
                    class={[
                      "staff-pos-place",
                      (@cart == [] or @placing_order?) && "is-disabled"
                    ]}
                    id="pos-place-order"
                    disabled={@cart == [] or @placing_order?}
                  >
                    <%= if @payment_choice == :paid and @paid_via == "gcash" do %>
                      Confirm GCash &amp; Process
                    <% else %>
                      Process Cash Order
                    <% end %>
                  </button>
                </div>
                </form>
              <% end %>
            </aside>
          </div>
        </main>

        <.cash_tender_modal
          :if={@cash_tender_open?}
          cart={@cart}
          cash_tendered={@cash_tendered}
          cash_tender_error={@cash_tender_error}
          cash_tender_token={@cash_tender_token}
          placing_order?={@placing_order?}
        />
      </div>
    </.staff_shell>
    """
  end

  defp cash_tender_modal(assigns) do
    total = cart_total(assigns.cart) |> Decimal.round(2)
    tender_state = cash_tender_state(assigns.cash_tendered, total)

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(:tender_state, tender_state)
      |> assign(:quick_tenders, cash_quick_tenders(total))
      |> assign(:confirm_enabled?, cash_tender_valid?(tender_state))

    ~H"""
    <.modal
      id="cash-tender-modal"
      show={true}
      on_cancel={JS.push("cancel_cash_tender")}
    >
      <div class="staff-pos-cash-modal">
        <header class="staff-pos-cash-modal-head">
          <p class="staff-pos-cash-modal-eyebrow">Cash payment</p>
          <h2 id="cash-tender-modal-title">Cash Received</h2>
          <p id="cash-tender-modal-description">
            Enter the cash handed to staff before creating this order.
          </p>
        </header>

        <div class="staff-pos-cash-total" id="pos-cash-total">
          <span>Total</span>
          <strong>{Menu.format_price(@total)}</strong>
        </div>

        <form
          id="pos-cash-tender-form"
          phx-change="set_cash_tendered"
          phx-submit="confirm_cash_tender"
        >
          <input type="hidden" name="cash_tender_token" value={@cash_tender_token} />

          <label class="staff-pos-cash-field" for="pos-cash-tendered">
            <span>Cash received</span>
            <span class="staff-pos-cash-input-wrap">
              <span aria-hidden="true">₱</span>
              <input
                type="text"
                inputmode="decimal"
                autocomplete="off"
                id="pos-cash-tendered"
                name="cash_tendered"
                value={@cash_tendered}
                placeholder="0.00"
                aria-describedby="pos-cash-tender-feedback"
                aria-invalid={to_string(@tender_state == :invalid or not is_nil(@cash_tender_error))}
              />
            </span>
          </label>

          <div class="staff-pos-cash-quick" id="pos-cash-quick-tenders">
            <button
              type="button"
              id="pos-cash-exact"
              phx-click="cash_exact"
              aria-label="Set cash received to the exact total"
              data-dismiss-keyboard
            >
              Exact
            </button>
            <button
              :for={amount <- @quick_tenders}
              type="button"
              id={"pos-cash-preset-#{Decimal.to_integer(amount)}"}
              phx-click="cash_chip"
              phx-value-amount={Decimal.to_string(amount, :normal)}
              aria-label={"Set cash received to #{Menu.format_price(amount)}"}
              data-dismiss-keyboard
            >
              {Menu.format_price(amount)}
            </button>
          </div>

          <div
            class={[
              "staff-pos-cash-feedback",
              match?({:short, _, _}, @tender_state) && "is-short",
              (@tender_state == :invalid or not is_nil(@cash_tender_error)) && "is-error"
            ]}
            id="pos-cash-tender-feedback"
            aria-live="polite"
          >
            <%= case @tender_state do %>
              <% {:exact, _tendered, change} -> %>
                <span>Exact cash</span>
                <strong>Change {Menu.format_price(change)}</strong>
              <% {:change, _tendered, change} -> %>
                <span>Change</span>
                <strong>{Menu.format_price(change)}</strong>
              <% {:short, _tendered, needed} -> %>
                <span>Still needed</span>
                <strong>{Menu.format_price(needed)}</strong>
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
              type="submit"
              class="staff-pos-place"
              id="pos-confirm-cash"
              disabled={!@confirm_enabled? or @placing_order?}
              phx-disable-with="Processing…"
              data-dismiss-keyboard
            >
              Confirm Payment
            </button>
            <button
              type="button"
              class="staff-pos-place staff-pos-place--secondary"
              id="pos-cancel-cash"
              phx-click={JS.exec("data-cancel", to: "#cash-tender-modal")}
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </.modal>
    """
  end

  defp create_pos_order(socket) do
    case order_preflight(socket) do
      :ignore ->
        {:noreply, socket}

      {:error, message} ->
        {:noreply, assign(socket, :submission_error, message)}

      :ok ->
        customer_name = String.trim(socket.assigns.customer_name)
        paid? = socket.assigns.payment_choice == :paid
        paid_via = if paid?, do: socket.assigns.paid_via, else: nil
        {tendered, change} = cash_amounts(socket)

        lines =
          Enum.map(socket.assigns.cart, fn line ->
            %{
              product_id: line.product_id,
              price_id: line.price_id,
              name: line.name,
              size: line.size,
              quantity: line.quantity,
              price: line.price
            }
          end)

        attrs =
          %{
            customer_name: customer_name,
            notes: blank_notes(socket.assigns.notes),
            fulfillment: socket.assigns.fulfillment,
            table_number: nil,
            payment_method: :counter,
            payment_status: socket.assigns.payment_choice,
            paid_via: paid_via,
            source: :pos
          }
          |> maybe_put_cash_settlement(tendered)
          |> Map.put(:settled_by_user_id, socket.assigns.current_user.id)
          |> Map.put(:settlement_source, :pos)

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

            {note, failed?, note_error?} =
              print_note_result(print_result, order.paid_via || paid_via)

            cash_change = if(change, do: %{tendered: tendered, change: change})

            socket =
              socket
              |> clear_cart_undo()
              |> assign(:cart, [])
              |> assign(:card_sizes, %{})
              |> assign(:added_product_id, nil)
              |> assign(:error, nil)
              |> assign(:submission_error, nil)
              |> assign(:payment_choice, :paid)
              |> assign(:paid_via, "cash")
              |> assign(:customer_name, "Walk-in")
              |> assign(:variant_editor_key, nil)
              |> assign(:cash_tender_open?, false)
              |> assign(:cash_tendered, "")
              |> assign(:cash_tender_error, nil)
              |> assign(:cash_tender_token, nil)
              |> assign(:fulfillment, :pickup)
              |> assign(:table_number, "")
              |> assign(:placing_order?, false)
              |> assign(:notes, "")
              |> assign(:notes_open?, false)
              |> assign(:categories, Menu.list_menu())
              |> assign(:last_cash_change, cash_change)
              |> assign(:print_note, note)
              |> assign(:print_failed?, failed?)
              |> assign(:print_retry_token, if(failed?, do: new_print_retry_token()))
              |> assign(:print_note_error?, note_error?)

            socket =
              if failed? do
                socket
                |> assign(:last_order, order)
                |> clear_place_flash()
              else
                flash = place_flash_message(order, note, cash_change)

                socket
                |> assign(:last_order, nil)
                |> put_place_flash(flash)
              end

            {:noreply, socket}

          {:error, :empty_cart} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:submission_error, "Add at least one item before placing an order.")}

          {:error, {:unavailable, names}} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:submission_error, unavailable_error(names))}

          {:error, {:price_changed, _names}} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:categories, Menu.list_menu())
             |> assign(:submission_error, "Price changed — please review your ticket.")}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:submission_error, "Could not place order. Check items and try again.")}
        end
    end
  end

  defp order_preflight(socket) do
    cond do
      socket.assigns.placing_order? ->
        :ignore

      socket.assigns.cart == [] and
          (not is_nil(socket.assigns.place_flash) or not is_nil(socket.assigns.last_order)) ->
        :ignore

      socket.assigns.cart == [] ->
        {:error, "Add at least one item before placing an order."}

      String.trim(socket.assigns.customer_name) == "" ||
          String.length(String.trim(socket.assigns.customer_name)) < 2 ->
        {:error, "Enter a customer name (at least 2 characters)."}

      true ->
        :ok
    end
  end

  defp open_cash_tender(socket) do
    socket
    |> assign(:cash_tender_open?, true)
    |> assign(:cash_tendered, "")
    |> assign(:cash_tender_error, nil)
    |> assign(:cash_tender_token, Integer.to_string(System.unique_integer([:positive])))
    |> assign(:error, nil)
  end

  defp close_cash_tender(socket) do
    socket
    |> assign(:cash_tender_open?, false)
    |> assign(:cash_tendered, "")
    |> assign(:cash_tender_error, nil)
    |> assign(:cash_tender_token, nil)
  end

  defp consume_cash_tender(socket) do
    socket
    |> assign(:cash_tender_open?, false)
    |> assign(:cash_tender_error, nil)
    |> assign(:cash_tender_token, nil)
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

  defp remove_cart_line(socket, key) do
    case Enum.find_index(socket.assigns.cart, &(&1.key == key)) do
      nil ->
        socket

      index ->
        line = Enum.at(socket.assigns.cart, index)

        socket
        |> assign(:cart, List.delete_at(socket.assigns.cart, index))
        |> assign(:variant_editor_key, nil)
        |> put_cart_undo(%{kind: :line, line: line, index: index})
    end
  end

  defp change_cart_line_variant(socket, source, source_key, price_id) do
    with prices when length(prices) > 1 <-
           cart_variant_options(socket.assigns.categories, source),
         %{} = target_price <- Enum.find(prices, &(&1.id == price_id)),
         {:ok, cart} <- replace_or_merge_cart_variant(socket.assigns.cart, source_key, target_price) do
      draft = ticket_draft(socket.assigns)

      socket
      |> assign(:cart, cart)
      |> assign(
        :card_sizes,
        Map.put(socket.assigns.card_sizes, source.product_id, target_price.id)
      )
      |> assign(:variant_editor_key, nil)
      |> put_cart_undo(%{kind: :variant, draft: draft})
    else
      _ -> socket
    end
  end

  defp replace_or_merge_cart_variant(cart, source_key, target_price) do
    with {:ok, source, source_index} <- uniquely_find_cart_line(cart, source_key) do
      destinations =
        cart
        |> Enum.with_index()
        |> Enum.reject(fn {_line, index} -> index == source_index end)
        |> Enum.filter(fn {line, _index} ->
          line.product_id == source.product_id and line.price_id == target_price.id
        end)

      case destinations do
        [] ->
          replacement = apply_variant_to_line(source, target_price)
          {:ok, List.replace_at(cart, source_index, replacement)}

        [{destination, destination_index}] ->
          merged =
            destination
            |> apply_variant_to_line(target_price)
            |> Map.put(:quantity, destination.quantity + source.quantity)

          {:ok,
           cart
           |> List.replace_at(destination_index, merged)
           |> List.delete_at(source_index)}

        _ ->
          :error
      end
    end
  end

  defp apply_variant_to_line(line, price) do
    %{
      line
      | key: cart_line_key(line.product_id, price.id),
        price_id: price.id,
        size: price.size,
        price: price.price
    }
  end

  defp cart_line_key(product_id, price_id), do: "#{product_id}-#{price_id}"

  defp uniquely_find_cart_line(cart, key) when is_binary(key) do
    case cart |> Enum.with_index() |> Enum.filter(fn {line, _index} -> line.key == key end) do
      [{line, index}] -> {:ok, line, index}
      _ -> :error
    end
  end

  defp uniquely_find_cart_line(_cart, _key), do: :error

  defp cart_variant_options(categories, line) do
    case find_product_entry(categories, line.product_id) do
      {_category_name, %{product_prices: prices}} ->
        ambiguous_signatures =
          prices
          |> Enum.group_by(&variant_display_signature/1)
          |> Enum.filter(fn {_signature, matching} -> length(matching) > 1 end)
          |> Map.new(fn {signature, _matching} -> {signature, true} end)

        safe_prices =
          Enum.reject(prices, &Map.has_key?(ambiguous_signatures, variant_display_signature(&1)))

        if Enum.any?(safe_prices, &(&1.id == line.price_id)), do: safe_prices, else: []

      _ ->
        []
    end
  end

  defp variant_display_signature(price) do
    {size_label(price.size), Decimal.to_string(price.price, :normal)}
  end

  defp parse_positive_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_positive_id(_value), do: :error

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
    |> clear_cart_undo()
    |> clear_place_flash()
    |> assign(:cart, [])
    |> assign(:card_sizes, %{})
    |> assign(:variant_editor_key, nil)
    |> assign(:added_product_id, nil)
    |> assign(:last_order, nil)
    |> assign(:print_note, nil)
    |> assign(:print_failed?, false)
    |> assign(:print_retry_token, nil)
    |> assign(:print_note_error?, false)
    |> assign(:last_cash_change, nil)
    |> assign(:error, nil)
    |> assign(:submission_error, nil)
    |> assign(:payment_choice, :paid)
    |> assign(:paid_via, "cash")
    |> assign(:cash_tender_open?, false)
    |> assign(:cash_tendered, "")
    |> assign(:cash_tender_error, nil)
    |> assign(:cash_tender_token, nil)
    |> assign(:fulfillment, :pickup)
    |> assign(:table_number, "")
    |> assign(:placing_order?, false)
    |> assign(:customer_name, "Walk-in")
    |> assign(:notes, "")
    |> assign(:notes_open?, false)
  end

  defp ticket_draft(assigns) do
    Map.take(assigns, [
      :cart,
      :customer_name,
      :notes,
      :notes_open?,
      :fulfillment,
      :table_number,
      :payment_choice,
      :paid_via,
      :cash_tendered,
      :card_sizes
    ])
  end

  defp restore_ticket_draft(socket, draft) do
    Enum.reduce(draft, socket, fn {key, value}, socket ->
      assign(socket, key, value)
    end)
  end

  defp put_cart_undo(socket, undo) do
    socket = clear_cart_undo(socket)
    token = make_ref()
    timer = Process.send_after(self(), {:expire_cart_undo, token}, @cart_undo_timeout_ms)

    socket
    |> assign(:cart_undo, Map.put(undo, :token, token))
    |> assign(:cart_undo_timer, timer)
  end

  defp clear_cart_undo(socket) do
    if timer = socket.assigns[:cart_undo_timer] do
      Process.cancel_timer(timer)
    end

    socket
    |> assign(:cart_undo, nil)
    |> assign(:cart_undo_timer, nil)
  end

  defp put_place_flash(socket, flash) do
    socket = clear_place_flash(socket)
    token = make_ref()

    timer =
      if connected?(socket) do
        Process.send_after(self(), {:clear_place_flash, token}, 4_000)
      end

    socket
    |> assign(:place_flash, flash)
    |> assign(:place_flash_token, token)
    |> assign(:place_flash_timer, timer)
  end

  defp clear_place_flash(socket) do
    if timer = socket.assigns[:place_flash_timer] do
      Process.cancel_timer(timer)
    end

    socket
    |> assign(:place_flash, nil)
    |> assign(:place_flash_token, nil)
    |> assign(:place_flash_timer, nil)
  end

  defp cart_undo_label(%{kind: :ticket}), do: "Ticket cleared"
  defp cart_undo_label(%{kind: :variant}), do: "Size changed"
  defp cart_undo_label(_undo), do: "Item removed"

  defp place_flash_message(order, print_note, cash_change) do
    base =
      "#{order.number} · #{order.customer_name} · #{Orders.status_label(order.status)} · #{Orders.payment_label(order)}"

    extras =
      [
        print_note,
        if(cash_change,
          do: "Cash received #{Menu.format_price(cash_change.tendered)}",
          else: nil
        ),
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

  defp cash_short?(socket) do
    match?(
      {:short, _tendered, _needed},
      cash_tender_state(socket.assigns.cash_tendered, cart_total(socket.assigns.cart))
    )
  end

  defp cash_amounts(socket) do
    if socket.assigns.payment_choice == :paid and socket.assigns.paid_via == "cash" and
         not cash_short?(socket) do
      case cash_tender_state(socket.assigns.cash_tendered, cart_total(socket.assigns.cart)) do
        {:exact, tendered, change} -> {tendered, change}
        {:change, tendered, change} -> {tendered, change}
        _ -> {nil, nil}
      end
    else
      {nil, nil}
    end
  end

  defp cash_quick_tenders(total) do
    ["100", "200", "500", "1000"]
    |> Enum.map(&Decimal.new/1)
    |> Enum.filter(&(Decimal.compare(&1, total) in [:eq, :gt]))
  end

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

  defp new_print_retry_token do
    Integer.to_string(System.unique_integer([:positive]))
  end

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

    {note, false, false}
  end

  defp print_note_result(:disabled, _), do: {"Printing disabled", false, false}

  defp print_note_result({:error, reason}, _) do
    {"Order saved · print failed (#{inspect(reason)}). Tap Retry.", true, true}
  end

  defp print_note_result(_, _), do: {nil, false, false}

  defp maybe_put_cash_settlement(attrs, %Decimal{} = tendered),
    do: Map.put(attrs, :cash_tendered, tendered)

  defp maybe_put_cash_settlement(attrs, _), do: attrs

  defp order_note(%{notes: notes}) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: nil, else: trimmed
  end

  defp order_note(_), do: nil
end

defmodule EspresoWeb.MenuLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot
  alias Espreso.Menu
  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    categories = Menu.list_menu()
    selected = categories |> List.first() |> then(&(&1 && &1.name))

    {:ok,
     socket
     |> assign(:page_title, "Menu")
     |> assign(:categories, categories)
     |> assign(:selected_category, selected)
     |> assign(:search, "")
     |> assign(:cart, [])
     |> assign(:basket_open?, false)
     |> assign(:basket_closing?, false)
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)
     |> assign(:toast, nil)
     |> assign(:basket_pulse?, false)
     |> assign(:fulfillment, :dine_in)
     |> assign(:table_number, "")
     |> assign(:customer_name, "")
     |> assign(:notes, "")
     |> assign(:checkout_errors, %{})
     |> assign(:payment_method, :counter)
     |> assign(:placing_order?, false), layout: false}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_table_param(socket, params)}
  end

  @impl true
  def handle_info(:clear_detail, socket) do
    {:noreply,
     socket
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)}
  end

  def handle_info(:clear_basket, socket) do
    {:noreply,
     socket
     |> assign(:basket_open?, false)
     |> assign(:basket_closing?, false)}
  end

  def handle_info(:clear_toast, socket) do
    {:noreply,
     socket
     |> assign(:toast, nil)
     |> assign(:basket_pulse?, false)}
  end

  @impl true
  def handle_event("select_category", %{"name" => name}, socket) do
    if Enum.any?(socket.assigns.categories, &(&1.name == name)) do
        {:noreply,
         socket
         |> assign(:selected_category, name)
         |> assign(:search, "")
         |> assign(:detail, nil)
         |> assign(:detail_closing?, false)
         |> push_event("scroll_to_category", %{name: name})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search", %{"search" => query}, socket) do
    {:noreply, assign(socket, :search, query)}
  end

  def handle_event("open_detail", %{"id" => id}, socket) do
    case find_product_with_category(socket.assigns.categories, id) do
      nil ->
        {:noreply, socket}

      {category, product} ->
        price = List.first(product.product_prices)

        detail = %{
          product: product,
          category_name: category.name,
          selected_price_id: price && price.id,
          quantity: 1
        }

        {:noreply,
         socket
         |> assign(:selected_category, category.name)
         |> assign(:detail, detail)
         |> assign(:detail_closing?, false)
         |> assign(:basket_open?, false)
         |> assign(:basket_closing?, false)}
    end
  end

  def handle_event("close_detail", _params, socket) do
    cond do
      is_nil(socket.assigns.detail) ->
        {:noreply, socket}

      socket.assigns.detail_closing? ->
        {:noreply, socket}

      true ->
        Process.send_after(self(), :clear_detail, 280)
        {:noreply, assign(socket, :detail_closing?, true)}
    end
  end

  def handle_event("select_size", %{"price-id" => price_id}, socket) do
    detail = socket.assigns.detail

    if detail && !socket.assigns.detail_closing? do
      {:noreply, assign(socket, :detail, %{detail | selected_price_id: String.to_integer(price_id)})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("detail_qty", %{"delta" => delta}, socket) do
    detail = socket.assigns.detail

    if detail && !socket.assigns.detail_closing? do
      next = max(1, detail.quantity + String.to_integer(delta))
      {:noreply, assign(socket, :detail, %{detail | quantity: next})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("buy_now", _params, socket) do
    detail = socket.assigns.detail

    if detail && !socket.assigns.detail_closing? do
      with %{product: product, category_name: category_name, selected_price_id: price_id, quantity: qty} <- detail,
           %{} = price <- Enum.find(product.product_prices, &(&1.id == price_id)) do
        cart =
          add_line(
            socket.assigns.cart,
            product,
            price,
            qty,
            Menu.product_image(category_name, product.name)
          )
        Process.send_after(self(), :clear_toast, 2000)

        {:noreply,
         socket
         |> assign(:cart, cart)
         |> assign(:detail, nil)
         |> assign(:detail_closing?, false)
         |> assign(:toast, "Added to basket")
         |> assign(:basket_pulse?, true)}
      else
        _ -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_basket", _params, socket) do
    {:noreply,
     socket
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)
     |> assign(:basket_open?, true)
     |> assign(:basket_closing?, false)
     |> assign(:checkout_errors, %{})}
  end

  def handle_event("set_fulfillment", %{"type" => type}, socket) do
    fulfillment =
      case type do
        "pickup" -> :pickup
        _ -> :dine_in
      end

    socket =
      socket
      |> assign(:fulfillment, fulfillment)
      |> assign(:checkout_errors, Map.delete(socket.assigns.checkout_errors, :table_number))

    socket =
      if fulfillment == :pickup do
        assign(socket, :table_number, "")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("update_checkout", params, socket) do
    name = Map.get(params, "customer_name", socket.assigns.customer_name)
    table = Map.get(params, "table_number", socket.assigns.table_number)
    notes = Map.get(params, "notes", socket.assigns.notes)

    {:noreply,
     socket
     |> assign(:customer_name, name)
     |> assign(:table_number, table)
     |> assign(:notes, notes)
     |> assign(:checkout_errors, %{})}
  end

  def handle_event("validate_checkout", _params, socket) do
    {:noreply, assign(socket, :checkout_errors, checkout_errors(socket.assigns))}
  end

  def handle_event("set_payment_method", %{"method" => method}, socket) do
    payment_method =
      case method do
        "online" -> :online
        _ -> :counter
      end

    {:noreply, assign(socket, :payment_method, payment_method)}
  end

  def handle_event("place_order", _params, socket) do
    errors = checkout_errors(socket.assigns)

    cond do
      socket.assigns.cart == [] ->
        {:noreply, socket}

      socket.assigns.placing_order? ->
        {:noreply, socket}

      errors != %{} ->
        {:noreply, assign(socket, :checkout_errors, errors)}

      socket.assigns.payment_method == :online ->
        {:noreply,
         socket
         |> assign(:checkout_errors, %{})
         |> assign(:toast, "Online payment coming soon — use Pay at counter")
         |> then(fn s ->
           Process.send_after(self(), :clear_toast, 2800)
           s
         end)}

      true ->
        socket = assign(socket, :placing_order?, true)

        attrs = %{
          customer_name: socket.assigns.customer_name,
          fulfillment: socket.assigns.fulfillment,
          table_number: socket.assigns.table_number,
          notes: socket.assigns.notes,
          payment_method: :counter
        }

        case Orders.create_order(socket.assigns.cart, attrs) do
          {:ok, order} ->
            {:noreply,
             socket
             |> assign(:cart, [])
             |> assign(:basket_open?, false)
             |> assign(:basket_closing?, false)
             |> assign(:placing_order?, false)
             |> assign(:checkout_errors, %{})
             |> push_navigate(to: ~p"/order/#{order.number}")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:checkout_errors, checkout_errors_from_changeset(changeset))}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:toast, "Could not place order — try again")
             |> then(fn s ->
               Process.send_after(self(), :clear_toast, 2400)
               s
             end)}
        end
    end
  end

  def handle_event("close_basket", _params, socket) do
    cond do
      not socket.assigns.basket_open? ->
        {:noreply, socket}

      socket.assigns.basket_closing? ->
        {:noreply, socket}

      true ->
        Process.send_after(self(), :clear_basket, 280)
        {:noreply, assign(socket, :basket_closing?, true)}
    end
  end

  def handle_event("cart_qty", %{"key" => key, "delta" => delta}, socket) do
    delta = String.to_integer(delta)

    cart =
      socket.assigns.cart
      |> Enum.map(fn line ->
        if line.key == key do
          %{line | quantity: max(1, line.quantity + delta)}
        else
          line
        end
      end)

    {:noreply, assign(socket, :cart, cart)}
  end

  def handle_event("cart_remove", %{"key" => key}, socket) do
    cart = Enum.reject(socket.assigns.cart, &(&1.key == key))
    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="menu-page"
      phx-hook="MenuBrowse"
      class={["menu-live-root", (@detail || @basket_open?) && "menu-page-locked"]}
    >
      <div class="menu-page menu-page-brune site-page">
      <.brune_header
        current="menu"
        show_basket?={true}
        basket_count={cart_count(@cart)}
        basket_pulse?={@basket_pulse?}
      />

      <%!-- Menu header with cups illustration --%>
      <section class="brune-menu-hero" aria-labelledby="brune-menu-title">
        <div class="brune-menu-hero-copy">
          <h1 id="brune-menu-title" class="brune-menu-hero-title">Our Menu</h1>
          <p class="brune-menu-hero-lede">
            We have drink for every taste and a place for every occasion.
          </p>
        </div>
        <div class="brune-menu-hero-art" aria-hidden="true">
          <.brune_cups />
        </div>
      </section>

      <section class="brune-menu-shell" id="menu">
        <%!-- Search --%>
        <div id="menu-search" class="brune-menu-search">
          <form phx-change="search" phx-submit="search">
            <div class="brune-search-wrap">
              <span class="brune-search-icon" aria-hidden="true">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <circle cx="11" cy="11" r="8" /><path d="m21 21-4.3-4.3" />
                </svg>
              </span>
              <input
                id="menu-search-input"
                type="text"
                name="search"
                value={@search}
                placeholder="Search menu..."
                class="brune-search-input"
                autocomplete="off"
                phx-debounce="200"
              />
            </div>
          </form>
        </div>

        <nav class="brune-menu-tabs-line" aria-label="Menu categories">
          <button
            :for={category <- @categories}
            type="button"
            phx-click="select_category"
            phx-value-name={category.name}
            class={[
              "brune-menu-tab-link",
              @selected_category == category.name && "brune-menu-tab-link-active"
            ]}
            aria-pressed={to_string(@selected_category == category.name)}
          >
            {category_nav_label(category.name)}
          </button>
        </nav>

        <.brune_student_promo />

        <div class="brune-menu-body" id="menu-items">
          <section
            :for={category <- visible_categories(@categories, @selected_category, @search)}
            class={"brune-menu-section brune-menu-section--#{section_tone(category.name)}"}
            id={"category-#{category.name}"}
            data-category={category.name}
          >
            <h2 class="brune-menu-category-title">{category_nav_label(category.name)}</h2>
            <div :for={group <- category.groups} class="brune-menu-group">
              <p :if={group.name} class="brune-menu-subgroup">{group.name}</p>

              <ul class="brune-menu-items">
                <li :for={product <- group.products} class="brune-menu-item">
                  <article class="brune-menu-item-card">
                    <div class="brune-menu-item-thumb">
                      <img
                        src={Menu.product_image(category.name, product.name)}
                        alt={product.name}
                        class="brune-menu-item-photo"
                        loading="lazy"
                      />
                    </div>
                    <div class="brune-menu-item-body">
                      <div class="brune-menu-item-top">
                        <h3 class="brune-menu-item-name">{product.name}</h3>
                        <p class="brune-menu-item-price">{card_price_label(product)}</p>
                      </div>
                      <p class="brune-menu-item-blurb">{product_blurb(product, category.name)}</p>
                      <button
                        type="button"
                        class="brune-order-link"
                        phx-click="open_detail"
                        phx-value-id={product.id}
                        aria-label={"Order #{product.name}"}
                      >
                        Order <span aria-hidden="true">›</span>
                      </button>
                    </div>
                  </article>
                </li>
              </ul>
            </div>
          </section>
        </div>
      </section>

      <%!-- Instagram --%>
      <section class="site-instagram site-instagram-menu" aria-labelledby="menu-instagram-title">
        <header class="site-instagram-head">
          <h2 id="menu-instagram-title" class="site-instagram-title">
            <a href={CoffeeSpot.instagram_url()} target="_blank" rel="noopener noreferrer">
              Check us out on Instagram
            </a>
          </h2>
        </header>
        <ul class="site-instagram-grid">
          <li :for={src <- instagram_images()} class="site-instagram-cell">
            <a href={CoffeeSpot.instagram_url()} target="_blank" rel="noopener noreferrer" tabindex="-1" aria-hidden="true">
              <img src={src} alt="" loading="lazy" />
            </a>
          </li>
        </ul>
      </section>

      <footer class="brune-mega-footer" aria-label="CoffeeSpot footer">
        <p class="brune-mega-brand">Elilai</p>

        <div class="brune-mega-grid">
          <div class="brune-mega-block">
            <p class="brune-mega-label">Hours</p>
            <p :for={line <- CoffeeSpot.hours_lines()} class="brune-mega-text">{line}</p>
          </div>

          <div class="brune-mega-block">
            <p class="brune-mega-label">Contact</p>
            <a href={CoffeeSpot.email_url()} class="brune-mega-link">{CoffeeSpot.email()}</a>
            <a href={"tel:#{CoffeeSpot.phone_tel()}"} class="brune-mega-link">
              {CoffeeSpot.phone_display()}
            </a>
          </div>

          <div class="brune-mega-block">
            <p class="brune-mega-label">Location</p>
            <a
              href={CoffeeSpot.map_link_url()}
              target="_blank"
              rel="noopener noreferrer"
              class="brune-mega-link"
            >
              {CoffeeSpot.address_short()}
            </a>
          </div>
        </div>

      </footer>
      </div>

      <div
        :if={@detail}
        class={["menu-buy-layer", @detail_closing? && "is-closing"]}
        id="menu-detail"
        phx-window-keydown="close_detail"
        phx-key="Escape"
      >
        <button type="button" class="menu-buy-backdrop" phx-click="close_detail" aria-label="Close">
        </button>

        <div
          id="menu-buy-modal"
          class="menu-buy-modal"
          role="dialog"
          aria-modal="true"
          aria-labelledby="menu-detail-title"
          phx-hook="MenuSheet"
          data-close-event="close_detail"
        >
          <div class="menu-buy-handle" data-drag-handle>
            <span class="menu-buy-handle-bar" aria-hidden="true"></span>
            <span class="menu-buy-handle-label">Swipe down to close</span>
          </div>

          <div class={"menu-buy-visual menu-detail-visual--#{section_tone(@detail.category_name)}"}>
            <img
              src={Menu.product_image(@detail.category_name, @detail.product.name)}
              alt={@detail.product.name}
              class="menu-buy-photo"
            />
          </div>

          <div class="menu-buy-body">
            <div class="menu-buy-title-row">
              <h2 id="menu-detail-title" class="menu-detail-name">{@detail.product.name}</h2>
              <p class="menu-detail-price">
                {Menu.format_price(selected_price(@detail).price)}
              </p>
            </div>

            <div class="menu-detail-sizes">
              <p class="menu-detail-label">Size</p>
              <div class="menu-size-pills" role="group" aria-label="Size">
                <button
                  :for={price <- @detail.product.product_prices}
                  type="button"
                  class={[
                    "menu-size-pill",
                    @detail.selected_price_id == price.id && "menu-size-pill-active"
                  ]}
                  phx-click="select_size"
                  phx-value-price-id={price.id}
                >
                  {size_label(price) || "Regular"}
                </button>
              </div>
            </div>

            <div class="menu-buy-about">
              <p class="menu-detail-label">About</p>
              <p
                :if={description?(@detail.product.description)}
                class="menu-detail-description"
              >
                {@detail.product.description}
              </p>
              <p :if={!description?(@detail.product.description)} class="menu-detail-description">
                Prepared fresh at CoffeeSpot Lilac Marikina.
              </p>
            </div>

            <div class="menu-detail-qty-row">
              <p class="menu-detail-label">Quantity</p>
              <div class="menu-qty">
                <button
                  type="button"
                  phx-click="detail_qty"
                  phx-value-delta="-1"
                  aria-label="Decrease"
                  disabled={@detail.quantity <= 1}
                >
                  −
                </button>
                <span>{@detail.quantity}</span>
                <button type="button" phx-click="detail_qty" phx-value-delta="1" aria-label="Increase">
                  +
                </button>
              </div>
            </div>
          </div>

          <footer class="menu-buy-bar">
            <button
              type="button"
              class="menu-buy-basket"
              phx-click="open_basket"
              aria-label={"Checkout, #{cart_count(@cart)} items"}
            >
              <span aria-hidden="true">▣</span>
              <span class="menu-buy-basket-count">{cart_count(@cart)}</span>
            </button>
            <button type="button" class="menu-buy-now" phx-click="buy_now">
              Add to basket
            </button>
          </footer>
        </div>
      </div>

      <div
        :if={@toast}
        class="menu-toast"
        role="status"
        aria-live="polite"
      >
        {@toast}
        <button type="button" class="menu-toast-action" phx-click="open_basket">
          View
        </button>
      </div>

      <div
        :if={@basket_open?}
        class={["menu-basket-layer", @basket_closing? && "is-closing"]}
        id="menu-basket"
        phx-window-keydown="close_basket"
        phx-key="Escape"
      >
        <button type="button" class="menu-basket-backdrop" phx-click="close_basket" aria-label="Close basket">
        </button>
        <aside
          id="menu-basket-panel"
          class="menu-basket-panel"
          role="dialog"
          aria-modal="true"
          aria-labelledby="menu-basket-title"
          phx-hook="MenuSheet"
          data-close-event="close_basket"
        >
          <div class="menu-basket-handle" data-drag-handle>
            <span class="menu-basket-handle-bar" aria-hidden="true"></span>
          </div>

          <header class="menu-basket-header">
            <div class="menu-basket-heading">
              <p class="menu-basket-eyebrow">CoffeeSpot</p>
              <h2 id="menu-basket-title">Your order</h2>
              <p class="menu-basket-count-label">
                {cart_count(@cart)} {if cart_count(@cart) == 1, do: "item", else: "items"}
              </p>
            </div>
            <button type="button" class="menu-basket-close" phx-click="close_basket" aria-label="Close">
              ✕
            </button>
          </header>

          <div :if={@cart == []} class="menu-basket-empty">
            <p class="menu-basket-empty-title">Nothing here yet</p>
            <p>Choose something from the menu, then add it to your basket.</p>
            <button type="button" class="menu-basket-empty-cta" phx-click="close_basket">
              Back to menu
            </button>
          </div>

          <ul :if={@cart != []} class="menu-basket-list">
            <li :for={line <- @cart} class="menu-basket-line">
              <div class="menu-basket-line-visual">
                <img
                  src={line.image}
                  alt=""
                  class="menu-basket-line-photo"
                />
              </div>
              <div class="menu-basket-line-main">
                <div class="menu-basket-line-top">
                  <div class="menu-basket-line-copy">
                    <p class="menu-basket-line-name">{line.name}</p>
                    <p :if={line.size} class="menu-basket-line-size">{line.size}</p>
                  </div>
                  <p class="menu-basket-line-price">
                    {Menu.format_price(Decimal.mult(line.price, line.quantity))}
                  </p>
                </div>
                <div class="menu-basket-line-actions">
                  <div class="menu-qty menu-qty-compact">
                    <button
                      type="button"
                      phx-click="cart_qty"
                      phx-value-key={line.key}
                      phx-value-delta="-1"
                      aria-label="Decrease"
                      disabled={line.quantity <= 1}
                    >
                      −
                    </button>
                    <span>{line.quantity}</span>
                    <button
                      type="button"
                      phx-click="cart_qty"
                      phx-value-key={line.key}
                      phx-value-delta="1"
                      aria-label="Increase"
                    >
                      +
                    </button>
                  </div>
                  <button
                    type="button"
                    class="menu-basket-remove"
                    phx-click="cart_remove"
                    phx-value-key={line.key}
                  >
                    Remove
                  </button>
                </div>
              </div>
            </li>
          </ul>

          <footer :if={@cart != []} class="menu-basket-footer">
            <form id="menu-checkout-form" class="menu-checkout" phx-change="update_checkout" phx-submit="validate_checkout">
              <fieldset class="menu-checkout-fulfillment">
                <legend class="menu-checkout-label">How will you get it?</legend>
                <div class="menu-checkout-options" role="radiogroup" aria-label="Fulfillment">
                  <button
                    type="button"
                    class={["menu-checkout-option", @fulfillment == :dine_in && "is-active"]}
                    phx-click="set_fulfillment"
                    phx-value-type="dine_in"
                    aria-pressed={to_string(@fulfillment == :dine_in)}
                  >
                    Dine-in
                  </button>
                  <button
                    type="button"
                    class={["menu-checkout-option", @fulfillment == :pickup && "is-active"]}
                    phx-click="set_fulfillment"
                    phx-value-type="pickup"
                    aria-pressed={to_string(@fulfillment == :pickup)}
                  >
                    Pickup at counter
                  </button>
                </div>
              </fieldset>

              <div :if={@fulfillment == :dine_in} class="menu-checkout-field">
                <label class="menu-checkout-label" for="checkout-table">Table number</label>
                <input
                  id="checkout-table"
                  type="number"
                  name="table_number"
                  inputmode="numeric"
                  min="1"
                  max="99"
                  value={@table_number}
                  placeholder="e.g. 7"
                  class={["menu-checkout-input", @checkout_errors[:table_number] && "is-error"]}
                  phx-debounce="200"
                />
                <p :if={@checkout_errors[:table_number]} class="menu-checkout-error">
                  {@checkout_errors[:table_number]}
                </p>
              </div>

              <div class="menu-checkout-field">
                <label class="menu-checkout-label" for="checkout-name">Your name</label>
                <input
                  id="checkout-name"
                  type="text"
                  name="customer_name"
                  value={@customer_name}
                  placeholder="Name for your order"
                  autocomplete="name"
                  maxlength="60"
                  class={["menu-checkout-input", @checkout_errors[:customer_name] && "is-error"]}
                  phx-debounce="200"
                />
                <p :if={@checkout_errors[:customer_name]} class="menu-checkout-error">
                  {@checkout_errors[:customer_name]}
                </p>
              </div>

              <div class="menu-checkout-field">
                <label class="menu-checkout-label" for="checkout-notes">Notes <span class="menu-checkout-optional">(optional)</span></label>
                <textarea
                  id="checkout-notes"
                  name="notes"
                  rows="2"
                  maxlength="200"
                  placeholder="less ice, oat milk, no sugar…"
                  class="menu-checkout-input menu-checkout-textarea"
                  phx-debounce="200"
                >{Phoenix.HTML.Form.normalize_value("textarea", @notes)}</textarea>
              </div>
            </form>

            <div class="menu-basket-total">
              <span>Total</span>
              <strong>{Menu.format_price(cart_total(@cart))}</strong>
            </div>

            <fieldset class="menu-checkout-fulfillment menu-checkout-payment">
              <legend class="menu-checkout-label">Payment</legend>
              <div class="menu-checkout-options" role="radiogroup" aria-label="Payment">
                <button
                  type="button"
                  class={["menu-checkout-option", @payment_method == :counter && "is-active"]}
                  phx-click="set_payment_method"
                  phx-value-method="counter"
                  aria-pressed={to_string(@payment_method == :counter)}
                >
                  Pay at counter
                </button>
                <button
                  type="button"
                  class={["menu-checkout-option", @payment_method == :online && "is-active"]}
                  phx-click="set_payment_method"
                  phx-value-method="online"
                  aria-pressed={to_string(@payment_method == :online)}
                >
                  Pay online
                </button>
              </div>
              <p class="menu-basket-note menu-checkout-payment-note">
                Online payment (GCash / cards) comes next — Pay at counter works now.
              </p>
            </fieldset>

            <%= if checkout_valid?(@fulfillment, @customer_name, @table_number) do %>
              <button
                type="button"
                class="menu-basket-checkout"
                phx-click="place_order"
                disabled={@placing_order?}
              >
                {if @placing_order?, do: "Placing order…", else: place_order_label(@payment_method)}
              </button>
              <a
                href={CoffeeSpot.order_whatsapp_url(@cart, checkout_payload(assigns))}
                class="menu-basket-whatsapp"
                target="_blank"
                rel="noopener noreferrer"
              >
                Or send on WhatsApp
              </a>
            <% else %>
              <button type="button" class="menu-basket-checkout" phx-click="validate_checkout">
                Place order
              </button>
            <% end %>

            <p class="menu-basket-note">You’ll get an order number to show at the counter.</p>
          </footer>
        </aside>
      </div>
    </div>
    """
  end

  defp visible_categories(categories, selected_category, search) do
    query = String.trim(search) |> String.downcase()

    if query == "" do
      Enum.filter(categories, &(&1.name == selected_category))
    else
      categories
      |> Enum.map(fn category ->
        filtered_groups =
          Enum.map(category.groups, fn group ->
            filtered = Enum.filter(group.products, fn product ->
              String.downcase(product.name) |> String.contains?(query)
            end)
            %{group | products: filtered}
          end)
          |> Enum.reject(fn group -> group.products == [] end)

        %{category | groups: filtered_groups}
      end)
      |> Enum.reject(fn category -> category.groups == [] end)
    end
  end

  defp find_product_with_category(categories, id) when is_binary(id) do
    find_product_with_category(categories, String.to_integer(id))
  end

  defp find_product_with_category(categories, id) when is_integer(id) do
    categories
    |> Enum.find_value(fn category ->
      case Enum.find(category.products, &(&1.id == id)) do
        nil -> nil
        product -> {category, product}
      end
    end)
  end

  defp add_line(cart, product, price, quantity, image) do
    key = line_key(product.id, price)
    size = size_label(price)

    case Enum.find_index(cart, &(&1.key == key)) do
      nil ->
        cart ++
          [
            %{
              key: key,
              product_id: product.id,
              name: product.name,
              size: size,
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

  defp line_key(product_id, %{id: price_id}), do: "#{product_id}:#{price_id}"

  defp cart_count(cart), do: Enum.reduce(cart, 0, fn line, acc -> acc + line.quantity end)

  defp cart_total(cart) do
    Enum.reduce(cart, Decimal.new(0), fn line, acc ->
      Decimal.add(acc, Decimal.mult(line.price, line.quantity))
    end)
  end

  defp selected_price(%{product: product, selected_price_id: price_id}) do
    Enum.find(product.product_prices, &(&1.id == price_id)) || List.first(product.product_prices)
  end

  defp card_price_label(product) do
    case product.product_prices do
      [price] ->
        Menu.format_price(price.price)

      [_ | _] = prices ->
        lowest =
          prices
          |> Enum.map(& &1.price)
          |> Enum.min(Decimal)

        "from #{Menu.format_price(lowest)}"

      _ ->
        ""
    end
  end

  defp size_label(%{size: size}) when is_binary(size) and size != "", do: size
  defp size_label(_price), do: nil

  defp section_tone("HOT"), do: "hot"
  defp section_tone("COLD"), do: "cold"
  defp section_tone("FRAPPE"), do: "frappe"
  defp section_tone("SODA"), do: "soda"
  defp section_tone("FOOD"), do: "food"
  defp section_tone(_name), do: "default"

  defp category_nav_label("HOT"), do: "Hot"
  defp category_nav_label("COLD"), do: "Cold"
  defp category_nav_label("FRAPPE"), do: "Frappe"
  defp category_nav_label("SODA"), do: "Soda"
  defp category_nav_label("FOOD"), do: "Food"
  defp category_nav_label(name), do: name

  defp category_blurb("HOT"), do: "Freshly pulled and served warm."
  defp category_blurb("COLD"), do: "Iced and ready for a slow Lilac afternoon."
  defp category_blurb("FRAPPE"), do: "Blended, topped, and built to share."
  defp category_blurb("SODA"), do: "Bright, fizzy, and easy to sip."
  defp category_blurb("FOOD"), do: "From the kitchen at CoffeeSpot Lilac."
  defp category_blurb(_name), do: "Prepared fresh at CoffeeSpot Lilac Marikina."

  defp description?(description) when is_binary(description) do
    String.trim(description) != ""
  end

  defp description?(_description), do: false

  defp product_blurb(product, category_name) do
    if description?(product.description) do
      product.description
    else
      category_blurb(category_name)
    end
  end

  defp apply_table_param(socket, %{"table" => table}) do
    case Integer.parse(to_string(table)) do
      {n, ""} when n in 1..99 ->
        socket
        |> assign(:fulfillment, :dine_in)
        |> assign(:table_number, Integer.to_string(n))

      _ ->
        socket
    end
  end

  defp apply_table_param(socket, _params), do: socket

  defp checkout_payload(assigns) do
    %{
      customer_name: assigns.customer_name,
      fulfillment: assigns.fulfillment,
      table_number: assigns.table_number,
      notes: assigns.notes
    }
  end

  defp checkout_valid?(fulfillment, customer_name, table_number) do
    checkout_errors(%{
      fulfillment: fulfillment,
      customer_name: customer_name,
      table_number: table_number
    }) == %{}
  end

  defp checkout_errors(assigns) do
    errors = %{}

    name = assigns.customer_name |> to_string() |> String.trim()

    errors =
      if String.length(name) >= 2 do
        errors
      else
        Map.put(errors, :customer_name, "Please enter your name")
      end

    case assigns.fulfillment do
      :dine_in ->
        case Integer.parse(String.trim(to_string(assigns.table_number))) do
          {n, ""} when n in 1..99 ->
            errors

          _ ->
            Map.put(errors, :table_number, "Enter your table number (1–99)")
        end

      _ ->
        errors
    end
  end

  defp checkout_errors_from_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.reduce(%{}, fn {field, messages}, acc ->
      Map.put(acc, field, List.first(messages))
    end)
  end

  defp place_order_label(:online), do: "Pay online"
  defp place_order_label(_), do: "Place order · Pay at counter"

  defp instagram_images do
    [
      "/images/coffeespot/IMG_3478.JPG",
      "/images/coffeespot/IMG_3482.JPG",
      "/images/coffeespot/IMG_3468.JPG",
      "/images/coffeespot/IMG_3475.JPG",
      "/images/coffeespot/IMG_3488.JPG"
    ]
  end
end

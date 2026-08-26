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
     |> assign(:menu_stage, :landing)
     |> assign(:menu_filter, nil)
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
  def handle_event("enter_craving", _params, socket) do
    {:noreply, assign(socket, :menu_stage, :craving)}
  end

  def handle_event("enter_visit", _params, socket) do
    {:noreply, assign(socket, :menu_stage, :visit)}
  end

  def handle_event("back_to_landing", _params, socket) do
    {:noreply,
     socket
     |> assign(:menu_stage, :landing)
     |> assign(:menu_filter, nil)
     |> assign(:search, "")
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)
     |> assign(:basket_open?, false)
     |> assign(:basket_closing?, false)}
  end

  def handle_event("back_to_craving", _params, socket) do
    {:noreply,
     socket
     |> assign(:menu_stage, :craving)
     |> assign(:menu_filter, nil)
     |> assign(:search, "")
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)
     |> assign(:basket_open?, false)
     |> assign(:basket_closing?, false)}
  end

  def handle_event("select_craving", %{"id" => id}, socket) do
    case Enum.find(craving_options(), &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      option ->
        {:noreply, apply_craving_option(socket, option)}
    end
  end

  def handle_event("select_category", %{"name" => name}, socket) do
    if Enum.any?(socket.assigns.categories, &(&1.name == name)) do
      {:noreply,
       socket
       |> assign(:selected_category, name)
       |> assign(:menu_filter, nil)
       |> assign(:search, "")
       |> assign(:detail, nil)
       |> assign(:detail_closing?, false)
       |> push_event("scroll_to_category", %{name: name})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search", %{"search" => query}, socket) do
    # Keep Matcha/Sweets filter context; search narrows within the active view.
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
      {:noreply,
       assign(socket, :detail, %{detail | selected_price_id: String.to_integer(price_id)})}
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
      with %{
             product: product,
             category_name: category_name,
             selected_price_id: price_id,
             quantity: qty
           } <- detail,
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
         |> assign(:toast, "Added to bag")
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

          {:error, {:unavailable, names}} ->
            {:noreply,
             socket
             |> assign(:placing_order?, false)
             |> assign(:checkout_errors, %{})
             |> assign(:toast, unavailable_toast(names))
             |> then(fn s ->
               Process.send_after(self(), :clear_toast, 3200)
               s
             end)}

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
      class={[
        "menu-live-root",
        @menu_stage != :menu && "menu-live-root--qr-entry",
        (@detail || @basket_open?) && "menu-page-locked"
      ]}
    >
      <div :if={@menu_stage == :landing} id="menu-landing" class="menu-qr-landing">
        <div class="menu-qr-landing-scene">
          <div class="menu-qr-landing-media" aria-hidden="true">
            <img
              src="/images/coffeespot/cold-signature-01.jpg"
              alt=""
              class="menu-qr-landing-photo"
              width="800"
              height="1000"
            />
          </div>

          <div class="menu-qr-landing-scrim" aria-hidden="true"></div>

          <div class="menu-qr-landing-content">
            <p class="menu-qr-landing-brand">CoffeeSpot</p>
            <h1 class="menu-qr-landing-headline">Order from your table.</h1>
            <p class="menu-qr-landing-lede">Browse, pay at the counter, we prepare it.</p>

            <div class="menu-qr-landing-actions">
              <button
                type="button"
                id="menu-cta-view-menu"
                class="menu-qr-landing-cta menu-qr-landing-cta--primary"
                phx-click="enter_craving"
              >
                View the menu
              </button>
              <button
                type="button"
                id="menu-cta-come-say-hi"
                class="menu-qr-landing-cta menu-qr-landing-cta--quiet"
                phx-click="enter_visit"
              >
                Come say hi
              </button>
            </div>
          </div>
        </div>
      </div>

      <div :if={@menu_stage == :craving} id="menu-craving-chooser" class="menu-qr-craving">
        <div class="menu-qr-craving-hero">
          <button type="button" class="menu-qr-craving-back" phx-click="back_to_landing">
            Back
          </button>
          <p class="menu-qr-craving-brand">CoffeeSpot</p>
          <h1 id="menu-craving-chooser-title" class="menu-qr-craving-title">
            What are you craving?
          </h1>
          <p class="menu-qr-craving-lede">Choose something for your CoffeeSpot moment.</p>
        </div>

        <div class="menu-qr-craving-body">
          <div class="menu-qr-craving-grid" role="list">
            <button
              :for={option <- craving_options()}
              type="button"
              id={"menu-craving-option-#{option.id}"}
              class={"menu-qr-craving-option menu-qr-craving-option--#{option.id}"}
              role="listitem"
              phx-click="select_craving"
              phx-value-id={option.id}
            >
              <span class="menu-qr-craving-thumb-wrap">
                <img
                  src={option.image}
                  alt=""
                  class="menu-qr-craving-thumb"
                  loading="lazy"
                  width="56"
                  height="56"
                />
              </span>
              <span class="menu-qr-craving-copy">
                <span class="menu-qr-craving-label">{option.label}</span>
              </span>
            </button>
          </div>
        </div>
      </div>

      <div :if={@menu_stage == :visit} id="menu-visit-stub" class="menu-qr-stub">
        <button type="button" class="menu-qr-stub-back" phx-click="back_to_landing">
          Back
        </button>
        <p class="menu-qr-stub-brand">CoffeeSpot</p>
        <h1 class="menu-qr-stub-title">Come say hi</h1>
        <p class="menu-qr-stub-lede">
          Visit details for Lilac Marikina will live here. About and Contact pages stay unchanged.
        </p>
      </div>

      <div :if={@menu_stage == :menu} class="menu-page menu-page-brune site-page menu-page--qr">
        <header id="menu-qr-chrome" class="menu-qr-chrome">
          <button
            type="button"
            id="menu-qr-back"
            class="menu-qr-chrome-back"
            phx-click="back_to_craving"
          >
            Back
          </button>
          <p class="menu-qr-chrome-brand">CoffeeSpot</p>
          <div class="menu-qr-chrome-trailing">
            <button
              type="button"
              class="menu-qr-chrome-search"
              aria-label="Search menu"
              phx-click={JS.focus(to: "#menu-search-input")}
            >
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="1.6" />
                <path
                  d="M16.2 16.2 20 20"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linecap="round"
                />
              </svg>
            </button>
            <button
              type="button"
              class={[
                "menu-qr-chrome-bag",
                "brune-icon-bag",
                @basket_pulse? && "brune-basket-btn-pulse"
              ]}
              phx-click="open_basket"
              aria-label={"Checkout, #{cart_count(@cart)} items"}
            >
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path
                  d="M7.5 8.5V7.2a4.5 4.5 0 0 1 9 0v1.3"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linecap="round"
                />
                <path
                  d="M6.2 8.5h11.6l-.7 11.2a1.6 1.6 0 0 1-1.6 1.5H8.5a1.6 1.6 0 0 1-1.6-1.5L6.2 8.5Z"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linejoin="round"
                />
              </svg>
              <span
                :if={cart_count(@cart) > 0}
                class={["brune-bag-count", @basket_pulse? && "is-pulse"]}
              >
                {cart_count(@cart)}
              </span>
            </button>
          </div>
        </header>

        <section class="brune-menu-heading" aria-labelledby="brune-menu-title">
          <h1 id="brune-menu-title" class="brune-menu-heading-title">
            {menu_page_title(@menu_filter)}
          </h1>
        </section>

        <nav
          id="menu-craving"
          class="menu-craving"
          aria-labelledby="menu-craving-title"
        >
          <p id="menu-craving-title" class="menu-craving-title">What are you craving?</p>
          <div class="menu-craving-rail">
            <button
              :for={chip <- menu_craving_chips(@categories)}
              type="button"
              id={"menu-craving-chip-#{chip.key}"}
              phx-click={chip.event}
              phx-value-name={chip[:name]}
              phx-value-id={chip[:id]}
              class={[
                "menu-craving-chip",
                chip_active?(chip, @selected_category, @menu_filter) && "is-active"
              ]}
              aria-pressed={
                to_string(chip_active?(chip, @selected_category, @menu_filter))
              }
              aria-current={
                if(chip_active?(chip, @selected_category, @menu_filter), do: "true")
              }
              aria-label={
                craving_chip_aria_label(
                  chip,
                  chip_active?(chip, @selected_category, @menu_filter)
                )
              }
            >
              <img
                src={chip.thumb}
                alt=""
                class="menu-craving-thumb"
                loading="lazy"
                width="32"
                height="32"
              />
              <span class="menu-craving-label">{chip.label}</span>
              <span
                :if={chip_active?(chip, @selected_category, @menu_filter)}
                class="menu-craving-check"
                aria-hidden="true"
              >
                ✓
              </span>
            </button>
          </div>
        </nav>

        <section class="brune-menu-shell" id="menu">
          <nav class="brune-menu-tabs-line" aria-label="Menu categories">
            <button
              :for={category <- @categories}
              type="button"
              phx-click="select_category"
              phx-value-name={category.name}
              class={[
                "brune-menu-tab-link",
                is_nil(@menu_filter) && @selected_category == category.name &&
                  "brune-menu-tab-link-active"
              ]}
              aria-pressed={
                to_string(is_nil(@menu_filter) && @selected_category == category.name)
              }
            >
              {category_nav_label(category.name)}
            </button>
          </nav>

          <div id="menu-search" class="brune-menu-search brune-menu-search--compact">
            <form phx-change="search" phx-submit="search">
              <div class="brune-search-wrap">
                <span class="brune-search-icon" aria-hidden="true">
                  <svg
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
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

          <div class="brune-menu-body" id="menu-items">
            <div
              :if={
                visible_categories(@categories, @selected_category, @search, @menu_filter) == []
              }
              id="menu-filter-empty"
              class="menu-filter-empty"
            >
              <p class="menu-filter-empty-title">Nothing here right now</p>
              <p class="menu-filter-empty-lede">
                Try another craving pick, or browse a category from the tabs above.
              </p>
            </div>

            <section
              :for={
                category <-
                  visible_categories(@categories, @selected_category, @search, @menu_filter)
              }
              class={"brune-menu-section brune-menu-section--#{section_tone(category.name)}"}
              id={"category-#{category.name}"}
              data-category={category.name}
            >
              <h2 class="brune-menu-category-title">
                {menu_section_title(@menu_filter, category.name)}
              </h2>
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
                        <h3 class="brune-menu-item-name">{product.name}</h3>
                        <p class="brune-menu-item-blurb">{product_blurb(product, category.name)}</p>
                        <div class="brune-menu-item-actions">
                          <p class="brune-menu-item-price">{card_price_label(product)}</p>
                          <button
                            type="button"
                            class="brune-menu-add"
                            phx-click="open_detail"
                            phx-value-id={product.id}
                            aria-label={"Add #{product.name}"}
                          >
                            Add
                          </button>
                        </div>
                      </div>
                    </article>
                  </li>
                </ul>
              </div>
            </section>
          </div>

          <.brune_student_promo />
        </section>

        <footer class="brune-mega-footer brune-mega-footer--secondary" aria-label="CoffeeSpot footer">
          <p class="brune-mega-brand">CoffeeSpot</p>

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
        :if={@menu_stage == :menu && @detail}
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
            <h2 id="menu-detail-title" class="menu-detail-name">{@detail.product.name}</h2>

            <p :if={description?(@detail.product.description)} class="menu-detail-description">
              {@detail.product.description}
            </p>
            <p :if={!description?(@detail.product.description)} class="menu-detail-description">
              Prepared fresh at CoffeeSpot Lilac Marikina.
            </p>

            <div :if={detail_multi_size?(@detail)} class="menu-detail-sizes">
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
                  aria-pressed={to_string(@detail.selected_price_id == price.id)}
                >
                  {size_label(price) || "Regular"}
                </button>
              </div>
            </div>

            <p :if={detail_single_size_label(@detail)} class="menu-detail-size-note">
              {detail_single_size_label(@detail)}
            </p>

            <div class="menu-detail-qty-row">
              <p class="menu-detail-label">Quantity</p>
              <div class="menu-qty">
                <button
                  type="button"
                  phx-click="detail_qty"
                  phx-value-delta="-1"
                  aria-label="Decrease quantity"
                  disabled={@detail.quantity <= 1}
                >
                  −
                </button>
                <span aria-live="polite">{@detail.quantity}</span>
                <button
                  type="button"
                  phx-click="detail_qty"
                  phx-value-delta="1"
                  aria-label="Increase quantity"
                >
                  +
                </button>
              </div>
            </div>

            <p class="menu-detail-price menu-detail-price--sheet">
              {Menu.format_price(selected_price(@detail).price)}
            </p>
          </div>

          <footer class="menu-buy-bar menu-buy-bar--detail">
            <button type="button" class="menu-buy-now" phx-click="buy_now">
              Add to bag
            </button>
            <button
              type="button"
              class="menu-buy-basket-link"
              phx-click="open_basket"
              aria-label={"Checkout, #{cart_count(@cart)} items"}
            >
              Bag · {cart_count(@cart)}
            </button>
          </footer>
        </div>
      </div>

      <div :if={@menu_stage == :menu && @toast} class="menu-toast" role="status" aria-live="polite">
        {@toast}
        <button type="button" class="menu-toast-action" phx-click="open_basket">
          View
        </button>
      </div>

      <div
        :if={@menu_stage == :menu && show_floating_bag?(@cart, @basket_open?, @detail)}
        id="menu-floating-bag"
        class="menu-floating-bag"
        role="region"
        aria-label={floating_bag_label(@cart)}
      >
        <p class="menu-floating-bag-summary">
          Your order · {cart_count(@cart)} {floating_bag_items_label(@cart)} · {Menu.format_price(
            cart_total(@cart)
          )}
        </p>
        <button type="button" class="menu-floating-bag-cta" phx-click="open_basket">
          View bag
        </button>
      </div>

      <div
        :if={@menu_stage == :menu && @basket_open?}
        class={["menu-basket-layer", @basket_closing? && "is-closing"]}
        id="menu-basket"
        phx-window-keydown="close_basket"
        phx-key="Escape"
      >
        <button
          type="button"
          class="menu-basket-backdrop"
          phx-click="close_basket"
          aria-label="Close basket"
        >
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
            <button
              type="button"
              class="menu-basket-close"
              phx-click="close_basket"
              aria-label="Close"
            >
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

          <div :if={@cart != []} class="menu-basket-body">
            <ul class="menu-basket-list">
              <li :for={line <- @cart} class="menu-basket-line">
                <div class="menu-basket-line-visual">
                  <img src={line.image} alt="" class="menu-basket-line-photo" />
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

            <div class="menu-basket-checkout-fields">
              <form
                id="menu-checkout-form"
                class="menu-checkout"
                phx-change="update_checkout"
                phx-submit="validate_checkout"
              >
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

                <div class="menu-checkout-field menu-checkout-field--optional">
                  <label class="menu-checkout-label menu-checkout-label--optional" for="checkout-notes">
                    Add a note <span class="menu-checkout-optional">(optional)</span>
                  </label>
                  <textarea
                    id="checkout-notes"
                    name="notes"
                    rows="2"
                    maxlength="200"
                    placeholder="less ice, oat milk, no sugar…"
                    class="menu-checkout-input menu-checkout-textarea menu-checkout-textarea--optional"
                    phx-debounce="200"
                  >{Phoenix.HTML.Form.normalize_value("textarea", @notes)}</textarea>
                </div>
              </form>

              <p class="menu-checkout-payment-info" aria-label="Payment">
                <span class="menu-checkout-payment-info-label">Payment</span>
                <span class="menu-checkout-payment-info-value">Pay at counter</span>
              </p>
            </div>
          </div>

          <div :if={@cart != []} id="menu-basket-submit" class="menu-basket-submit">
            <div class="menu-basket-total">
              <span>Total</span>
              <strong>{Menu.format_price(cart_total(@cart))}</strong>
            </div>

            <p class="menu-basket-submit-payment">Pay at counter</p>

            <p
              :if={checkout_summary_error(@checkout_errors)}
              id="menu-checkout-summary"
              class="menu-checkout-summary"
              role="alert"
            >
              {checkout_summary_error(@checkout_errors)}
            </p>

            <%= if checkout_valid?(@fulfillment, @customer_name, @table_number) do %>
              <button
                type="button"
                class="menu-basket-checkout"
                phx-click="place_order"
                disabled={@placing_order?}
              >
                {if @placing_order?, do: "Placing order…", else: "Place order · Pay at counter"}
              </button>
              <div class="menu-basket-alt">
                <p class="menu-basket-alt-label">Other ways to order</p>
                <a
                  href={CoffeeSpot.order_whatsapp_url(@cart, checkout_payload(assigns))}
                  class="menu-basket-whatsapp"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Message us on WhatsApp instead
                </a>
                <p class="menu-basket-whatsapp-note">
                  WhatsApp orders don’t create a tracked order number.
                </p>
              </div>
            <% else %>
              <button type="button" class="menu-basket-checkout" phx-click="validate_checkout">
                Place order
              </button>
            <% end %>

            <p class="menu-basket-note">You’ll get an order number to show at the counter.</p>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  defp visible_categories(categories, selected_category, search, filter) do
    query = String.trim(search) |> String.downcase()

    categories =
      cond do
        filter == :matcha ->
          filter_matcha_categories(categories)

        filter == :sweets ->
          filter_sweets_categories(categories)

        query != "" ->
          categories

        true ->
          Enum.filter(categories, &(&1.name == selected_category))
      end

    if query == "" do
      categories
    else
      filter_categories_by_query(categories, query)
    end
  end

  defp filter_categories_by_query(categories, query) do
    categories
    |> Enum.map(fn category ->
      filtered_groups =
        Enum.map(category.groups, fn group ->
          filtered =
            Enum.filter(group.products, fn product ->
              String.downcase(product.name) |> String.contains?(query)
            end)

          %{group | products: filtered}
        end)
        |> Enum.reject(fn group -> group.products == [] end)

      %{category | groups: filtered_groups}
    end)
    |> Enum.reject(fn category -> category.groups == [] end)
  end

  defp filter_matcha_categories(categories) do
    categories
    |> Enum.map(fn category ->
      filtered_groups =
        Enum.map(category.groups, fn group ->
          filtered = Enum.filter(group.products, &matcha_product?/1)
          %{group | products: filtered}
        end)
        |> Enum.reject(fn group -> group.products == [] end)

      %{category | groups: filtered_groups}
    end)
    |> Enum.reject(fn category -> category.groups == [] end)
  end

  defp filter_sweets_categories(categories) do
    categories
    |> Enum.filter(&(&1.name == "FOOD"))
    |> Enum.map(fn category ->
      filtered_groups =
        Enum.map(category.groups, fn group ->
          filtered = Enum.filter(group.products, &sweets_product?/1)
          %{group | products: filtered}
        end)
        |> Enum.reject(fn group -> group.products == [] end)

      %{category | groups: filtered_groups}
    end)
    |> Enum.reject(fn category -> category.groups == [] end)
  end

  defp matcha_product?(%{name: name}) when is_binary(name) do
    String.contains?(String.downcase(name), "matcha")
  end

  defp matcha_product?(_), do: false

  defp sweets_product?(%{name: name}), do: Menu.sweets_product_name?(name)
  defp sweets_product?(_), do: false

  defp craving_options do
    [
      %{
        id: "coffee",
        label: "Coffee",
        category: "HOT",
        filter: nil,
        image: "/images/coffeespot/coffee-espresso-01.jpg"
      },
      %{
        id: "iced",
        label: "Iced",
        category: "COLD",
        filter: nil,
        image: "/images/coffeespot/cold-signature-01.jpg"
      },
      %{
        id: "frappe",
        label: "Frappe",
        category: "FRAPPE",
        filter: nil,
        image: "/images/coffeespot/IMG_3458.JPG"
      },
      %{
        id: "soda",
        label: "Soda",
        category: "SODA",
        filter: nil,
        image: "/images/coffeespot/soda-signature-01.jpg"
      },
      %{
        id: "food",
        label: "Food",
        category: "FOOD",
        filter: nil,
        image: "/images/coffeespot/food-savory-01.jpg"
      },
      %{
        id: "matcha",
        label: "Matcha",
        category: nil,
        filter: :matcha,
        image: "/images/coffeespot/IMG_3471.JPG"
      },
      %{
        id: "sweets",
        label: "Sweets",
        category: "FOOD",
        filter: :sweets,
        image: "/images/coffeespot/pastry-signature-01.jpg"
      }
    ]
  end

  defp apply_craving_option(socket, %{filter: :matcha}) do
    selected =
      socket.assigns.categories
      |> filter_matcha_categories()
      |> List.first()
      |> case do
        %{name: name} -> name
        _ -> socket.assigns.selected_category
      end

    socket
    |> assign(:menu_stage, :menu)
    |> assign(:menu_filter, :matcha)
    |> assign(:selected_category, selected)
    |> assign(:search, "")
    |> assign(:detail, nil)
    |> assign(:detail_closing?, false)
  end

  defp apply_craving_option(socket, %{filter: :sweets, category: "FOOD"}) do
    socket
    |> assign(:menu_stage, :menu)
    |> assign(:menu_filter, :sweets)
    |> assign(:selected_category, "FOOD")
    |> assign(:search, "")
    |> assign(:detail, nil)
    |> assign(:detail_closing?, false)
  end

  defp apply_craving_option(socket, %{filter: nil, category: category})
       when is_binary(category) do
    if Enum.any?(socket.assigns.categories, &(&1.name == category)) do
      socket
      |> assign(:menu_stage, :menu)
      |> assign(:menu_filter, nil)
      |> assign(:selected_category, category)
      |> assign(:search, "")
      |> assign(:detail, nil)
      |> assign(:detail_closing?, false)
    else
      # Category currently empty — still enter menu with empty state.
      socket
      |> assign(:menu_stage, :menu)
      |> assign(:menu_filter, nil)
      |> assign(:selected_category, category)
      |> assign(:search, "")
      |> assign(:detail, nil)
      |> assign(:detail_closing?, false)
    end
  end

  defp apply_craving_option(socket, _option), do: socket

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

  defp show_floating_bag?(cart, basket_open?, detail) do
    cart != [] && not basket_open? && is_nil(detail)
  end

  defp floating_bag_items_label(cart) do
    if cart_count(cart) == 1, do: "item", else: "items"
  end

  defp floating_bag_label(cart) do
    "Your order, #{cart_count(cart)} #{floating_bag_items_label(cart)}, #{Menu.format_price(cart_total(cart))}"
  end

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

  defp detail_multi_size?(%{product: %{product_prices: prices}}) when length(prices) > 1, do: true
  defp detail_multi_size?(_detail), do: false

  defp detail_single_size_label(%{product: %{product_prices: [price | _]}}) do
    case size_label(price) do
      nil -> nil
      label -> label
    end
  end

  defp detail_single_size_label(_detail), do: nil

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

  defp menu_page_title(:matcha), do: "Matcha"
  defp menu_page_title(:sweets), do: "Sweets"
  defp menu_page_title(_), do: "Menu"

  defp menu_section_title(:matcha, category_name), do: craving_label(category_name)
  defp menu_section_title(:sweets, _category_name), do: "Sweets"
  defp menu_section_title(_, category_name), do: category_nav_label(category_name)

  defp craving_label("HOT"), do: "Coffee"
  defp craving_label("COLD"), do: "Iced"
  defp craving_label("FRAPPE"), do: "Frappe"
  defp craving_label("SODA"), do: "Soda"
  defp craving_label("FOOD"), do: "Food"
  defp craving_label(name), do: category_nav_label(name)

  defp menu_craving_chips(categories) do
    category_chips =
      Enum.map(categories, fn category ->
        %{
          key: category.name,
          label: craving_label(category.name),
          event: "select_category",
          name: category.name,
          id: nil,
          thumb: craving_thumb(category),
          kind: :category
        }
      end)

    filter_chips =
      [
        Enum.find(craving_options(), &(&1.id == "matcha")),
        Enum.find(craving_options(), &(&1.id == "sweets"))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn option ->
        %{
          key: option.id,
          label: option.label,
          event: "select_craving",
          name: nil,
          id: option.id,
          thumb: option.image,
          kind: :filter
        }
      end)

    category_chips ++ filter_chips
  end

  defp chip_active?(%{kind: :filter, id: "matcha"}, _selected, :matcha), do: true
  defp chip_active?(%{kind: :filter, id: "sweets"}, _selected, :sweets), do: true

  defp chip_active?(%{kind: :category, name: name}, selected, nil), do: selected == name
  defp chip_active?(_chip, _selected, _filter), do: false

  defp craving_chip_aria_label(%{label: label}, true), do: "#{label}, selected"
  defp craving_chip_aria_label(%{label: label}, false), do: "Show #{label} menu"

  defp craving_thumb(category) do
    case craving_sample_product(category) do
      %{name: product_name} -> Menu.product_image(category.name, product_name)
      _ -> Menu.product_image(category.name, category.name)
    end
  end

  defp craving_sample_product(%{groups: groups}) do
    Enum.find_value(groups, fn group -> List.first(group.products) end)
  end

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

  defp checkout_summary_error(errors) when errors == %{}, do: nil

  defp checkout_summary_error(errors) when is_map(errors) do
    has_name? = Map.has_key?(errors, :customer_name)
    has_table? = Map.has_key?(errors, :table_number)

    cond do
      has_name? and has_table? -> "Enter your name and table number."
      has_name? -> "Please enter your name."
      has_table? -> "Enter your table number."
      true -> errors |> Map.values() |> List.first()
    end
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

  defp unavailable_toast([name]), do: "#{name} is no longer available. Update your bag and try again."

  defp unavailable_toast(names) when is_list(names) do
    "#{Enum.join(names, ", ")} are no longer available. Update your bag and try again."
  end
end

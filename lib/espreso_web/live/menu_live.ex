defmodule EspresoWeb.MenuLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.BusinessSettings
  alias Espreso.PayMongo

  @impl true
  def mount(_params, _session, socket) do
    categories = Menu.list_menu()
    selected = default_category(categories)

    payment_config = BusinessSettings.payment_config()

    {:ok,
     socket
     |> assign(:page_title, "Menu")
     |> assign(:payments_mode, payment_config.payments_mode)
     |> assign(:gcash_pay_available?, wallet_pay_available?(payment_config, :gcash))
     |> assign(:maya_pay_available?, wallet_pay_available?(payment_config, :maya))
     |> assign(:menu_stage, :landing)
     |> assign(:menu_filter, nil)
     |> assign(:categories, categories)
     |> assign(:selected_category, selected)
     |> assign(:search, "")
     |> assign(:search_open?, false)
     |> assign(:cart, [])
     |> assign(:basket_open?, false)
     |> assign(:basket_closing?, false)
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)
     |> assign(:toast, nil)
     |> assign(:basket_pulse?, false)
     |> assign(:bag_add_delta, nil)
     |> assign(:fulfillment, :dine_in)
     |> assign(:fulfillment_touched?, false)
     |> assign(:table_number, "")
     |> assign(:customer_name, "")
     |> assign(:notes, "")
     |> assign(:checkout_errors, %{})
     |> assign(:payment_method, :counter)
     |> assign(:payment_touched?, false)
     |> assign(:placing_order?, false)
     |> assign(:my_orders, [])
     |> assign(:my_orders_open?, false), layout: false}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> apply_table_param(params)
     |> apply_menu_stage_param(params)}
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
     |> assign(:basket_pulse?, false)
     |> assign(:bag_add_delta, nil)}
  end

  def handle_info({:order_changed, %{id: id} = order}, socket) do
    case Enum.find(socket.assigns.my_orders, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      existing ->
        {:noreply, update_my_order_summary(socket, existing, order)}
    end
  end

  @impl true
  def handle_event("enter_menu", _params, socket) do
    category = default_category(socket.assigns.categories)

    {:noreply,
     socket
     |> push_patch(to: menu_path(socket, :menu, category: category, filter: nil))
     |> then(fn socket ->
       if is_binary(category) do
         socket
         |> push_event("scroll_active_chip", %{id: "menu-craving-chip-#{category}"})
         |> push_event("scroll_to_menu_content", %{})
       else
         socket
       end
     end)}
  end

  def handle_event("enter_craving", _params, socket) do
    # Deprecated hop: keep for deep links / legacy handlers; normal UI uses enter_menu.
    {:noreply, push_patch(socket, to: menu_path(socket, :craving))}
  end

  def handle_event("enter_visit", _params, socket) do
    {:noreply, push_patch(socket, to: menu_path(socket, :visit))}
  end

  def handle_event("back_to_landing", _params, socket) do
    {:noreply, push_patch(socket, to: menu_path(socket, :landing))}
  end

  def handle_event("back_to_craving", _params, socket) do
    # Legacy event name — return to Landing where cravings now live.
    {:noreply, push_patch(socket, to: menu_path(socket, :landing))}
  end

  def handle_event("select_craving", %{"id" => id}, socket) do
    case Enum.find(craving_options(), &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      option ->
        {:noreply,
         socket
         |> push_patch(to: craving_option_path(socket, option))
         |> push_qr_nav_visibility(option)}
    end
  end

  def handle_event("select_category", %{"name" => "ALL"}, socket) do
    {:noreply,
     socket
     |> push_patch(to: menu_path(socket, :menu, category: "ALL", filter: nil))
     |> push_event("scroll_active_chip", %{id: "menu-craving-chip-ALL"})
     |> push_event("scroll_to_menu_content", %{})}
  end

  def handle_event("select_category", %{"name" => name}, socket) do
    if Enum.any?(socket.assigns.categories, &(&1.name == name)) do
      {:noreply,
       socket
       |> push_patch(to: menu_path(socket, :menu, category: name, filter: nil))
       |> push_event("scroll_active_chip", %{id: "menu-craving-chip-#{name}"})
       |> push_event("scroll_to_menu_content", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_search", _params, socket) do
    open? = not socket.assigns.search_open?

    socket =
      socket
      |> assign(:search_open?, open?)
      |> then(fn sock -> if open?, do: push_event(sock, "focus_menu_search", %{}), else: sock end)

    {:noreply, socket}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search, "")
     |> assign(:search_open?, false)}
  end

  def handle_event("search", %{"search" => query}, socket) do
    trimmed = String.trim(query)

    # Keep Matcha/Sweets filter context; search narrows within the active view.
    {:noreply,
     socket
     |> assign(:search, query)
     |> assign(:search_open?, trimmed != "" or socket.assigns.search_open?)}
  end

  def handle_event("open_detail", %{"id" => id}, socket) do
    {:noreply, open_detail(socket, id)}
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
        {:noreply, put_product_in_cart(socket, category_name, product, price, qty)}
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
     |> assign(:my_orders_open?, false)
     |> assign(:checkout_errors, %{})
     |> push_event("scroll_basket_top", %{})}
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
      |> assign(:fulfillment_touched?, true)
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

    {:noreply,
     socket
     |> assign(:customer_name, name)
     |> assign(:table_number, table)
     |> assign(:checkout_errors, %{})}
  end

  def handle_event("validate_checkout", _params, socket) do
    {:noreply, assign(socket, :checkout_errors, checkout_errors(socket.assigns))}
  end

  def handle_event("set_payment_method", %{"method" => method}, socket) do
    payment_method =
      resolve_payment_method(
        method,
        socket.assigns.payments_mode,
        socket.assigns.gcash_pay_available?,
        socket.assigns.maya_pay_available?
      )

    {:noreply,
     socket
     |> assign(:payment_method, payment_method)
     |> assign(:payment_touched?, true)}
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

      socket.assigns.payment_method in [:gcash, :maya] ->
        case socket.assigns.payments_mode do
          "paymongo" -> place_online_order(socket, socket.assigns.payment_method)
          "qrph_manual" -> place_qrph_order(socket, socket.assigns.payment_method)
          _ -> place_counter_order(socket)
        end

      true ->
        place_counter_order(socket)
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

  def handle_event("restore_cart", params, socket) do
    {:noreply, maybe_restore_cart(socket, params)}
  end

  def handle_event("restore_my_orders", params, socket) do
    {:noreply, maybe_restore_my_orders(socket, params)}
  end

  # Compatibility for older client hooks still emitting a single number.
  def handle_event("restore_current_order", params, socket) do
    number = Map.get(params, "number") || Map.get(params, :number)
    {:noreply, maybe_restore_my_orders(socket, %{"numbers" => [number]})}
  end

  def handle_event("toggle_my_orders", _params, socket) do
    {:noreply, assign(socket, :my_orders_open?, !socket.assigns.my_orders_open?)}
  end

  def handle_event("close_my_orders", _params, socket) do
    {:noreply, assign(socket, :my_orders_open?, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="menu-page"
      phx-hook="MenuBrowse"
      data-cart={Jason.encode!(cart_storage_payload(@cart))}
      class={[
        "menu-live-root",
        @menu_stage != :menu && "menu-live-root--qr-entry",
        (@detail || @basket_open? || @my_orders_open?) && "menu-page-locked"
      ]}
    >
      <div :if={@menu_stage == :landing} id="menu-landing" class="menu-qr-landing">
        <header class="menu-qr-landing-top menu-qr-top">
          <p class="menu-qr-landing-top-brand menu-qr-top-brand">CoffeeSpot</p>
        </header>

        <div
          id="menu-landing-carousel"
          class="menu-qr-landing-carousel"
          phx-hook="LandingCarousel"
          aria-label="CoffeeSpot intro"
        >
          <section
            id="menu-landing-slide-welcome"
            class="menu-qr-landing-slide"
            aria-label="Welcome"
          >
            <div class="menu-qr-landing-media" aria-hidden="true">
              <img
                src="/images/coffeespot/IMG_3498.png"
                alt=""
                class="menu-qr-landing-photo"
                width="817"
                height="1024"
              />
            </div>
            <div class="menu-qr-landing-scrim" aria-hidden="true"></div>
            <div class="menu-qr-landing-copy">
              <h1 class="menu-qr-landing-headline">Your coffee moment starts here.</h1>
              <p class="menu-qr-landing-lede">Browse the menu. Order from your table.</p>
            </div>
          </section>

          <section
            id="menu-landing-slide-visit"
            class="menu-qr-landing-slide"
            aria-label="Visit CoffeeSpot"
          >
            <div class="menu-qr-landing-media" aria-hidden="true">
              <img
                src="/images/coffeespot/IMG_3497.jpg"
                alt=""
                class="menu-qr-landing-photo menu-qr-landing-photo--visit"
                width="800"
                height="1000"
              />
            </div>
            <div class="menu-qr-landing-scrim" aria-hidden="true"></div>
            <div class="menu-qr-landing-copy">
              <h1 class="menu-qr-landing-headline">Visit CoffeeSpot</h1>
              <p class="menu-qr-landing-lede">
                {CoffeeSpot.location()} · Come say hi in Lilac, Marikina.
              </p>
              <button
                type="button"
                id="menu-cta-visit-coffeespot"
                class="menu-qr-landing-visit-link"
                phx-click="enter_visit"
              >
                See hours &amp; directions →
              </button>
            </div>
          </section>
        </div>

        <div class="menu-qr-landing-dock">
          <div class="menu-qr-landing-dots" role="tablist" aria-label="Intro slides">
            <button
              type="button"
              class="menu-qr-landing-dot is-active"
              data-landing-dot="0"
              role="tab"
              aria-selected="true"
              aria-label="Welcome slide"
            >
            </button>
            <button
              type="button"
              class="menu-qr-landing-dot"
              data-landing-dot="1"
              role="tab"
              aria-selected="false"
              aria-label="Visit CoffeeSpot slide"
            >
            </button>
          </div>

          <button
            type="button"
            id="menu-cta-view-menu"
            class="menu-qr-landing-cta menu-qr-landing-cta--primary"
            phx-click="enter_menu"
          >
            <span class="menu-qr-landing-cta-label">Get Started</span>
            <span class="menu-qr-landing-cta-arrow" aria-hidden="true">→</span>
          </button>
        </div>
      </div>

      <div :if={@menu_stage == :craving} id="menu-craving-chooser" class="menu-qr-craving">
        <div class="menu-qr-craving-bridge" aria-hidden="true">
          <img
            src="/images/coffeespot/cold-signature-01.jpg"
            alt=""
            class="menu-qr-craving-bridge-photo"
            width="800"
            height="1000"
          />
          <div class="menu-qr-craving-bridge-scrim"></div>
        </div>

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
              <span class="menu-qr-craving-label">{option.label}</span>
              <span class="menu-qr-craving-thumb-wrap">
                <img
                  src={option.image}
                  alt=""
                  class="menu-qr-craving-thumb"
                  loading="lazy"
                  width="40"
                  height="40"
                />
              </span>
            </button>
          </div>
        </div>
      </div>

      <div :if={@menu_stage == :visit} id="menu-visit" class="menu-qr-visit">
        <div class="menu-qr-visit-bridge" aria-hidden="true">
          <img
            src="/images/coffeespot/IMG_3497.jpg"
            alt=""
            class="menu-qr-visit-bridge-photo"
            width="800"
            height="1000"
          />
          <div class="menu-qr-visit-bridge-scrim"></div>
        </div>

        <div class="menu-qr-visit-sheet">
          <button type="button" class="menu-qr-visit-back" phx-click="back_to_landing">
            Back
          </button>

          <p class="menu-qr-visit-brand">{CoffeeSpot.business_name()}</p>
          <h1 class="menu-qr-visit-title">Visit CoffeeSpot</h1>
          <p class="menu-qr-visit-place">{CoffeeSpot.location()}</p>

          <section class="menu-qr-visit-block" aria-labelledby="menu-visit-address-label">
            <h2 id="menu-visit-address-label" class="menu-qr-visit-label">Address</h2>
            <p class="menu-qr-visit-text">{CoffeeSpot.address_short()}</p>
            <a
              href={CoffeeSpot.map_link_url()}
              id="menu-visit-maps"
              class="menu-qr-visit-link"
              target="_blank"
              rel="noopener noreferrer"
            >
              Open in Maps
            </a>
          </section>

          <section class="menu-qr-visit-block" aria-labelledby="menu-visit-hours-label">
            <h2 id="menu-visit-hours-label" class="menu-qr-visit-label">Hours</h2>
            <p
              :for={line <- visit_hours_lines()}
              class={[
                "menu-qr-visit-text",
                visit_hours_note?(line) && "menu-qr-visit-text--note"
              ]}
            >
              {line}
            </p>
          </section>

          <section class="menu-qr-visit-block" aria-labelledby="menu-visit-contact-label">
            <h2 id="menu-visit-contact-label" class="menu-qr-visit-label">Contact</h2>
            <a
              href={"tel:#{CoffeeSpot.phone_tel()}"}
              id="menu-visit-phone"
              class="menu-qr-visit-link menu-qr-visit-link--stack"
            >
              {CoffeeSpot.phone_display()}
            </a>
            <a
              href={CoffeeSpot.email_url()}
              id="menu-visit-email"
              class="menu-qr-visit-link menu-qr-visit-link--stack"
            >
              {CoffeeSpot.email()}
            </a>
          </section>

          <section
            class="menu-qr-visit-block menu-qr-visit-socials"
            aria-label="Social"
          >
            <a
              :for={link <- CoffeeSpot.social_links()}
              href={link.href}
              id={"menu-visit-#{link.id}"}
              class={"menu-qr-visit-social menu-qr-visit-social--#{link.id}"}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={"CoffeeSpot on #{link.label}"}
            >
              <.social_icon name={link.id} />
            </a>
          </section>

          <button
            type="button"
            id="menu-visit-view-menu"
            class="menu-qr-visit-menu-link"
            phx-click="enter_menu"
          >
            View the menu
          </button>
        </div>
      </div>

      <div :if={@menu_stage == :menu} class="menu-page menu-page-brune site-page menu-page--qr">
        <div id="menu-qr-sticky" class="menu-qr-sticky">
          <header id="menu-qr-chrome" class="menu-qr-chrome menu-qr-top">
            <button
              type="button"
              id="menu-qr-back"
              class="menu-qr-chrome-back"
              phx-click="back_to_landing"
              aria-label="Back to CoffeeSpot home"
            >
              <.icon name="hero-arrow-left" class="menu-qr-chrome-icon" />
            </button>
            <p class="menu-qr-chrome-brand menu-qr-top-brand">CoffeeSpot</p>
            <div class="menu-qr-chrome-trailing">
              <button
                type="button"
                id="menu-qr-search-toggle"
                class={[
                  "menu-qr-chrome-search",
                  (@search_open? || search_active?(@search)) && "is-active"
                ]}
                phx-click="toggle_search"
                aria-label="Search menu"
                aria-expanded={to_string(@search_open?)}
                aria-controls="menu-search"
              >
                <.icon name="hero-magnifying-glass" class="menu-qr-chrome-icon" />
                <span
                  :if={search_active?(@search) && !@search_open?}
                  class="menu-qr-chrome-search-dot"
                  aria-hidden="true"
                >
                </span>
              </button>
              <button
                type="button"
                id="menu-qr-bag"
                class={[
                  "menu-qr-chrome-bag",
                  "brune-icon-bag",
                  @basket_pulse? && "is-bag-confirm"
                ]}
                phx-click="open_basket"
                aria-label={"Your order, #{cart_count(@cart)} items"}
              >
                <.icon name="hero-shopping-bag" class="menu-qr-chrome-bag-icon" />
                <span
                  :if={cart_count(@cart) > 0}
                  class={["brune-bag-count", @basket_pulse? && "is-pulse"]}
                >
                  {cart_count(@cart)}
                </span>
                <span
                  :if={@bag_add_delta}
                  class="menu-qr-bag-plus"
                  aria-hidden="true"
                >
                  +{@bag_add_delta}
                </span>
              </button>
            </div>
          </header>

          <div
            id="menu-search"
            class={[
              "brune-menu-search brune-menu-search--compact menu-qr-search",
              @search_open? && "is-open"
            ]}
          >
            <form phx-change="search" phx-submit="search">
              <div class="brune-search-wrap menu-qr-search-wrap">
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
                <button
                  type="button"
                  id="menu-qr-search-close"
                  class="menu-qr-search-close"
                  phx-click="clear_search"
                  aria-label="Clear search"
                >
                  <.icon name="hero-x-mark" class="menu-qr-search-close-icon" />
                </button>
              </div>
            </form>
          </div>

          <nav
            id="menu-craving"
            class="menu-craving menu-craving--sticky"
            aria-label="Menu categories"
          >
            <p class="menu-craving-context" id="menu-craving-context">Categories</p>
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
        </div>

        <section class="brune-menu-shell" id="menu">
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
                Try another craving pick, or browse a category above.
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
                        <span
                          :if={badge = temperature_badge(category.name)}
                          class={"menu-temp-badge menu-temp-badge--#{badge.tone}"}
                        >
                          {badge.label}
                        </span>
                      </div>
                      <div class="brune-menu-item-body">
                        <h3 class="brune-menu-item-name">{product.name}</h3>
                        <p class="brune-menu-item-blurb">{product_blurb(product, category.name)}</p>
                        <div class="brune-menu-item-actions">
                          <p class="brune-menu-item-price">{card_price_label(product)}</p>
                          <button
                            type="button"
                            class="brune-menu-add brune-menu-add--icon"
                            phx-click="open_detail"
                            phx-value-id={product.id}
                            aria-label={"Add #{product.name}"}
                            title={"Add #{product.name}"}
                          >
                            <.icon name="hero-plus" class="brune-menu-add-icon" />
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
          <.brune_hours_strip />
        </section>

        <footer class="brune-mega-footer brune-mega-footer--secondary" aria-label="CoffeeSpot footer">
          <p class="brune-mega-brand">CoffeeSpot Marikina</p>
          <p class="menu-footer-owned-label">Owned and Operated by:</p>
          <p class="menu-footer-owned-name">Elilai Kafe</p>

          <div class="menu-footer-socials" aria-label="Social">
            <a
              :for={link <- CoffeeSpot.social_links()}
              href={link.href}
              id={"menu-footer-#{link.id}"}
              class={"menu-footer-social menu-footer-social--#{link.id}"}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={"CoffeeSpot on #{link.label}"}
            >
              <.social_icon name={link.id} />
            </a>
          </div>
        </footer>
      </div>

      <div
        :if={@menu_stage == :menu && @detail}
        class={["menu-buy-layer", "menu-buy-layer--sheet", @detail_closing? && "is-closing"]}
        id="menu-detail"
        phx-window-keydown="close_detail"
        phx-key="Escape"
      >
        <button
          type="button"
          class="menu-buy-backdrop"
          phx-click="close_detail"
          aria-label="Close product detail"
        >
        </button>
        <aside
          id="menu-buy-panel"
          class="menu-buy-panel menu-buy-panel--sheet"
          role="dialog"
          aria-modal="true"
          aria-labelledby="menu-detail-title"
          phx-hook="MenuSheet"
          data-close-event="close_detail"
        >
          <div class="menu-buy-hero">
            <div class="menu-buy-handle" data-drag-handle>
              <span class="menu-buy-handle-bar" aria-hidden="true"></span>
            </div>

            <img
              src={Menu.product_image(@detail.category_name, @detail.product.name)}
              alt={@detail.product.name}
              class="menu-buy-photo"
            />

            <span
              :if={badge = temperature_badge(@detail.category_name)}
              class={"menu-temp-badge menu-temp-badge--detail menu-temp-badge--#{badge.tone}"}
            >
              {badge.label}
            </span>

            <div class="menu-buy-hero-scrim" aria-hidden="true"></div>

            <button
              type="button"
              class="menu-buy-close menu-buy-hero-back"
              phx-click="close_detail"
              aria-label="Back to menu"
            >
              <.icon name="hero-arrow-left" class="menu-buy-hero-back-icon" />
            </button>
          </div>

          <div class="menu-buy-body">
            <div class="menu-detail-heading">
              <h2 id="menu-detail-title" class="menu-detail-name">{@detail.product.name}</h2>
              <p class="menu-detail-price menu-detail-price--sheet">
                {Menu.format_price(selected_price(@detail).price)}
              </p>
            </div>

            <p :if={description?(@detail.product.description)} class="menu-detail-description">
              {@detail.product.description}
            </p>
            <p :if={!description?(@detail.product.description)} class="menu-detail-description">
              Prepared fresh at CoffeeSpot Lilac Marikina.
            </p>

            <div class="menu-detail-options">
              <div :if={detail_multi_size?(@detail)} class="menu-detail-option">
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

              <p
                :if={!detail_multi_size?(@detail) && detail_single_size_label(@detail)}
                class="menu-detail-size-note"
              >
                {detail_single_size_label(@detail)}
              </p>

              <div class="menu-detail-option menu-detail-qty-row">
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
            </div>
          </div>

          <footer class="menu-buy-bar menu-buy-bar--detail">
            <button type="button" class="menu-buy-now" phx-click="buy_now">
              Add to your order
            </button>
          </footer>
        </aside>
      </div>

      <div
        :if={@menu_stage == :menu && @toast}
        class="menu-toast"
        role="status"
        aria-live="polite"
      >
        {@toast}
      </div>

      <button
        :if={
          @menu_stage == :menu &&
            show_floating_my_orders?(@my_orders, @my_orders_open?, @basket_open?, @detail)
        }
        type="button"
        id="menu-qr-my-orders"
        class={[
          "menu-qr-my-orders",
          my_orders_trigger_status?(@my_orders) && "menu-qr-my-orders--status"
        ]}
        phx-click="toggle_my_orders"
        aria-expanded={to_string(@my_orders_open?)}
        aria-controls="menu-my-orders-panel"
        aria-label={my_orders_trigger_aria(@my_orders)}
      >
        <span class="menu-qr-my-orders-icon" aria-hidden="true">
          <.icon name="hero-clipboard-document-list" class="menu-qr-my-orders-icon-glyph" />
        </span>
        <span class="menu-qr-my-orders-label">{my_orders_trigger_label(@my_orders)}</span>
      </button>

      <button
        :if={@menu_stage == :menu && show_floating_bag?(@cart, @basket_open?, @detail)}
        type="button"
        id="menu-floating-bag"
        class="menu-floating-bag"
        phx-click="open_basket"
        aria-label={floating_bag_label(@cart)}
      >
        <span class="menu-floating-bag-summary">
          <span class="menu-floating-bag-count">{cart_count(@cart)}</span>
          <span class="menu-floating-bag-total">{Menu.format_price(cart_total(@cart))}</span>
        </span>
        <span class="menu-floating-bag-cta">View order</span>
      </button>

      <div
        :if={@menu_stage == :menu && @basket_open?}
        class={["menu-basket-layer", "menu-basket-layer--fullscreen", @basket_closing? && "is-closing"]}
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
          class="menu-basket-panel menu-basket-panel--fullscreen"
          role="dialog"
          aria-modal="true"
          aria-labelledby="menu-basket-title"
          phx-hook="MenuSheet"
          data-close-event="close_basket"
        >
          <header class="menu-basket-header menu-qr-chrome menu-qr-top">
            <div class="menu-basket-handle" data-drag-handle>
              <span class="menu-basket-handle-bar" aria-hidden="true"></span>
            </div>

            <button
              type="button"
              class="menu-basket-close"
              phx-click="close_basket"
              aria-label="Back to menu"
            >
              <.icon name="hero-arrow-left" class="menu-qr-chrome-icon" />
            </button>

            <h2 id="menu-basket-title" class="menu-basket-title menu-qr-chrome-brand menu-qr-top-brand">
              Your order
            </h2>

            <span class="menu-basket-header-spacer" aria-hidden="true"></span>
          </header>

          <div :if={@cart == []} class="menu-basket-empty">
            <p class="menu-basket-empty-title">Nothing here yet</p>
            <p>Choose something from the menu, then add it to your order.</p>
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
                      aria-label={"Remove #{line.name}"}
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
                <div class="menu-basket-checkout-card">
                  <fieldset class="menu-checkout-fulfillment">
                    <legend class="menu-checkout-label">Fulfillment</legend>
                    <div class="menu-checkout-options" role="radiogroup" aria-label="Fulfillment">
                      <button
                        type="button"
                        class={[
                          "menu-checkout-option",
                          @fulfillment_touched? && @fulfillment == :dine_in && "is-active"
                        ]}
                        id="checkout-fulfillment-dine-in"
                        phx-click="set_fulfillment"
                        phx-value-type="dine_in"
                        aria-pressed={to_string(@fulfillment_touched? and @fulfillment == :dine_in)}
                      >
                        Dine-in
                      </button>
                      <button
                        type="button"
                        class={[
                          "menu-checkout-option",
                          @fulfillment_touched? && @fulfillment == :pickup && "is-active"
                        ]}
                        id="checkout-fulfillment-pickup"
                        phx-click="set_fulfillment"
                        phx-value-type="pickup"
                        aria-pressed={to_string(@fulfillment_touched? and @fulfillment == :pickup)}
                      >
                        Pickup
                      </button>
                    </div>
                    <p :if={@fulfillment == :pickup} class="menu-checkout-hint" id="checkout-pickup-hint">
                      Pick up at counter when ready.
                    </p>
                  </fieldset>

                  <div :if={@fulfillment == :dine_in} class="menu-checkout-field">
                    <label class="menu-checkout-label" for="checkout-table">Table number</label>
                    <input
                      id="checkout-table"
                      type="number"
                      name="table_number"
                      inputmode="numeric"
                      pattern="[0-9]*"
                      min="1"
                      max="99"
                      value={@table_number}
                      placeholder="e.g. 7"
                      class={[
                        "menu-checkout-input",
                        "menu-checkout-input--table",
                        @checkout_errors[:table_number] && "is-error"
                      ]}
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

                  <fieldset
                    :if={@payments_mode != "counter_only"}
                    class="menu-checkout-payment"
                    id="menu-checkout-payment"
                  >
                    <legend class="menu-checkout-label">Pay with</legend>
                    <div
                      class={[
                        "menu-checkout-options",
                        "menu-checkout-options--pay",
                        pay_option_count(@gcash_pay_available?, @maya_pay_available?) == 3 &&
                          "is-three"
                      ]}
                      role="radiogroup"
                      aria-label="Payment"
                    >
                      <button
                        type="button"
                        class={[
                          "menu-checkout-option",
                          @payment_touched? && @payment_method == :counter && "is-active"
                        ]}
                        id="checkout-pay-counter"
                        phx-click="set_payment_method"
                        phx-value-method="counter"
                        aria-pressed={to_string(@payment_touched? and @payment_method == :counter)}
                      >
                        Cash at counter
                      </button>
                      <button
                        :if={@gcash_pay_available?}
                        type="button"
                        class={[
                          "menu-checkout-option",
                          @payment_touched? && @payment_method == :gcash && "is-active"
                        ]}
                        id="checkout-pay-gcash"
                        phx-click="set_payment_method"
                        phx-value-method="gcash"
                        aria-pressed={to_string(@payment_touched? and @payment_method == :gcash)}
                      >
                        GCash
                      </button>
                      <button
                        :if={@maya_pay_available?}
                        type="button"
                        class={[
                          "menu-checkout-option",
                          @payment_touched? && @payment_method == :maya && "is-active"
                        ]}
                        id="checkout-pay-maya"
                        phx-click="set_payment_method"
                        phx-value-method="maya"
                        aria-pressed={to_string(@payment_touched? and @payment_method == :maya)}
                      >
                        Maya
                      </button>
                    </div>
                    <p class="menu-checkout-payment-note menu-basket-note" id="checkout-payment-note">
                      {payment_checkout_note(@payment_method, @payments_mode)}
                    </p>
                  </fieldset>
                  <p
                    :if={@payments_mode == "counter_only"}
                    class="menu-checkout-payment-note menu-basket-note"
                    id="checkout-payment-note"
                  >
                    Pay at the counter when your order is ready.
                  </p>
                </div>
              </form>
            </div>
          </div>
        </aside>

        <div
          :if={@cart != []}
          id="menu-basket-submit"
          class="menu-basket-submit menu-basket-submit--floating"
        >
          <p
            :if={checkout_summary_error(@checkout_errors)}
            id="menu-checkout-summary"
            class="menu-checkout-summary"
            role="alert"
          >
            {checkout_summary_error(@checkout_errors)}
          </p>

          <div class="menu-basket-submit-row">
            <div class="menu-basket-total">
              <strong>{Menu.format_price(cart_total(@cart))}</strong>
              <span class="menu-basket-total-meta">{cart_count_label(@cart)}</span>
            </div>

            <%= if checkout_valid?(@fulfillment, @customer_name, @table_number) do %>
              <button
                type="button"
                class="menu-basket-checkout"
                phx-click="place_order"
                disabled={@placing_order?}
              >
                {checkout_button_label(@payment_method, @placing_order?, @payments_mode)}
              </button>
            <% else %>
              <button type="button" class="menu-basket-checkout" phx-click="validate_checkout">
                Enter your details
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <div
        :if={@menu_stage == :menu && @my_orders_open? && @my_orders != []}
        id="menu-my-orders"
        class="menu-my-orders-layer"
        phx-window-keydown="close_my_orders"
        phx-key="Escape"
      >
        <button
          type="button"
          class="menu-my-orders-backdrop"
          phx-click="close_my_orders"
          aria-label="Close my orders"
        >
        </button>
        <aside
          id="menu-my-orders-panel"
          class="menu-my-orders-panel"
          role="dialog"
          aria-modal="true"
          aria-labelledby="menu-my-orders-title"
        >
          <header class="menu-my-orders-header">
            <div>
              <p class="menu-my-orders-eyebrow">CoffeeSpot</p>
              <h2 id="menu-my-orders-title">My Orders</h2>
            </div>
            <button
              type="button"
              class="menu-my-orders-close"
              phx-click="close_my_orders"
              aria-label="Close my orders"
            >
              Close
            </button>
          </header>

          <div class="menu-my-orders-body">
            <section
              :if={active_my_orders(@my_orders) != []}
              class="menu-my-orders-section"
              aria-labelledby="menu-my-orders-active-heading"
            >
              <h3 id="menu-my-orders-active-heading" class="menu-my-orders-section-title">
                Active
              </h3>
              <ul class="menu-my-orders-list">
                <li
                  :for={order <- active_my_orders(@my_orders)}
                  id={"menu-my-order-#{order.number}"}
                  class="menu-my-orders-card"
                  data-status={order.status}
                  data-payment-status={order.payment_status}
                >
                  <div class="menu-my-orders-card-top">
                    <p class="menu-my-orders-number">{order.number}</p>
                    <p class={[
                      "menu-my-orders-status",
                      my_order_status_class(order)
                    ]}>
                      {customer_my_order_status_label(order)}
                    </p>
                  </div>
                  <p class="menu-my-orders-meta">
                    {order.item_count} {if order.item_count == 1, do: "item", else: "items"} · {Menu.format_price(
                      order.total
                    )}
                  </p>
                  <.link
                    navigate={~p"/order/#{order.number}"}
                    class="menu-my-orders-view"
                  >
                    View Order
                  </.link>
                </li>
              </ul>
            </section>

            <section
              :if={history_my_orders(@my_orders) != []}
              class="menu-my-orders-section"
              aria-labelledby="menu-my-orders-history-heading"
            >
              <h3 id="menu-my-orders-history-heading" class="menu-my-orders-section-title">
                History
              </h3>
              <ul class="menu-my-orders-list">
                <li
                  :for={order <- history_my_orders(@my_orders)}
                  id={"menu-my-order-#{order.number}"}
                  class="menu-my-orders-card menu-my-orders-card--history"
                  data-status={order.status}
                >
                  <div class="menu-my-orders-card-top">
                    <p class="menu-my-orders-number">{order.number}</p>
                    <p class={[
                      "menu-my-orders-status",
                      my_order_status_class(order)
                    ]}>
                      {customer_my_order_status_label(order)}
                    </p>
                  </div>
                  <p class="menu-my-orders-meta">
                    {order.item_count} {if order.item_count == 1, do: "item", else: "items"} · {Menu.format_price(
                      order.total
                    )}
                  </p>
                  <.link
                    navigate={~p"/order/#{order.number}"}
                    class="menu-my-orders-view"
                  >
                    View Order
                  </.link>
                </li>
              </ul>
            </section>

            <p
              :if={active_my_orders(@my_orders) == [] and history_my_orders(@my_orders) == []}
              class="menu-my-orders-empty"
            >
              No orders to show right now.
            </p>
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

        selected_category == "ALL" ->
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

  defp visit_hours_lines do
    CoffeeSpot.public_hours_lines()
  end

  defp visit_hours_note?(line), do: CoffeeSpot.public_hours_note?(line)

  defp craving_options do
    [
      %{
        id: "coffee",
        label: "Hot coffee",
        category: "HOT",
        filter: nil,
        image: "/images/coffeespot/gen-hot-espresso.png"
      },
      %{
        id: "iced",
        label: "Iced coffee",
        category: "COLD",
        filter: nil,
        image: "/images/coffeespot/gen-cold-cafe-latte.png"
      },
      %{
        id: "frappe",
        label: "Frappe",
        category: "FRAPPE",
        filter: nil,
        image: "/images/coffeespot/gen-frappe-salted-caramel.png"
      },
      %{
        id: "soda",
        label: "Soda",
        category: "SODA",
        filter: nil,
        image: "/images/coffeespot/gen-soda-tropical-passion.png"
      },
      %{
        id: "food",
        label: "Food",
        category: "FOOD",
        filter: nil,
        image: "/images/coffeespot/gen-food-beef-tapa.png"
      },
      %{
        id: "matcha",
        label: "Matcha",
        category: nil,
        filter: :matcha,
        image: "/images/coffeespot/gen-hot-matcha-latte.png"
      },
      %{
        id: "sweets",
        label: "Sweets",
        category: "FOOD",
        filter: :sweets,
        image: "/images/coffeespot/gen-food-belgian-waffles.png"
      }
    ]
  end

  defp push_qr_nav_visibility(socket, %{filter: :matcha}) do
    socket
    |> push_event("scroll_active_chip", %{id: "menu-craving-chip-matcha"})
    |> push_event("scroll_to_menu_content", %{})
  end

  defp push_qr_nav_visibility(socket, %{filter: :sweets}) do
    socket
    |> push_event("scroll_active_chip", %{id: "menu-craving-chip-sweets"})
    |> push_event("scroll_to_menu_content", %{})
  end

  defp push_qr_nav_visibility(socket, %{filter: nil, category: category})
       when is_binary(category) do
    socket
    |> push_event("scroll_active_chip", %{id: "menu-craving-chip-#{category}"})
    |> push_event("scroll_to_menu_content", %{})
  end

  defp push_qr_nav_visibility(socket, _option), do: socket

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

  defp open_detail(socket, id) do
    case find_product_with_category(socket.assigns.categories, id) do
      nil ->
        socket

      {category, product} ->
        price = List.first(product.product_prices)

        detail = %{
          product: product,
          category_name: category.name,
          selected_price_id: price && price.id,
          quantity: 1
        }

        socket
        |> assign(:detail, detail)
        |> assign(:detail_closing?, false)
        |> assign(:basket_open?, false)
        |> assign(:basket_closing?, false)
        |> assign(:my_orders_open?, false)
    end
  end

  defp put_product_in_cart(socket, category_name, product, price, qty) do
    cart =
      add_line(
        socket.assigns.cart,
        product,
        price,
        qty,
        Menu.product_image(category_name, product.name)
      )

    socket
    |> assign(:cart, cart)
    |> assign(:detail, nil)
    |> assign(:detail_closing?, false)
    |> assign(:toast, nil)
    |> assign(:basket_pulse?, true)
    |> assign(:bag_add_delta, qty)
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

  # Total quantity across all cart lines (not distinct product count).
  defp cart_count(cart), do: Enum.reduce(cart, 0, fn line, acc -> acc + line.quantity end)

  defp cart_count_label(cart) do
    count = cart_count(cart)
    word = if count == 1, do: "item", else: "items"
    "#{count} #{word} total"
  end

  defp cart_storage_payload(cart) do
    Enum.map(cart, fn line ->
      %{
        "key" => line.key,
        "product_id" => line.product_id,
        "name" => line.name,
        "size" => line.size,
        "price" => Decimal.to_string(line.price),
        "quantity" => line.quantity,
        "image" => line.image
      }
    end)
  end

  defp maybe_restore_cart(socket, params) do
    # Only hydrate an empty in-memory cart (fresh mount / refresh).
    if socket.assigns.cart == [] do
      assign(socket, :cart, sanitize_restored_cart(params, socket.assigns.categories))
    else
      socket
    end
  rescue
    _ -> socket
  end

  defp maybe_restore_my_orders(socket, params) do
    numbers = extract_my_order_numbers(params)
    load_my_orders(socket, numbers)
  rescue
    _ ->
      socket
      |> assign(:my_orders, [])
      |> assign(:my_orders_open?, false)
  end

  defp extract_my_order_numbers(%{"numbers" => numbers}) when is_list(numbers), do: numbers
  defp extract_my_order_numbers(%{numbers: numbers}) when is_list(numbers), do: numbers

  defp extract_my_order_numbers(%{"number" => number}), do: [number]
  defp extract_my_order_numbers(%{number: number}), do: [number]

  defp extract_my_order_numbers(_), do: []

  defp load_my_orders(socket, numbers) do
    orders = Orders.list_orders_by_numbers(numbers)
    summaries = Enum.map(orders, &my_order_summary/1)

    # Drop cancelled from UI; keep numbers for completed/active in client sync.
    visible =
      summaries
      |> Enum.reject(&(&1.status == "cancelled"))

    subscribe_my_orders(socket, visible)

    socket
    |> assign(:my_orders, visible)
    |> push_event("sync_my_orders", %{numbers: Enum.map(visible, & &1.number)})
  end

  defp remember_my_order(socket, order) do
    summary = my_order_summary(order)

    if connected?(socket) and not Enum.any?(socket.assigns.my_orders, &(&1.id == order.id)) do
      Orders.subscribe(order)
    end

    my_orders =
      socket.assigns.my_orders
      |> Enum.reject(&(&1.id == order.id or &1.number == order.number))
      |> then(fn rest -> [summary | rest] end)
      |> Enum.reject(&(&1.status == "cancelled"))
      |> Enum.take(20)

    assign(socket, :my_orders, my_orders)
  end

  defp update_my_order_summary(socket, existing, order) do
    summary = %{
      existing
      | status: order.status,
        payment_status: order.payment_status || existing.payment_status,
        payment_method: order.payment_method || existing.payment_method,
        total: order.total || existing.total,
        inserted_at: order.inserted_at || existing.inserted_at
    }

    my_orders =
      socket.assigns.my_orders
      |> Enum.map(fn entry ->
        if entry.id == order.id, do: summary, else: entry
      end)
      |> Enum.reject(&(&1.status == "cancelled"))

    assign(socket, :my_orders, my_orders)
  end

  defp subscribe_my_orders(socket, summaries) do
    if connected?(socket) do
      already = MapSet.new(Enum.map(socket.assigns.my_orders, & &1.id))

      Enum.each(summaries, fn summary ->
        if not MapSet.member?(already, summary.id) do
          Orders.subscribe(summary.id)
        end
      end)
    end

    :ok
  end

  defp my_order_summary(order) do
    item_count =
      order.items
      |> List.wrap()
      |> Enum.reduce(0, fn item, acc -> acc + (item.quantity || 0) end)

    %{
      id: order.id,
      number: order.number,
      status: order.status,
      payment_status: order.payment_status,
      payment_method: order.payment_method,
      item_count: item_count,
      total: order.total,
      inserted_at: order.inserted_at
    }
  end

  defp active_my_orders(orders) do
    ready = Enum.filter(orders, &(&1.status == "ready"))
    preparing = Enum.filter(orders, &(&1.status == "preparing"))
    received = Enum.filter(orders, &(&1.status == "received"))

    sort_newest = fn list ->
      Enum.sort_by(list, & &1.inserted_at, {:desc, DateTime})
    end

    sort_newest.(ready) ++ sort_newest.(preparing) ++ sort_newest.(received)
  end

  defp history_my_orders(orders) do
    orders
    |> Enum.filter(&(&1.status == "completed"))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp my_orders_trigger_label(orders) do
    active = active_my_orders(orders)
    count = length(active)

    cond do
      Enum.any?(active, &(&1.status == "ready")) ->
        "#{my_orders_title(count)} · Ready"

      Enum.any?(active, &(&1.status == "preparing")) ->
        "#{my_orders_title(count)} · Preparing"

      Enum.any?(active, &my_order_unpaid?/1) ->
        "#{my_orders_title(count)} · Pay"

      active != [] ->
        if count == 1, do: "My Order", else: "My Orders · #{count} active"

      true ->
        "My Orders"
    end
  end

  defp my_orders_title(1), do: "My Order"
  defp my_orders_title(_), do: "My Orders"

  defp my_orders_trigger_status?(orders) do
    active = active_my_orders(orders)

    Enum.any?(active, &(&1.status in ["ready", "preparing"])) or
      Enum.any?(active, &my_order_unpaid?/1) or
      length(active) > 1
  end

  defp my_orders_trigger_aria(orders) do
    active_count = length(active_my_orders(orders))
    history_count = length(history_my_orders(orders))
    label = my_orders_trigger_label(orders)

    "#{label}, #{active_count} active, #{history_count} in history"
  end

  defp show_floating_my_orders?(my_orders, my_orders_open?, basket_open?, detail) do
    my_orders != [] and not my_orders_open? and not basket_open? and is_nil(detail)
  end

  # Customer-facing My Orders labels only — DB status remains unchanged.
  defp customer_my_order_status_label(%{status: "ready"}), do: "Ready — come to counter"
  defp customer_my_order_status_label(%{status: "completed"}), do: "Picked up ✓"
  defp customer_my_order_status_label(%{status: "preparing"}), do: "Preparing"

  defp customer_my_order_status_label(%{payment_status: "awaiting_payment"}),
    do: "Waiting for payment"

  defp customer_my_order_status_label(%{payment_status: "unpaid", payment_method: "counter"}),
    do: "Pay at counter"

  defp customer_my_order_status_label(%{payment_status: "unpaid"}), do: "Unpaid"
  defp customer_my_order_status_label(%{status: "received"}), do: "Received"
  defp customer_my_order_status_label(%{status: status}), do: Orders.status_label(status)

  defp my_order_status_class(%{status: "ready"}), do: "menu-my-orders-status--ready"
  defp my_order_status_class(%{status: "completed"}), do: "menu-my-orders-status--done"
  defp my_order_status_class(%{status: "preparing"}), do: "menu-my-orders-status--preparing"

  defp my_order_status_class(%{payment_status: status})
       when status in ["awaiting_payment", "unpaid"],
       do: "menu-my-orders-status--unpaid"

  defp my_order_status_class(_), do: "menu-my-orders-status--received"

  defp my_order_unpaid?(%{payment_status: status}) when status in ["awaiting_payment", "unpaid"],
    do: true

  defp my_order_unpaid?(_), do: false
  defp sanitize_restored_cart(%{"cart" => lines}, categories) when is_list(lines) do
    lines
    |> Enum.flat_map(&sanitize_restored_line(&1, categories))
    |> Enum.take(40)
  end

  defp sanitize_restored_cart(lines, categories) when is_list(lines) do
    lines
    |> Enum.flat_map(&sanitize_restored_line(&1, categories))
    |> Enum.take(40)
  end

  defp sanitize_restored_cart(_, _), do: []

  defp sanitize_restored_line(line, categories) when is_map(line) do
    with product_id when is_integer(product_id) and product_id > 0 <-
           parse_positive_int(Map.get(line, "product_id") || Map.get(line, :product_id)),
         quantity when is_integer(quantity) and quantity >= 1 and quantity <= 99 <-
           parse_positive_int(Map.get(line, "quantity") || Map.get(line, :quantity)),
         %Decimal{} = price <-
           parse_money(Map.get(line, "price") || Map.get(line, :price)),
         name when is_binary(name) and name != "" <-
           normalize_restored_string(Map.get(line, "name") || Map.get(line, :name)),
         {category, product} <- find_product_with_category(categories, product_id),
         true <- product.available == true,
         true <- product.name == name do
      size = normalize_restored_size(Map.get(line, "size") || Map.get(line, :size))

      image =
        case normalize_restored_image(Map.get(line, "image") || Map.get(line, :image)) do
          nil -> Menu.product_image(category.name, product.name)
          path -> path
        end

      key =
        case Map.get(line, "key") || Map.get(line, :key) do
          key when is_binary(key) and key != "" -> key
          _ -> "#{product_id}:#{:erlang.phash2({name, size, Decimal.to_string(price)})}"
        end

      [
        %{
          key: key,
          product_id: product_id,
          name: name,
          size: size,
          price: price,
          quantity: quantity,
          image: image
        }
      ]
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp sanitize_restored_line(_, _), do: []

  defp parse_positive_int(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp parse_positive_int(_), do: nil

  defp parse_money(%Decimal{} = price), do: price

  defp parse_money(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {price, ""} -> price
      {_price, _rest} -> nil
      :error -> nil
    end
  end

  defp parse_money(value) when is_integer(value) and value >= 0, do: Decimal.new(value)

  defp parse_money(value) when is_float(value) and value >= 0 do
    value |> Float.to_string() |> Decimal.new()
  rescue
    _ -> nil
  end

  defp parse_money(_), do: nil

  defp normalize_restored_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_restored_string(_), do: nil

  defp normalize_restored_size(nil), do: nil
  defp normalize_restored_size(""), do: nil

  defp normalize_restored_size(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_restored_size(_), do: nil

  defp normalize_restored_image(value) when is_binary(value) do
    trimmed = String.trim(value)

    if String.starts_with?(trimmed, "/images/") do
      trimmed
    else
      nil
    end
  end

  defp normalize_restored_image(_), do: nil

  defp show_floating_bag?(cart, basket_open?, detail) do
    cart != [] && not basket_open? && is_nil(detail)
  end

  defp floating_bag_items_label(cart) do
    if cart_count(cart) == 1, do: "item", else: "items"
  end

  defp floating_bag_label(cart) do
    "Your order, #{cart_count(cart)} #{floating_bag_items_label(cart)}, #{Menu.format_price(cart_total(cart))}, view order"
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

  defp category_nav_label("HOT"), do: "Hot coffee"
  defp category_nav_label("COLD"), do: "Iced coffee"
  defp category_nav_label("FRAPPE"), do: "Frappe"
  defp category_nav_label("SODA"), do: "Soda"
  defp category_nav_label("FOOD"), do: "Food"
  defp category_nav_label(name), do: name

  defp menu_section_title(:matcha, category_name), do: craving_label(category_name)
  defp menu_section_title(:sweets, _category_name), do: "Sweets"
  defp menu_section_title(_, category_name), do: category_nav_label(category_name)

  defp craving_label("HOT"), do: "Hot coffee"
  defp craving_label("COLD"), do: "Iced coffee"
  defp craving_label("FRAPPE"), do: "Frappe"
  defp craving_label("SODA"), do: "Soda"
  defp craving_label("FOOD"), do: "Food"
  defp craving_label(name), do: category_nav_label(name)

  defp temperature_badge("HOT"), do: %{label: "Hot", tone: "hot"}
  defp temperature_badge("COLD"), do: %{label: "Iced", tone: "iced"}
  defp temperature_badge(_), do: nil

  defp menu_craving_chips(categories) do
    all_chip = %{
      key: "ALL",
      label: "All",
      event: "select_category",
      name: "ALL",
      id: nil,
      thumb: "/images/coffeespot/IMG_3498.png",
      kind: :all
    }

    category_chips =
      Enum.map(craving_options(), fn option ->
        case option do
          %{filter: nil, category: category, label: label, image: image} ->
            %{
              key: category,
              label: label,
              event: "select_category",
              name: category,
              id: nil,
              thumb: qr_nav_thumb(categories, category, image),
              kind: :category
            }

          %{filter: filter, id: id, label: label, image: image}
          when filter in [:matcha, :sweets] ->
            %{
              key: id,
              label: label,
              event: "select_craving",
              name: nil,
              id: id,
              thumb: image,
              kind: :filter
            }
        end
      end)

    [all_chip | category_chips]
  end

  defp qr_nav_thumb(categories, category_name, fallback_image) do
    case Enum.find(categories, &(&1.name == category_name)) do
      nil -> fallback_image
      category -> craving_thumb(category)
    end
  end

  defp chip_active?(%{kind: :filter, id: "matcha"}, _selected, :matcha), do: true
  defp chip_active?(%{kind: :filter, id: "sweets"}, _selected, :sweets), do: true
  defp chip_active?(%{kind: :all}, "ALL", nil), do: true
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

  defp apply_menu_stage_param(socket, params) do
    case Map.get(params, "stage") do
      "craving" ->
        socket
        |> assign(:menu_stage, :craving)
        |> assign(:selected_category, default_category(socket.assigns.categories))
        |> clear_transient_menu_state()

      "visit" ->
        socket
        |> assign(:menu_stage, :visit)
        |> assign(:selected_category, default_category(socket.assigns.categories))
        |> clear_transient_menu_state()

      "menu" ->
        socket
        |> assign(:menu_stage, :menu)
        |> clear_transient_menu_state()
        |> apply_menu_browse_param(params)
        |> maybe_restore_menu_chip_visibility(params)

      _ ->
        socket
        |> assign(:menu_stage, :landing)
        |> assign(:selected_category, default_category(socket.assigns.categories))
        |> clear_transient_menu_state()
    end
  end

  defp clear_transient_menu_state(socket) do
    socket
    |> assign(:menu_filter, nil)
    |> assign(:search, "")
    |> assign(:search_open?, false)
    |> assign(:detail, nil)
    |> assign(:detail_closing?, false)
    |> assign(:basket_open?, false)
    |> assign(:basket_closing?, false)
  end

  defp apply_menu_browse_param(socket, params) do
    filter = parse_menu_filter(Map.get(params, "filter"))
    category = Map.get(params, "category")

    case filter do
      :matcha ->
        selected =
          socket.assigns.categories
          |> filter_matcha_categories()
          |> List.first()
          |> case do
            %{name: name} -> name
            _ -> socket.assigns.selected_category
          end

        socket
        |> assign(:menu_filter, :matcha)
        |> assign(:selected_category, selected)

      :sweets ->
        socket
        |> assign(:menu_filter, :sweets)
        |> assign(:selected_category, "FOOD")

      nil ->
        selected = valid_category(socket.assigns.categories, category)

        socket
        |> assign(:menu_filter, nil)
        |> assign(:selected_category, selected)
    end
  end

  defp maybe_restore_menu_chip_visibility(socket, params) do
    if connected?(socket) do
      chip_id =
        case parse_menu_filter(Map.get(params, "filter")) do
          :matcha -> "menu-craving-chip-matcha"
          :sweets -> "menu-craving-chip-sweets"
          nil -> chip_id_for_category(Map.get(params, "category") || socket.assigns.selected_category)
        end

      socket =
        if chip_id do
          push_event(socket, "scroll_active_chip", %{id: chip_id})
        else
          socket
        end

      push_event(socket, "scroll_to_menu_content", %{})
    else
      socket
    end
  end

  defp chip_id_for_category(category)
       when category in ["ALL", "HOT", "COLD", "FRAPPE", "SODA", "FOOD"] do
    "menu-craving-chip-#{category}"
  end

  defp chip_id_for_category(_category), do: nil

  defp valid_category(_categories, "ALL"), do: "ALL"

  defp valid_category(categories, category) when is_binary(category) do
    if Enum.any?(categories, &(&1.name == category)), do: category, else: default_category(categories)
  end

  defp valid_category(categories, _category), do: default_category(categories)

  defp default_category(categories) do
    cond do
      Enum.any?(categories, &(&1.name == "HOT")) -> "HOT"
      true -> categories |> List.first() |> then(&(&1 && &1.name))
    end
  end

  defp parse_menu_filter("matcha"), do: :matcha
  defp parse_menu_filter("sweets"), do: :sweets
  defp parse_menu_filter(_), do: nil

  defp search_active?(search) when is_binary(search), do: String.trim(search) != ""
  defp search_active?(_), do: false

  defp menu_path(socket, stage, opts \\ []) do
    params = build_menu_query(socket, stage, opts)

    if params == %{} do
      ~p"/menu"
    else
      ~p"/menu?#{params}"
    end
  end

  defp craving_option_path(socket, option) do
    case option do
      %{filter: :matcha} ->
        menu_path(socket, :menu, filter: :matcha)

      %{filter: :sweets, category: category} ->
        menu_path(socket, :menu, category: category, filter: :sweets)

      %{filter: nil, category: category} when is_binary(category) ->
        menu_path(socket, :menu, category: category, filter: nil)

      _ ->
        menu_path(socket, :menu)
    end
  end

  defp build_menu_query(socket, stage, opts) do
    filter = Keyword.get(opts, :filter, :__unset__)
    category = Keyword.get(opts, :category, :__unset__)

    %{}
    |> maybe_put_table(socket.assigns.table_number)
    |> maybe_put_stage(stage, category, filter, socket)
  end

  defp maybe_put_table(params, table) when table in [nil, ""], do: params

  defp maybe_put_table(params, table) do
    case Integer.parse(to_string(table)) do
      {n, ""} when n in 1..99 -> Map.put(params, "table", Integer.to_string(n))
      _ -> params
    end
  end

  defp maybe_put_stage(params, :landing, _category, _filter, _socket), do: params

  defp maybe_put_stage(params, stage, category, filter, socket) do
    params = Map.put(params, "stage", Atom.to_string(stage))

    if stage == :menu do
      params
      |> maybe_put_menu_category(category, filter, socket)
      |> maybe_put_menu_filter(filter, socket)
    else
      params
    end
  end

  defp maybe_put_menu_category(params, :__unset__, :__unset__, socket) do
    if socket.assigns.selected_category do
      Map.put(params, "category", socket.assigns.selected_category)
    else
      params
    end
  end

  defp maybe_put_menu_category(params, :__unset__, filter, _socket) when filter != :__unset__ do
    params
  end

  defp maybe_put_menu_category(params, category, _filter, _socket) when is_binary(category) do
    Map.put(params, "category", category)
  end

  defp maybe_put_menu_category(params, _category, _filter, _socket), do: params

  defp maybe_put_menu_filter(params, :__unset__, socket) do
    case socket.assigns.menu_filter do
      nil -> params
      filter -> Map.put(params, "filter", Atom.to_string(filter))
    end
  end

  defp maybe_put_menu_filter(params, nil, _socket), do: params

  defp maybe_put_menu_filter(params, filter, _socket) when filter in [:matcha, :sweets] do
    Map.put(params, "filter", Atom.to_string(filter))
  end

  defp maybe_put_menu_filter(params, _filter, _socket), do: params

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

  defp unavailable_toast([name]), do: "#{name} is no longer available. Update your order and try again."

  defp unavailable_toast(names) when is_list(names) do
    "#{Enum.join(names, ", ")} are no longer available. Update your order and try again."
  end

  defp place_counter_order(socket) do
    socket = assign(socket, :placing_order?, true)

    case Orders.create_order(socket.assigns.cart, order_attrs(socket, :counter)) do
      {:ok, order} ->
        {:noreply, finalize_counter_order(socket, order)}

      {:error, {:unavailable, names}} ->
        {:noreply, order_failure(socket, unavailable_toast(names))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, checkout_errors_from_changeset(changeset))}

      {:error, _} ->
        {:noreply, order_failure(socket, "Could not place order — try again")}
    end
  end

  defp place_qrph_order(socket, _channel) do
    socket = assign(socket, :placing_order?, true)

    case Orders.create_order(socket.assigns.cart, order_attrs(socket, :online)) do
      {:ok, order} ->
        {:noreply, finalize_counter_order(socket, order)}

      {:error, {:unavailable, names}} ->
        {:noreply, order_failure(socket, unavailable_toast(names))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, checkout_errors_from_changeset(changeset))}

      {:error, _} ->
        {:noreply, order_failure(socket, "Could not place order — try again")}
    end
  end

  defp place_online_order(socket, channel) do
    socket = assign(socket, :placing_order?, true)

    case Orders.create_order(socket.assigns.cart, order_attrs(socket, :online)) do
      {:ok, order} ->
        finish_online_checkout(socket, order, channel)

      {:error, {:unavailable, names}} ->
        {:noreply, order_failure(socket, unavailable_toast(names))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, checkout_errors_from_changeset(changeset))}

      {:error, _} ->
        {:noreply, order_failure(socket, "Could not place order — try again")}
    end
  end

  defp finish_online_checkout(socket, order, channel) do
    return_urls = checkout_return_urls(order)

    case begin_online_checkout_session(order, socket.assigns.cart, channel, return_urls) do
      {:ok, checkout_url} ->
        {:noreply,
         socket
         |> assign(:cart, [])
         |> assign(:basket_open?, false)
         |> assign(:basket_closing?, false)
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, %{})
         |> remember_my_order(order)
         |> push_event("clear_persisted_cart", %{})
         |> push_event("persist_my_order", %{number: order.number})
         |> redirect(external: checkout_url)}

      {:error, _} ->
        _ = compensate_failed_online_checkout(order)

        {:noreply,
         order_failure(socket, "Could not start online payment — try again or pay at counter")}
    end
  end

  defp begin_online_checkout_session(order, cart, channel, return_urls) do
    with {:ok, %{id: session_id, checkout_url: checkout_url}} <-
           PayMongo.create_checkout_session(order, cart,
             channel: channel,
             success_url: return_urls.success_url,
             cancel_url: return_urls.cancel_url
           ),
         {:ok, _order} <- Orders.attach_paymongo_session(order, session_id) do
      {:ok, checkout_url}
    end
  end

  # If PayMongo checkout or session attach fails after create_order, remove the
  # unpaid online ticket from the KDS. Prefer cancel; if a session is already
  # bound, abandon so ESP-83/85 session retention stays intact.
  defp compensate_failed_online_checkout(order) do
    case Orders.cancel_order(order) do
      {:ok, cancelled} ->
        {:ok, cancelled}

      {:error, :checkout_in_progress} ->
        Orders.abandon_online_payment(order)

      {:error, _} = error ->
        error
    end
  end

  defp finalize_counter_order(socket, order) do
    socket
    |> assign(:cart, [])
    |> assign(:basket_open?, false)
    |> assign(:basket_closing?, false)
    |> assign(:placing_order?, false)
    |> assign(:checkout_errors, %{})
    |> remember_my_order(order)
    |> push_event("clear_persisted_cart", %{})
    |> push_event("persist_my_order", %{number: order.number})
    |> push_navigate(to: ~p"/order/#{order.number}?confirm=1")
  end

  defp order_failure(socket, message) do
    socket
    |> assign(:placing_order?, false)
    |> assign(:checkout_errors, %{})
    |> assign(:toast, message)
    |> then(fn s ->
      Process.send_after(self(), :clear_toast, 3200)
      s
    end)
  end

  defp order_attrs(socket, payment_method) do
    wallet =
      case socket.assigns.payment_method do
        channel when channel in [:gcash, :maya] -> channel
        _ -> nil
      end

    attrs = %{
      customer_name: socket.assigns.customer_name,
      fulfillment: socket.assigns.fulfillment,
      table_number: socket.assigns.table_number,
      notes: socket.assigns.notes,
      payment_method: payment_method
    }

    if payment_method == :online and wallet do
      Map.put(attrs, :online_wallet, wallet)
    else
      attrs
    end
  end

  defp checkout_return_urls(order) do
    %{
      success_url: url(~p"/order/#{order.number}?confirm=1"),
      cancel_url: url(~p"/order/#{order.number}?payment=cancelled")
    }
  end

  defp checkout_button_label(:counter, true, _mode), do: "Placing order…"
  defp checkout_button_label(:gcash, true, "qrph_manual"), do: "Starting…"
  defp checkout_button_label(:maya, true, "qrph_manual"), do: "Starting…"
  defp checkout_button_label(:gcash, true, _mode), do: "Starting GCash…"
  defp checkout_button_label(:maya, true, _mode), do: "Starting Maya…"
  defp checkout_button_label(:counter, false, _mode), do: "Place order"
  defp checkout_button_label(:gcash, false, "qrph_manual"), do: "Place order"
  defp checkout_button_label(:maya, false, "qrph_manual"), do: "Place order"
  defp checkout_button_label(:gcash, false, _mode), do: "Continue to GCash"
  defp checkout_button_label(:maya, false, _mode), do: "Continue to Maya"

  defp resolve_payment_method("gcash", mode, true, _maya) when mode in ["paymongo", "qrph_manual"],
    do: :gcash

  defp resolve_payment_method("maya", mode, _gcash, true) when mode in ["paymongo", "qrph_manual"],
    do: :maya

  defp resolve_payment_method(_, _, _, _), do: :counter

  defp wallet_pay_available?(%{payments_mode: "paymongo"}, :gcash), do: true
  defp wallet_pay_available?(%{payments_mode: "paymongo"}, :maya), do: true

  defp wallet_pay_available?(%{payments_mode: "qrph_manual", gcash_qrph_path: path}, :gcash)
       when is_binary(path) and path != "",
       do: true

  defp wallet_pay_available?(%{payments_mode: "qrph_manual", maya_qrph_path: path}, :maya)
       when is_binary(path) and path != "",
       do: true

  defp wallet_pay_available?(_, _), do: false

  defp pay_option_count(gcash?, maya?) do
    1 + if(gcash?, do: 1, else: 0) + if(maya?, do: 1, else: 0)
  end

  defp payment_checkout_note(:counter, _), do: "Pay at the counter when your order is ready."

  defp payment_checkout_note(:gcash, "paymongo"),
    do: "Continue to PayMongo to complete payment."

  defp payment_checkout_note(:maya, "paymongo"),
    do: "Continue to PayMongo to complete payment."

  defp payment_checkout_note(:gcash, "qrph_manual"),
    do: "Scan QR at counter after this."

  defp payment_checkout_note(:maya, "qrph_manual"),
    do: "Scan QR at counter after this."

  defp payment_checkout_note(_, _), do: "Pay at the counter when your order is ready."
end

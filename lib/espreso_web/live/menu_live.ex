defmodule EspresoWeb.MenuLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot
  alias Espreso.Customers
  alias Espreso.Loyalty
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.BusinessSettings
  alias Espreso.PayMongo
  alias Espreso.Shifts
  alias Espreso.Tenancy

  @impl true
  def mount(params, _session, socket) do
    case put_menu_branch(params) do
      {:error, :not_found} ->
        {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/menu")}

      _ ->
        mount_menu(socket)
    end
  end

  defp mount_menu(socket) do
    categories = Menu.list_menu()
    selected = default_category(categories)

    payment_config = BusinessSettings.payment_config()

    {:ok,
     socket
     |> assign(:page_title, "Menu")
     |> assign(:coffeespot_guest?, Tenancy.coffeespot_guest?())
     |> assign(:lilac_guest?, Tenancy.lilac_guest?())
     |> assign(:guest_brand_name, CoffeeSpot.business_name())
     |> assign(:payments_mode, payment_config.payments_mode)
     |> assign(:gcash_pay_available?, wallet_pay_available?(payment_config, :gcash))
     |> assign(:maya_pay_available?, wallet_pay_available?(payment_config, :maya))
     |> assign(:menu_stage, :landing)
     |> assign(:visit_return, :landing)
     |> assign(:menu_filter, nil)
     |> assign(:categories, categories)
     |> assign(:signature_feature, Menu.find_signature_product(categories))
     |> assign(:selected_category, selected)
     |> assign(:search, "")
     |> assign(:search_open?, true)
     |> assign(:saved_product_ids, MapSet.new())
     |> assign(:saved_open?, false)
     |> assign(:cart, [])
     |> assign(:basket_open?, false)
     |> assign(:basket_closing?, false)
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)
     |> assign(:toast, nil)
     |> assign(:basket_pulse?, false)
     |> assign(:bag_add_delta, nil)
     |> assign(:bag_fly_n, 0)
     |> assign(:fulfillment, :dine_in)
     |> assign(:fulfillment_touched?, false)
     |> assign(:table_number, "")
     |> assign(:customer_name, "")
     |> assign(:loyalty_phone, "")
     |> assign(:rewards_phone, "")
     |> assign(:rewards_remembered_phone, nil)
     |> assign(:notes, "")
     |> assign(:checkout_errors, %{})
     |> assign(:payment_method, :counter)
     |> assign(:payment_touched?, false)
     |> assign(:placing_order?, false)
     |> assign(:shop_day_status, Shifts.shop_day_status())
     |> assign(:my_orders, [])
     |> assign(:my_orders_open?, false)
     |> assign(:my_orders_tab, :orders)
     |> assign(:my_orders_rewards, %{kind: :prompt}), layout: false}
  end

  defp put_menu_branch(%{"tenant_slug" => tenant_slug, "branch_slug" => branch_slug})
       when is_binary(tenant_slug) and is_binary(branch_slug) do
    Tenancy.put_guest_tenant_branch(tenant_slug, branch_slug)
  end

  defp put_menu_branch(%{"tenant_slug" => tenant_slug}) when is_binary(tenant_slug) do
    Tenancy.put_guest_tenant(tenant_slug)
  end

  defp put_menu_branch(%{"branch_slug" => slug}) when is_binary(slug) do
    Tenancy.put_guest_branch(slug)
  end

  defp put_menu_branch(_params) do
    Tenancy.put_lilac_context()
    :ok
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case put_menu_branch(params) do
      {:error, :not_found} ->
        {:noreply, Phoenix.LiveView.redirect(socket, to: ~p"/menu")}

      _ ->
        {:noreply,
         socket
         |> apply_table_param(params)
         |> apply_menu_stage_param(params)}
    end
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

  def handle_info(:clear_bag_pulse, socket) do
    {:noreply,
     socket
     |> assign(:basket_pulse?, false)
     |> assign(:bag_add_delta, nil)}
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
        {:noreply,
         socket
         |> update_my_order_summary(existing, order)
         |> maybe_toast_order_cancelled(existing, order)}
    end
  end

  @impl true
  def handle_event("enter_menu", _params, socket) do
    socket = assign(socket, :visit_return, :landing)
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
    socket = assign(socket, :visit_return, :menu)
    {:noreply, push_patch(socket, to: menu_path(socket, :visit))}
  end

  def handle_event("leave_visit", _params, socket) do
    target =
      if socket.assigns.visit_return == :menu do
        menu_path(socket, :menu)
      else
        menu_path(socket, :landing)
      end

    {:noreply,
     socket
     |> assign(:visit_return, :landing)
     |> push_patch(to: target)}
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

  def handle_event("swipe_category", %{"dir" => dir}, socket) when dir in ["next", "prev"] do
    cond do
      not category_swipe_enabled?(socket.assigns) ->
        {:noreply, socket}

      true ->
        case neighbor_menu_chip(socket.assigns, dir) do
          nil ->
            {:noreply, socket}

          chip ->
            {:noreply,
             apply_menu_chip(socket, chip, scroll_content: false, chip_behavior: "smooth")}
        end
    end
  end

  def handle_event("swipe_category", _params, socket), do: {:noreply, socket}

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
     |> assign(:search_open?, true)}
  end

  def handle_event("toggle_save", %{"id" => id}, socket) do
    {:noreply, toggle_saved_product(socket, id)}
  end

  def handle_event("open_saved", _params, socket) do
    {:noreply,
     if socket.assigns.saved_open? do
       assign(socket, :saved_open?, false)
     else
       socket
       |> assign(:saved_open?, true)
       |> assign(:my_orders_open?, false)
       |> assign(:basket_open?, false)
       |> assign(:basket_closing?, false)
       |> assign(:detail, nil)
       |> assign(:detail_closing?, false)
       |> assign(:basket_pulse?, false)
       |> assign(:bag_add_delta, nil)
     end}
  end

  def handle_event("close_saved", _params, socket) do
    {:noreply, assign(socket, :saved_open?, false)}
  end

  def handle_event("menu_home", _params, socket) do
    {:noreply,
     socket
     |> assign(:saved_open?, false)
     |> assign(:my_orders_open?, false)
     |> assign(:basket_open?, false)
     |> assign(:basket_closing?, false)
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)
     |> assign(:search, "")
     |> push_patch(to: menu_path(socket, :menu, category: "ALL", filter: nil))
     |> push_event("scroll_active_chip", %{id: "menu-craving-chip-ALL"})
     |> push_event("scroll_to_menu_content", %{})}
  end

  def handle_event("focus_categories", _params, socket) do
    chip_id =
      cond do
        socket.assigns.menu_filter == :matcha -> "menu-craving-chip-matcha"
        socket.assigns.menu_filter == :sweets -> "menu-craving-chip-sweets"
        true -> "menu-craving-chip-#{socket.assigns.selected_category || "ALL"}"
      end

    {:noreply, push_event(socket, "scroll_active_chip", %{id: chip_id})}
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
     |> assign(:saved_open?, false)
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
    phone = Map.get(params, "loyalty_phone", socket.assigns.loyalty_phone)

    {:noreply,
     socket
     |> assign(:customer_name, name)
     |> assign(:table_number, table)
     |> assign(:loyalty_phone, phone)
     |> assign(:checkout_errors, %{})
     |> put_payment_method_from_params(params)}
  end

  def handle_event("validate_checkout", _params, socket) do
    {:noreply, assign(socket, :checkout_errors, checkout_errors(socket.assigns))}
  end

  def handle_event("set_payment_method", params, socket) do
    {:noreply, put_payment_method_from_params(socket, params)}
  end

  def handle_event("place_order", _params, socket) do
    errors = checkout_errors(socket.assigns)

    cond do
      socket.assigns.cart == [] ->
        {:noreply, socket}

      socket.assigns.placing_order? ->
        {:noreply, socket}

      socket.assigns.shop_day_status != :open ->
        {:noreply, order_failure(socket, shop_day_menu_message(socket.assigns.shop_day_status))}

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

  def handle_event("restore_loyalty_phone", params, socket) do
    phone =
      Map.get(params, "phone") || Map.get(params, :phone) || ""

    {:noreply, apply_restored_loyalty_phone(socket, phone)}
  end

  def handle_event("toggle_my_orders", params, socket) do
    open_my_orders(socket, Map.get(params, "tab", "orders"))
  end

  def handle_event("open_my_orders", params, socket) do
    open_my_orders(socket, Map.get(params, "tab", "orders"))
  end

  def handle_event("close_my_orders", _params, socket) do
    {:noreply,
     socket
     |> assign(:my_orders_open?, false)
     |> assign(:my_orders_tab, :orders)}
  end

  def handle_event("set_my_orders_tab", %{"tab" => tab}, socket) do
    tab = my_orders_tab(tab)

    socket =
      if tab == :rewards do
        refresh_my_orders_rewards(socket)
      else
        socket
      end

    {:noreply, assign(socket, :my_orders_tab, tab)}
  end

  def handle_event("update_rewards_phone", params, socket) do
    phone = Map.get(params, "rewards_phone", socket.assigns.rewards_phone)

    {:noreply,
     socket
     |> assign(:rewards_phone, phone)
     |> then(fn s ->
       case s.assigns.my_orders_rewards do
         %{kind: :not_found} -> assign(s, :my_orders_rewards, %{kind: :prompt})
         _ -> s
       end
     end)}
  end

  def handle_event("lookup_rewards", params, socket) do
    phone =
      Map.get(params, "rewards_phone") ||
        Map.get(params, "loyalty_phone") ||
        socket.assigns.rewards_phone

    {:noreply, lookup_rewards_phone(socket, phone)}
  end

  def handle_event("clear_rewards_phone", _params, socket) do
    {:noreply,
     socket
     |> assign(:rewards_phone, "")
     |> assign(:rewards_remembered_phone, nil)
     |> assign(:my_orders_rewards, %{kind: :prompt})
     |> push_event("clear_loyalty_phone", %{})
     |> refresh_my_orders_rewards()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="menu-page"
      phx-hook="MenuBrowse"
      data-cart={Jason.encode!(cart_storage_payload(@cart))}
      data-bag-fly={@bag_fly_n}
      class={[
        "menu-live-root",
        @menu_stage in [:menu, :visit] && "menu-live-root--glass",
        @menu_stage not in [:menu, :visit] && "menu-live-root--qr-entry",
        (@detail || @basket_open? || @my_orders_open? || @saved_open?) && "menu-page-locked"
      ]}
      data-category-swipe={if(category_swipe_enabled?(assigns), do: "1", else: "0")}
    >
      <div
        :if={@menu_stage == :landing}
        id="menu-landing"
        class="menu-qr-landing menu-qr-landing--poster"
      >
        <div class="menu-qr-landing-media" aria-hidden="true">
          <img
            src="/images/coffeespot/landing-latte-paddle.jpg"
            alt=""
            class="menu-qr-landing-photo"
            width="573"
            height="1024"
          />
        </div>
        <div class="menu-qr-landing-scrim" aria-hidden="true"></div>
        <header class="menu-qr-landing-top menu-qr-top" id="menu-landing-top">
          <p class="menu-qr-landing-top-brand menu-qr-top-brand">
            <.guest_brand_mark
              coffeespot?={@coffeespot_guest?}
              name={@guest_brand_name}
              variant="on-dark"
            />
          </p>
        </header>
        <div class="menu-qr-landing-sheet" id="menu-landing-sheet">
          <h1 class="menu-qr-landing-sheet-title">
            Your table.<br /> Our bar.
          </h1>
          <p class="menu-qr-landing-sheet-lede">Scan, order, and we’ll bring it over.</p>
          <button
            type="button"
            id="menu-cta-view-menu"
            class="menu-qr-landing-cta-pill"
            phx-click="enter_menu"
          >
            Get In Now
          </button>
        </div>
      </div>

      <div :if={@menu_stage == :craving} id="menu-craving-chooser" class="menu-qr-craving">
        <div :if={@lilac_guest?} class="menu-qr-craving-bridge" aria-hidden="true">
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
          <p class="menu-qr-craving-brand">
            <.guest_brand_mark coffeespot?={@coffeespot_guest?} name={@guest_brand_name} />
          </p>
          <h1 id="menu-craving-chooser-title" class="menu-qr-craving-title">
            What are you craving?
          </h1>
          <p class="menu-qr-craving-lede">
            {if @coffeespot_guest?,
              do: "Choose something for your CoffeeSpot moment.",
              else: "Choose something from the menu."}
          </p>
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

      <div :if={@menu_stage == :visit} id="menu-visit" class="menu-qr-visit menu-page--glass">
        <div :if={@lilac_guest?} class="menu-qr-visit-bridge" aria-hidden="true">
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
          <button type="button" class="menu-qr-visit-back" phx-click="leave_visit">
            Back
          </button>

          <p class="menu-qr-visit-brand">
            <.guest_brand_mark
              coffeespot?={@coffeespot_guest?}
              name={@guest_brand_name}
              variant="on-dark"
            />
          </p>
          <h1 class="menu-qr-visit-title">{CoffeeSpot.visit_title()}</h1>
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

          <section class="menu-qr-visit-block menu-qr-visit-socials" aria-label="Social">
            <a
              :for={link <- CoffeeSpot.social_links()}
              href={link.href}
              id={"menu-visit-#{link.id}"}
              class={"menu-qr-visit-social menu-qr-visit-social--#{link.id}"}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={CoffeeSpot.social_aria(link.label)}
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

      <div
        :if={@menu_stage == :menu}
        class="menu-page menu-page-brune site-page menu-page--qr menu-page--glass"
      >
        <div id="menu-qr-sticky" class="menu-qr-sticky menu-qr-sticky--glass">
          <header
            id="menu-qr-chrome"
            class="menu-qr-chrome menu-qr-top menu-qr-chrome--glass is-search-open"
          >
            <div class="menu-qr-chrome-bar">
              <button
                type="button"
                id="menu-qr-visit"
                class="menu-qr-visit-btn"
                phx-click="enter_visit"
                aria-label="Visit CoffeeSpot"
              >
                <.icon name="hero-bars-3" class="menu-qr-chrome-icon" />
              </button>
              <p class="menu-qr-chrome-brand menu-qr-top-brand">
                <.guest_brand_mark
                  coffeespot?={@coffeespot_guest?}
                  name={@guest_brand_name}
                  variant="on-dark"
                />
              </p>
            </div>
            <div class="menu-qr-chrome-tools">
              <div id="menu-qr-chrome-leading" class="menu-qr-chrome-leading">
                <div id="menu-search" class="menu-qr-search-inline is-open">
                  <button
                    type="button"
                    id="menu-qr-search-toggle"
                    class="menu-qr-search-inline-toggle"
                    phx-click="toggle_search"
                    aria-label="Search menu"
                    aria-expanded="true"
                    aria-controls="menu-search-input"
                  >
                    <.icon name="hero-magnifying-glass" class="menu-qr-chrome-icon" />
                  </button>

                  <form class="menu-qr-search-inline-form" phx-change="search" phx-submit="search">
                    <div class="menu-qr-search-inline-wrap">
                      <span class="menu-qr-search-inline-icon" aria-hidden="true">
                        <.icon name="hero-magnifying-glass" class="menu-qr-search-inline-glyph" />
                      </span>
                      <input
                        id="menu-search-input"
                        type="text"
                        name="search"
                        value={@search}
                        placeholder="Search menu…"
                        class="menu-qr-search-inline-input"
                        autocomplete="off"
                        phx-debounce="200"
                      />
                      <button
                        type="button"
                        id="menu-qr-search-close"
                        class="menu-qr-search-close menu-qr-search-inline-close"
                        phx-click="clear_search"
                        aria-label="Clear search"
                      >
                        <.icon name="hero-x-mark" class="menu-qr-search-close-icon" />
                      </button>
                    </div>
                  </form>
                </div>
              </div>
              <div id="menu-qr-chrome-trailing" class="menu-qr-chrome-trailing">
                <button
                  type="button"
                  id="menu-qr-category"
                  class="menu-qr-category-btn"
                  phx-click="focus_categories"
                  aria-label="Categories"
                >
                  <.icon name="hero-adjustments-horizontal" class="menu-qr-chrome-icon" />
                </button>
              </div>
            </div>
            <nav
              :if={show_floating_tabbar?(@basket_open?, @detail, @my_orders_open?, @saved_open?)}
              id="menu-craving"
              class="menu-craving menu-craving--header"
              aria-label="Menu categories"
            >
              <div class="menu-craving-rail">
                <button
                  :for={chip <- menu_craving_chips()}
                  type="button"
                  id={"menu-craving-chip-#{chip.key}"}
                  phx-click={chip.event}
                  phx-value-name={chip[:name]}
                  phx-value-id={chip[:id]}
                  class={[
                    "menu-craving-chip",
                    chip_active?(chip, @selected_category, @menu_filter) && "is-active"
                  ]}
                  aria-pressed={to_string(chip_active?(chip, @selected_category, @menu_filter))}
                  aria-current={if(chip_active?(chip, @selected_category, @menu_filter), do: "true")}
                  aria-label={
                    craving_chip_aria_label(
                      chip,
                      chip_active?(chip, @selected_category, @menu_filter)
                    )
                  }
                >
                  <span class="menu-craving-label">{chip.label}</span>
                </button>
              </div>
            </nav>
          </header>
        </div>

        <section class="brune-menu-shell" id="menu">
          <div class="brune-menu-body" id="menu-items">
            <section
              :if={
                show_signature_feature?(
                  @signature_feature,
                  @search,
                  @menu_filter,
                  @selected_category
                )
              }
              id="menu-signature-feature"
              class="menu-signature-feature"
              aria-label="Our signature"
            >
              <% {_signature_category, signature_product} = @signature_feature %>
              <article class="menu-signature-card">
                <button
                  type="button"
                  id={"menu-signature-feature-#{signature_product.id}"}
                  class="menu-signature-card-open"
                  phx-click="open_detail"
                  phx-value-id={signature_product.id}
                  aria-label={signature_product.name}
                >
                  <div class="menu-signature-card-media" aria-hidden="true">
                    <img
                      src="/images/coffeespot/signature-tablea-card-banner.jpg"
                      alt=""
                      class="menu-signature-card-photo"
                      loading="lazy"
                      width="1280"
                      height="720"
                    />
                    <span class="menu-item-rating">
                      <.icon name="hero-star" class="menu-item-rating-icon" />
                    </span>
                  </div>
                </button>
                <button
                  type="button"
                  id={"menu-item-save-#{signature_product.id}"}
                  class={[
                    "menu-item-heart",
                    MapSet.member?(@saved_product_ids, signature_product.id) && "is-on"
                  ]}
                  phx-click="toggle_save"
                  phx-value-id={signature_product.id}
                  aria-pressed={to_string(MapSet.member?(@saved_product_ids, signature_product.id))}
                  aria-label={
                    if(MapSet.member?(@saved_product_ids, signature_product.id),
                      do: "Unsave #{signature_product.name}",
                      else: "Save #{signature_product.name}"
                    )
                  }
                >
                  <.icon
                    name={
                      if(MapSet.member?(@saved_product_ids, signature_product.id),
                        do: "hero-heart-solid",
                        else: "hero-heart"
                      )
                    }
                    class="menu-item-heart-icon"
                  />
                </button>
              </article>
            </section>

            <div
              :if={visible_categories(@categories, @selected_category, @search, @menu_filter) == []}
              id="menu-filter-empty"
              class="menu-filter-empty"
            >
              <p class="menu-filter-empty-title">Nothing here right now</p>
              <p class="menu-filter-empty-lede">
                Try another craving pick, or browse a category below.
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
              <h2
                :if={show_section_title?(@selected_category, @menu_filter, @search)}
                class="brune-menu-category-title"
              >
                {menu_section_title(@menu_filter, category.name)}
              </h2>
              <div :for={group <- category.groups} class="brune-menu-group">
                <p :if={group.name} class="brune-menu-subgroup">{group.name}</p>

                <ul class="brune-menu-items">
                  <li
                    :for={
                      product <-
                        regular_menu_products(
                          group.products,
                          @signature_feature,
                          @search,
                          @menu_filter,
                          @selected_category
                        )
                    }
                    class="brune-menu-item"
                  >
                    <article class="brune-menu-item-card">
                      <button
                        type="button"
                        id={"menu-item-open-#{product.id}"}
                        class="brune-menu-item-open"
                        phx-click="open_detail"
                        phx-value-id={product.id}
                        data-menu-item-name={product.name}
                        aria-label={product.name}
                      >
                        <div class="brune-menu-item-thumb">
                          <img
                            src={Menu.product_image(category.name, product)}
                            alt={product.name}
                            class="brune-menu-item-photo"
                            loading="lazy"
                          />
                          <span class="menu-item-rating" aria-hidden="true">
                            <.icon name="hero-star" class="menu-item-rating-icon" />
                          </span>
                          <span
                            :if={badge = temperature_badge(category.name)}
                            class={"menu-temp-badge menu-temp-badge--#{badge.tone}"}
                          >
                            {badge.label}
                          </span>
                          <span
                            :if={Menu.signature_product?(product.name)}
                            class="menu-signature-item-badge"
                          >
                            ✦ Signature
                          </span>
                        </div>
                        <div class="brune-menu-item-body">
                          <h3 class="brune-menu-item-name">{product.name}</h3>
                          <p class="brune-menu-item-price">{card_price_label(product)}</p>
                        </div>
                      </button>
                      <button
                        type="button"
                        id={"menu-item-save-#{product.id}"}
                        class={[
                          "menu-item-heart",
                          MapSet.member?(@saved_product_ids, product.id) && "is-on"
                        ]}
                        phx-click="toggle_save"
                        phx-value-id={product.id}
                        aria-pressed={to_string(MapSet.member?(@saved_product_ids, product.id))}
                        aria-label={
                          if(MapSet.member?(@saved_product_ids, product.id),
                            do: "Unsave #{product.name}",
                            else: "Save #{product.name}"
                          )
                        }
                      >
                        <.icon
                          name={
                            if(MapSet.member?(@saved_product_ids, product.id),
                              do: "hero-heart-solid",
                              else: "hero-heart"
                            )
                          }
                          class="menu-item-heart-icon"
                        />
                      </button>
                    </article>
                  </li>
                </ul>
              </div>
            </section>
          </div>

          <.brune_student_promo />
          <.brune_hours_strip />
        </section>

        <footer
          class="brune-mega-footer brune-mega-footer--secondary"
          aria-label={"#{@guest_brand_name} footer"}
        >
          <p class="brune-mega-brand">
            <.guest_brand_mark coffeespot?={@coffeespot_guest?} name={@guest_brand_name} />
          </p>
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
              aria-label={CoffeeSpot.social_aria(link.label)}
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
              src={Menu.product_image(@detail.category_name, @detail.product)}
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
            <button
              type="button"
              class="menu-buy-save"
              phx-click="toggle_save"
              phx-value-id={@detail.product.id}
              aria-pressed={to_string(MapSet.member?(@saved_product_ids, @detail.product.id))}
              aria-label={
                if(MapSet.member?(@saved_product_ids, @detail.product.id),
                  do: "Unsave #{@detail.product.name}",
                  else: "Save #{@detail.product.name}"
                )
              }
            >
              <.icon
                name={
                  if(MapSet.member?(@saved_product_ids, @detail.product.id),
                    do: "hero-heart-solid",
                    else: "hero-heart"
                  )
                }
                class="menu-item-heart-icon"
              />
            </button>
          </div>

          <div class="menu-buy-body">
            <div class="menu-detail-heading">
              <h2 id="menu-detail-title" class="menu-detail-name">{@detail.product.name}</h2>
              <p class="menu-detail-price menu-detail-price--sheet">
                {Menu.format_price(selected_price(@detail).price)}
              </p>
            </div>
            <p class="menu-detail-rating" aria-hidden="true">
              <.icon name="hero-star" class="menu-item-rating-icon" />
              <.icon name="hero-star" class="menu-item-rating-icon" />
              <.icon name="hero-star" class="menu-item-rating-icon" />
              <.icon name="hero-star" class="menu-item-rating-icon" />
              <.icon name="hero-star" class="menu-item-rating-icon" />
            </p>

            <p :if={description?(@detail.product.description)} class="menu-detail-description">
              {@detail.product.description}
            </p>
            <p :if={!description?(@detail.product.description)} class="menu-detail-description">
              {if @lilac_guest?,
                do: "Prepared fresh at CoffeeSpot Lilac Marikina.",
                else: "Prepared fresh."}
            </p>

            <div class="menu-detail-options">
              <div :if={detail_multi_size?(@detail)} class="menu-detail-option">
                <p class="menu-detail-label">{detail_option_label(@detail)}</p>
                <div class="menu-size-pills" role="group" aria-label={detail_option_label(@detail)}>
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
              Add to Cart
            </button>
          </footer>
        </aside>
      </div>

      <div :if={@menu_stage == :menu && @toast} class="menu-toast" role="status" aria-live="polite">
        {@toast}
      </div>

      <nav
        :if={
          @menu_stage == :menu &&
            show_floating_tabbar?(@basket_open?, @detail, @my_orders_open?, @saved_open?)
        }
        id="menu-qr-tabbar"
        class="menu-qr-tabbar"
        aria-label="Guest menu"
      >
        <button
          type="button"
          id="menu-qr-home"
          class="menu-qr-tab"
          phx-click="menu_home"
          aria-label="Home"
        >
          <.icon name="hero-home" class="menu-qr-tab-icon" />
          <span class="sr-only">Home</span>
        </button>
        <button
          type="button"
          id="menu-qr-rewards"
          class={[
            "menu-qr-tab",
            "menu-qr-rewards",
            rewards_available?(@my_orders_rewards) && "menu-qr-rewards--available"
          ]}
          phx-click="open_my_orders"
          phx-value-tab="rewards"
          aria-expanded={to_string(@my_orders_open? and @my_orders_tab == :rewards)}
          aria-controls="menu-my-orders-panel"
          aria-label={rewards_trigger_aria(@my_orders_rewards)}
        >
          <.icon name="hero-gift" class="menu-qr-tab-icon" />
          <span class="sr-only">Rewards</span>
          <span
            :if={rewards_available?(@my_orders_rewards)}
            class="menu-qr-rewards-badge"
            aria-hidden="true"
          >
          </span>
        </button>
        <button
          type="button"
          id="menu-qr-my-orders"
          class={[
            "menu-qr-tab",
            "menu-qr-my-orders",
            my_orders_trigger_status?(@my_orders) && "menu-qr-my-orders--status"
          ]}
          phx-click="open_my_orders"
          phx-value-tab="orders"
          aria-expanded={to_string(@my_orders_open? and @my_orders_tab == :orders)}
          aria-controls="menu-my-orders-panel"
          aria-label={my_orders_trigger_aria(@my_orders)}
        >
          <.icon name="hero-clipboard-document-list" class="menu-qr-tab-icon" />
          <span class="sr-only">Orders</span>
        </button>
        <button
          type="button"
          id="menu-qr-saved"
          class={["menu-qr-tab", @saved_open? && "is-active"]}
          phx-click="open_saved"
          aria-expanded={to_string(@saved_open?)}
          aria-controls="menu-saved-panel"
          aria-label="Saved"
        >
          <.icon name="hero-heart" class="menu-qr-tab-icon" />
          <span class="sr-only">Saved</span>
        </button>
        <button
          type="button"
          id="menu-qr-bag"
          class={[
            "menu-qr-tab",
            "menu-qr-chrome-bag",
            "brune-icon-bag",
            @basket_pulse? && "is-bag-confirm"
          ]}
          phx-click="open_basket"
          aria-label={"Your order, #{cart_count(@cart)} items"}
        >
          <.icon name="hero-shopping-bag" class="menu-qr-chrome-bag-icon" />
          <span :if={cart_count(@cart) > 0} class={["brune-bag-count", @basket_pulse? && "is-pulse"]}>
            {cart_count(@cart)}
          </span>
          <span :if={@bag_add_delta} class="menu-qr-bag-plus" aria-hidden="true">
            +{@bag_add_delta}
          </span>
        </button>
      </nav>

      <div
        :if={@menu_stage == :menu && @saved_open?}
        class="menu-my-orders-layer"
        id="menu-saved"
        phx-window-keydown="close_saved"
        phx-key="Escape"
      >
        <button
          type="button"
          class="menu-my-orders-backdrop"
          phx-click="close_saved"
          aria-label="Close saved"
        >
        </button>
        <aside
          id="menu-saved-panel"
          class="menu-my-orders-panel"
          role="dialog"
          aria-modal="true"
          aria-labelledby="menu-saved-title"
        >
          <header class="menu-my-orders-header">
            <div>
              <h2 id="menu-saved-title">Saved</h2>
            </div>
            <button
              type="button"
              class="menu-my-orders-close"
              phx-click="close_saved"
              aria-label="Close saved"
            >
              <.icon name="hero-x-mark" class="menu-my-orders-close-icon" />
            </button>
          </header>
          <div class="menu-saved-body">
            <p
              :if={saved_products(@categories, @saved_product_ids) == []}
              class="menu-my-orders-empty"
            >
              Save drinks with the heart, then find them here.
            </p>
            <ul :if={saved_products(@categories, @saved_product_ids) != []} class="menu-saved-list">
              <li :for={{category, product} <- saved_products(@categories, @saved_product_ids)}>
                <button
                  type="button"
                  id={"menu-saved-item-#{product.id}"}
                  class="menu-saved-item"
                  phx-click="open_detail"
                  phx-value-id={product.id}
                >
                  <img
                    src={Menu.product_image(category.name, product)}
                    alt=""
                    class="menu-saved-thumb"
                  />
                  <span class="menu-saved-copy">
                    <span class="menu-saved-name">{product.name}</span>
                    <span class="menu-saved-price">{card_price_label(product)}</span>
                  </span>
                </button>
              </li>
            </ul>
          </div>
        </aside>
      </div>

      <div
        :if={@menu_stage == :menu && @basket_open?}
        class={[
          "menu-basket-layer",
          "menu-basket-layer--fullscreen",
          @basket_closing? && "is-closing"
        ]}
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

            <h2
              id="menu-basket-title"
              class="menu-basket-title menu-qr-chrome-brand menu-qr-top-brand"
            >
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
                        Takeout
                      </button>
                    </div>
                    <p
                      :if={@fulfillment == :pickup}
                      class="menu-checkout-hint"
                      id="checkout-pickup-hint"
                    >
                      Takeout — pick up at the counter when ready.
                    </p>
                  </fieldset>

                  <div class="menu-checkout-identity">
                    <div class="menu-checkout-field">
                      <label class="menu-checkout-label" for="checkout-name">Name</label>
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
                      <label class="menu-checkout-label" for="checkout-loyalty-phone">
                        Loyalty <span class="menu-checkout-optional">(optional)</span>
                      </label>
                      <input
                        id="checkout-loyalty-phone"
                        type="tel"
                        name="loyalty_phone"
                        value={@loyalty_phone}
                        placeholder="for points"
                        autocomplete="tel"
                        inputmode="tel"
                        class={["menu-checkout-input", @checkout_errors[:loyalty_phone] && "is-error"]}
                        phx-debounce="200"
                      />
                      <p :if={@checkout_errors[:loyalty_phone]} class="menu-checkout-error">
                        {@checkout_errors[:loyalty_phone]}
                      </p>
                    </div>
                  </div>

                  <fieldset
                    :if={@payments_mode != "counter_only"}
                    class="menu-checkout-payment"
                    id="menu-checkout-payment"
                  >
                    <legend class="menu-checkout-label">Pay with</legend>
                    <select
                      id="checkout-pay"
                      name="payment_method"
                      class="menu-checkout-select"
                      aria-label="Payment"
                    >
                      <option value="" disabled selected={!@payment_touched?}>
                        Choose payment
                      </option>
                      <option
                        id="checkout-pay-counter"
                        value="counter"
                        selected={@payment_touched? and @payment_method == :counter}
                      >
                        Cash at counter
                      </option>
                      <option
                        :if={@gcash_pay_available?}
                        id="checkout-pay-gcash"
                        value="gcash"
                        selected={@payment_touched? and @payment_method == :gcash}
                      >
                        GCash
                      </option>
                      <option
                        :if={@maya_pay_available?}
                        id="checkout-pay-maya"
                        value="maya"
                        selected={@payment_touched? and @payment_method == :maya}
                      >
                        Maya
                      </option>
                    </select>
                    <p
                      :if={@payment_touched?}
                      class="menu-checkout-payment-note menu-basket-note"
                      id="checkout-payment-note"
                    >
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
            :if={@shop_day_status != :open}
            id="menu-shop-day-block"
            class="menu-checkout-summary"
            role="status"
          >
            {shop_day_menu_message(@shop_day_status)}
          </p>

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
                disabled={@placing_order? or @shop_day_status != :open}
                data-dismiss-keyboard
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
        :if={
          @menu_stage == :menu && @my_orders_open? &&
            (@my_orders_tab == :rewards or @my_orders != [])
        }
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
              <p class="menu-my-orders-eyebrow">
                <.guest_brand_mark
                  coffeespot?={@coffeespot_guest?}
                  name={@guest_brand_name}
                  variant="on-dark"
                />
              </p>
              <h2 id="menu-my-orders-title">
                <%= if @my_orders_tab == :rewards do %>
                  ELIlai Rewards
                <% else %>
                  My Orders
                <% end %>
              </h2>
            </div>
            <button
              type="button"
              class="menu-my-orders-close"
              phx-click="close_my_orders"
              aria-label={
                if(@my_orders_tab == :rewards, do: "Close rewards", else: "Close my orders")
              }
            >
              Close
            </button>
          </header>

          <div class="menu-my-orders-body">
            <div :if={@my_orders_tab == :orders} id="menu-my-orders-orders">
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
                    <.link navigate={~p"/order/#{order.number}"} class="menu-my-orders-view">
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
                    <p class="menu-my-orders-when">{my_order_history_when(order)}</p>
                    <p class="menu-my-orders-meta">
                      {order.item_count} {if order.item_count == 1, do: "item", else: "items"} · {Menu.format_price(
                        order.total
                      )}
                    </p>
                    <.link navigate={~p"/order/#{order.number}"} class="menu-my-orders-view">
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

            <section
              :if={@my_orders_tab == :rewards}
              id="menu-my-orders-rewards"
              class="menu-my-orders-rewards"
              aria-labelledby="menu-my-orders-title"
            >
              <%= case @my_orders_rewards do %>
                <% %{kind: kind} when kind in [:prompt, :anonymous] -> %>
                  <div
                    class="menu-my-orders-rewards-card menu-my-orders-rewards-card--note"
                    id="menu-rewards-phone-entry"
                  >
                    <p class="menu-my-orders-rewards-note" id="menu-my-orders-rewards-note">
                      Enter your loyalty phone to see your points.
                    </p>
                    <form
                      id="menu-rewards-phone-form"
                      phx-change="update_rewards_phone"
                      phx-submit="lookup_rewards"
                      class="menu-rewards-phone-form"
                    >
                      <label class="menu-checkout-label" for="menu-rewards-phone-input">
                        Loyalty phone
                      </label>
                      <input
                        id="menu-rewards-phone-input"
                        type="tel"
                        name="rewards_phone"
                        value={@rewards_phone}
                        placeholder="09XXXXXXXXX"
                        autocomplete="tel"
                        inputmode="tel"
                        class="menu-checkout-input"
                      />
                      <button
                        type="submit"
                        id="menu-rewards-phone-submit"
                        class="menu-rewards-phone-submit"
                      >
                        Find
                      </button>
                    </form>
                  </div>
                <% %{kind: :not_found} -> %>
                  <div
                    class="menu-my-orders-rewards-card menu-my-orders-rewards-card--note"
                    id="menu-rewards-not-found"
                  >
                    <p class="menu-my-orders-rewards-note" id="menu-my-orders-rewards-note">
                      No rewards account found for that number. Check the phone and try again.
                    </p>
                    <form
                      id="menu-rewards-phone-form"
                      phx-change="update_rewards_phone"
                      phx-submit="lookup_rewards"
                      class="menu-rewards-phone-form"
                    >
                      <label class="menu-checkout-label" for="menu-rewards-phone-input">
                        Loyalty phone
                      </label>
                      <input
                        id="menu-rewards-phone-input"
                        type="tel"
                        name="rewards_phone"
                        value={@rewards_phone}
                        placeholder="09XXXXXXXXX"
                        autocomplete="tel"
                        inputmode="tel"
                        class="menu-checkout-input"
                      />
                      <button
                        type="submit"
                        id="menu-rewards-phone-submit"
                        class="menu-rewards-phone-submit"
                      >
                        Find
                      </button>
                    </form>
                  </div>
                <% %{kind: :ambiguous} -> %>
                  <div class="menu-my-orders-rewards-card menu-my-orders-rewards-card--note">
                    <p class="menu-my-orders-rewards-note" id="menu-my-orders-rewards-note">
                      Rewards are unavailable for these orders.
                    </p>
                  </div>
                <% %{kind: :ready} = rewards -> %>
                  <div class="menu-my-orders-rewards-card">
                    <p class="menu-my-orders-rewards-eyebrow" id="menu-my-orders-rewards-current">
                      Current points
                    </p>
                    <p class="menu-my-orders-rewards-balance" id="menu-my-orders-rewards-balance">
                      <strong>{rewards.balance}</strong> / {rewards.cost} points
                    </p>

                    <div
                      class="menu-my-orders-rewards-progress-block"
                      id="menu-my-orders-rewards-progress-block"
                    >
                      <p class="menu-my-orders-rewards-ratio" id="menu-my-orders-rewards-ratio">
                        {min(rewards.balance, rewards.cost)} / {rewards.cost}
                      </p>
                      <div
                        class="menu-my-orders-rewards-meter"
                        role="progressbar"
                        aria-valuemin="0"
                        aria-valuemax={rewards.cost}
                        aria-valuenow={min(rewards.balance, rewards.cost)}
                        aria-label={"#{min(rewards.balance, rewards.cost)} of #{rewards.cost} points toward a free coffee"}
                      >
                        <div
                          class="menu-my-orders-rewards-meter-fill"
                          style={"width: #{rewards_progress_pct(rewards.balance, rewards.cost)}%"}
                        >
                        </div>
                      </div>

                      <%= if rewards.eligible? do %>
                        <div
                          class="menu-my-orders-rewards-unlocked"
                          id="menu-my-orders-rewards-unlocked"
                        >
                          <p class="menu-my-orders-rewards-status" id="menu-my-orders-rewards-status">
                            <span class="menu-my-orders-rewards-status-icon" aria-hidden="true">
                              <.icon name="hero-gift" class="menu-my-orders-rewards-status-glyph" />
                            </span>
                            Reward Unlocked
                          </p>
                          <p class="menu-my-orders-rewards-reward" id="menu-my-orders-rewards-reward">
                            1 Free Hot or Cold Coffee
                          </p>
                          <p class="menu-my-orders-rewards-note" id="menu-my-orders-rewards-hint">
                            Redeem at the counter.
                          </p>
                        </div>
                      <% else %>
                        <p class="menu-my-orders-rewards-note" id="menu-my-orders-rewards-progress">
                          <%= if rewards.balance == 0 do %>
                            Keep earning to unlock your free coffee.
                          <% else %>
                            {rewards.more} more {points_word(rewards.more)} to unlock your free coffee.
                          <% end %>
                        </p>
                        <p class="menu-my-orders-rewards-earn" id="menu-my-orders-rewards-earn">
                          Earn 1 point for every ₱{loyalty_earn_pesos()} paid.
                        </p>
                      <% end %>
                    </div>

                    <button
                      :if={rewards[:source] == :phone}
                      type="button"
                      id="menu-rewards-clear-phone"
                      class="menu-rewards-clear-phone"
                      phx-click="clear_rewards_phone"
                    >
                      Use a different phone
                    </button>
                  </div>

                  <div
                    :if={rewards.activity != []}
                    class="menu-my-orders-rewards-activity"
                    id="menu-my-orders-rewards-activity"
                  >
                    <h4 class="menu-my-orders-rewards-activity-title">Recent activity</h4>
                    <ul class="menu-my-orders-rewards-activity-list">
                      <li
                        :for={entry <- rewards.activity}
                        class={[
                          "menu-my-orders-rewards-activity-item",
                          "menu-rewards-activity-item",
                          "menu-rewards-activity-item--#{entry.kind}"
                        ]}
                        data-kind={entry.kind}
                      >
                        <p class="menu-rewards-activity-title">{entry.title}</p>
                        <p :if={entry.points_line} class="menu-rewards-activity-points">
                          {entry.points_line}
                        </p>
                        <p class="menu-rewards-activity-detail">{entry.detail}</p>
                        <p :if={entry.when != ""} class="menu-rewards-activity-when">
                          {entry.when}
                        </p>
                      </li>
                    </ul>
                  </div>
              <% end %>
            </section>
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

  defp show_signature_feature?(feature, search, filter, selected_category) do
    match?({_, _}, feature) and not search_active?(search) and is_nil(filter) and
      selected_category in ["ALL", "HOT"]
  end

  defp show_section_title?(selected_category, filter, search) do
    search_active?(search) or filter == :matcha or
      (is_nil(filter) and selected_category == "ALL")
  end

  # When the top featured Signature card is visible, omit that SKU from the
  # regular category list so it does not appear again at the bottom of HOT.
  defp regular_menu_products(products, signature_feature, search, menu_filter, selected_category) do
    if show_signature_feature?(signature_feature, search, menu_filter, selected_category) do
      Enum.reject(products, &Menu.signature_product?(&1.name))
    else
      products
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
          filtered = Enum.filter(group.products, &Menu.sweets_product?/1)
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
        |> assign(:saved_open?, false)
    end
  end

  defp put_product_in_cart(socket, category_name, product, price, qty) do
    cart =
      add_line(
        socket.assigns.cart,
        product,
        price,
        qty,
        category_name,
        Menu.product_image(category_name, product)
      )

    socket =
      socket
      |> assign(:cart, cart)
      |> assign(:detail, nil)
      |> assign(:detail_closing?, false)
      |> assign(:toast, nil)
      |> assign(:basket_pulse?, true)
      |> assign(:bag_add_delta, qty)
      |> assign(:bag_fly_n, Map.get(socket.assigns, :bag_fly_n, 0) + 1)

    Process.send_after(self(), :clear_bag_pulse, 800)
    socket
  end

  defp add_line(cart, product, price, quantity, category_name, image) do
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
              category: category_name,
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
      |> assign(:my_orders_tab, :orders)
      |> assign(:my_orders_rewards, %{kind: :prompt})
  end

  defp extract_my_order_numbers(%{"numbers" => numbers}) when is_list(numbers), do: numbers
  defp extract_my_order_numbers(%{numbers: numbers}) when is_list(numbers), do: numbers

  defp extract_my_order_numbers(%{"number" => number}), do: [number]
  defp extract_my_order_numbers(%{number: number}), do: [number]

  defp extract_my_order_numbers(_), do: []

  defp apply_restored_loyalty_phone(socket, raw) do
    phone = raw |> to_string() |> String.trim()

    case Customers.normalize_phone(phone) do
      {:ok, normalized} ->
        socket
        |> assign(:rewards_remembered_phone, normalized)
        |> assign(:rewards_phone, normalized)
        |> refresh_my_orders_rewards()

      {:error, _} ->
        socket
        |> assign(:rewards_remembered_phone, nil)
        |> push_event("clear_loyalty_phone", %{})
        |> refresh_my_orders_rewards()
    end
  end

  defp lookup_rewards_phone(socket, raw) do
    phone = raw |> to_string() |> String.trim()

    case Customers.get_by_phone(phone) do
      {:ok, customer} ->
        socket
        |> assign(:rewards_phone, customer.phone_e164)
        |> assign(:rewards_remembered_phone, customer.phone_e164)
        |> assign(:my_orders_rewards, ready_rewards(customer, source: :phone))
        |> push_event("persist_loyalty_phone", %{phone: customer.phone_e164})
        |> then(fn s ->
          # Restored-order customer still wins if present.
          refresh_my_orders_rewards(s)
        end)

      {:error, :not_found} ->
        socket
        |> assign(:rewards_phone, phone)
        |> assign(:my_orders_rewards, %{kind: :not_found})

      {:error, :invalid_phone} ->
        socket
        |> assign(:rewards_phone, phone)
        |> assign(:my_orders_rewards, %{kind: :not_found})
    end
  end

  defp maybe_persist_loyalty_phone(socket, order) do
    case Map.get(order, :customer_id) do
      id when is_integer(id) ->
        case Customers.get_customer(id) do
          %Espreso.Customers.Customer{phone_e164: phone} when is_binary(phone) and phone != "" ->
            socket
            |> assign(:rewards_remembered_phone, phone)
            |> push_event("persist_loyalty_phone", %{phone: phone})

          _ ->
            socket
        end

      _ ->
        socket
    end
  end

  defp load_my_orders(socket, numbers) do
    orders = Orders.list_orders_by_numbers(numbers)
    summaries = Enum.map(orders, &my_order_summary/1)

    visible = Enum.take(summaries, 20)

    subscribe_my_orders(socket, visible)

    socket
    |> assign(:my_orders, visible)
    |> push_event("sync_my_orders", %{numbers: Enum.map(visible, & &1.number)})
    |> refresh_my_orders_rewards()
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
      |> Enum.take(20)

    socket
    |> assign(:my_orders, my_orders)
    |> refresh_my_orders_rewards()
  end

  defp update_my_order_summary(socket, existing, order) do
    summary = %{
      existing
      | status: order.status,
        payment_status: order.payment_status || existing.payment_status,
        payment_method: order.payment_method || existing.payment_method,
        total: order.total || existing.total,
        inserted_at: order.inserted_at || existing.inserted_at,
        customer_id: Map.get(order, :customer_id) || existing[:customer_id]
    }

    my_orders =
      socket.assigns.my_orders
      |> Enum.map(fn entry ->
        if entry.id == order.id, do: summary, else: entry
      end)

    socket
    |> assign(:my_orders, my_orders)
    |> refresh_my_orders_rewards()
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
      inserted_at: order.inserted_at,
      customer_id: order.customer_id
    }
  end

  defp refresh_my_orders_rewards(socket) do
    assign(
      socket,
      :my_orders_rewards,
      resolve_my_orders_rewards(socket.assigns.my_orders, socket.assigns.rewards_remembered_phone)
    )
  end

  defp resolve_my_orders_rewards(summaries, remembered_phone) when is_list(summaries) do
    customer_ids =
      summaries
      |> Enum.map(&Map.get(&1, :customer_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case customer_ids do
      [] ->
        resolve_rewards_from_remembered_phone(remembered_phone)

      [customer_id] ->
        case Customers.get_customer(customer_id) do
          %Espreso.Customers.Customer{} = customer ->
            ready_rewards(customer, source: :orders)

          _ ->
            resolve_rewards_from_remembered_phone(remembered_phone)
        end

      _ ->
        %{kind: :ambiguous}
    end
  end

  defp resolve_my_orders_rewards(_, remembered_phone),
    do: resolve_rewards_from_remembered_phone(remembered_phone)

  defp resolve_rewards_from_remembered_phone(phone)
       when is_binary(phone) and phone != "" do
    case Customers.get_by_phone(phone) do
      {:ok, customer} ->
        ready_rewards(customer, source: :phone)

      _ ->
        %{kind: :prompt}
    end
  end

  defp resolve_rewards_from_remembered_phone(_), do: %{kind: :prompt}

  defp ready_rewards(%Espreso.Customers.Customer{} = customer, opts) do
    cost = Loyalty.redeem_cost()
    balance = customer.points_balance
    source = Keyword.get(opts, :source, :orders)

    activity =
      customer.id
      |> Loyalty.list_activity_for_customer(limit: 5)
      |> enrich_rewards_activity()

    %{
      kind: :ready,
      balance: balance,
      cost: cost,
      eligible?: balance >= cost,
      more: max(cost - balance, 0),
      activity: activity,
      source: source,
      phone_e164: customer.phone_e164
    }
  end

  defp enrich_rewards_activity(entries) when is_list(entries) do
    product_ids =
      entries
      |> Enum.filter(&(&1.kind == "redeem"))
      |> Enum.map(&redeem_product_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    products_by_id = load_reward_products(product_ids)

    Enum.map(entries, &rewards_activity_entry(&1, products_by_id))
  end

  defp enrich_rewards_activity(_), do: []

  defp load_reward_products([]), do: %{}

  defp load_reward_products(product_ids) do
    import Ecto.Query

    from(p in Espreso.Menu.Product,
      where: p.id in ^product_ids,
      preload: :category
    )
    |> Espreso.Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp redeem_product_id(%{metadata: %{"product_id" => id}}) when is_integer(id), do: id

  defp redeem_product_id(%{metadata: %{"product_id" => id}}) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp redeem_product_id(_), do: nil

  defp rewards_activity_entry(%{kind: "earn", points: points} = entry, _products)
       when is_integer(points) do
    %{
      kind: "earn",
      title: "+#{points} #{points_word(points)}",
      points_line: nil,
      detail: "Purchase",
      when: rewards_activity_when(entry.inserted_at)
    }
  end

  defp rewards_activity_entry(%{kind: "redeem", points: points} = entry, products)
       when is_integer(points) do
    %{
      kind: "redeem",
      title: "Reward redeemed",
      points_line: format_redeem_points_line(points),
      detail: redeem_activity_detail(entry, products),
      when: rewards_activity_when(entry.inserted_at)
    }
  end

  defp rewards_activity_entry(_, _) do
    %{kind: "other", title: "Loyalty activity", points_line: nil, detail: "", when: ""}
  end

  defp format_redeem_points_line(points) when is_integer(points) and points < 0 do
    "−#{abs(points)} points"
  end

  defp format_redeem_points_line(points) when is_integer(points) do
    "−#{points} points"
  end

  defp format_redeem_points_line(_), do: "−10 points"

  defp redeem_activity_detail(entry, products) do
    case Map.get(products, redeem_product_id(entry)) do
      %{name: name, category: %{name: cat}} when cat in ["HOT", "COLD"] and is_binary(name) ->
        "Free #{String.capitalize(String.downcase(cat))} · #{name}"

      %{name: name} when is_binary(name) and name != "" ->
        "Free #{name}"

      _ ->
        "Free Hot or Cold Coffee"
    end
  end

  defp rewards_activity_when(%DateTime{} = at) do
    manila = DateTime.add(at, 8 * 60 * 60, :second)
    month = Calendar.strftime(manila, "%b")
    "#{month} #{manila.day} · #{format_shop_time(manila)}"
  end

  defp rewards_activity_when(_), do: ""

  defp points_word(1), do: "point"
  defp points_word(n) when is_integer(n) and n < 0, do: "points"
  defp points_word(_), do: "points"

  defp loyalty_earn_pesos do
    div(Loyalty.point_threshold_centavos(), 100)
  end

  defp rewards_progress_pct(balance, cost)
       when is_integer(balance) and is_integer(cost) and cost > 0 do
    balance
    |> min(cost)
    |> max(0)
    |> Kernel.*(100)
    |> div(cost)
  end

  defp rewards_progress_pct(_, _), do: 0

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
    |> Enum.filter(&(&1.status in ["completed", "cancelled"]))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp maybe_toast_order_cancelled(socket, existing, order) do
    if existing.status != "cancelled" and order.status == "cancelled" do
      Process.send_after(self(), :clear_toast, 3200)

      assign(socket, :toast, "#{order.number || existing.number} was cancelled.")
    else
      socket
    end
  end

  defp my_order_history_when(%{inserted_at: %DateTime{} = at}) do
    manila = DateTime.add(at, 8 * 60 * 60, :second)
    shop_today = Orders.shop_date_today()
    order_date = DateTime.to_date(manila)

    cond do
      Date.compare(order_date, shop_today) == :eq ->
        "Today · #{format_shop_time(manila)}"

      Date.compare(order_date, Date.add(shop_today, -1)) == :eq ->
        "Yesterday"

      true ->
        format_shop_date(manila)
    end
  end

  defp my_order_history_when(_), do: ""

  defp format_shop_time(%DateTime{} = manila) do
    manila
    |> Calendar.strftime("%I:%M %p")
    |> String.trim_leading("0")
  end

  defp format_shop_date(%DateTime{} = manila) do
    month = Calendar.strftime(manila, "%b")
    day = manila.day
    year = manila.year
    "#{month} #{day}, #{year}"
  end

  defp open_my_orders(socket, tab) do
    tab = my_orders_tab(tab)

    cond do
      socket.assigns.my_orders_open? and socket.assigns.my_orders_tab == tab ->
        {:noreply,
         socket
         |> assign(:my_orders_open?, false)
         |> assign(:my_orders_tab, :orders)
         |> assign(:basket_pulse?, false)
         |> assign(:bag_add_delta, nil)}

      true ->
        {:noreply,
         socket
         |> assign(:my_orders_open?, true)
         |> assign(:my_orders_tab, tab)
         |> assign(:saved_open?, false)
         |> assign(:basket_pulse?, false)
         |> assign(:bag_add_delta, nil)
         |> refresh_my_orders_rewards()}
    end
  end

  defp my_orders_tab("rewards"), do: :rewards
  defp my_orders_tab(:rewards), do: :rewards
  defp my_orders_tab(_), do: :orders

  defp my_orders_trigger_status?(orders) do
    active = active_my_orders(orders)

    Enum.any?(active, &(&1.status in ["ready", "preparing"])) or
      Enum.any?(active, &my_order_unpaid?/1) or
      length(active) > 1
  end

  defp my_orders_trigger_aria(orders) do
    active_count = length(active_my_orders(orders))
    history_count = length(history_my_orders(orders))

    status =
      cond do
        Enum.any?(active_my_orders(orders), &(&1.status == "ready")) -> "ready"
        Enum.any?(active_my_orders(orders), &(&1.status == "preparing")) -> "preparing"
        Enum.any?(active_my_orders(orders), &my_order_unpaid?/1) -> "payment needed"
        true -> nil
      end

    base = "Orders, #{active_count} active, #{history_count} in history"
    if status, do: "#{base}, #{status}", else: base
  end

  defp rewards_available?(%{kind: :ready, eligible?: true}), do: true
  defp rewards_available?(_), do: false

  defp rewards_trigger_aria(rewards) do
    if rewards_available?(rewards), do: "Rewards, reward available", else: "Rewards"
  end

  defp show_floating_tabbar?(basket_open?, detail, my_orders_open?, saved_open?) do
    not basket_open? and is_nil(detail) and not my_orders_open? and not saved_open?
  end

  defp toggle_saved_product(socket, id) do
    id =
      case id do
        n when is_integer(n) -> n
        bin when is_binary(bin) -> String.to_integer(bin)
      end

    saved = socket.assigns.saved_product_ids

    saved =
      if MapSet.member?(saved, id) do
        MapSet.delete(saved, id)
      else
        MapSet.put(saved, id)
      end

    assign(socket, :saved_product_ids, saved)
  end

  defp saved_products(categories, saved_ids) do
    categories
    |> Enum.flat_map(fn category ->
      Enum.flat_map(category.products, fn product ->
        if MapSet.member?(saved_ids, product.id), do: [{category, product}], else: []
      end)
    end)
  end

  # Customer-facing My Orders labels only — DB status remains unchanged.
  defp customer_my_order_status_label(%{status: "cancelled"}), do: "Cancelled"
  defp customer_my_order_status_label(%{status: "ready"}), do: "Ready for pick up"
  defp customer_my_order_status_label(%{status: "completed"}), do: "Done"
  defp customer_my_order_status_label(%{status: "preparing"}), do: "Preparing"

  defp customer_my_order_status_label(%{payment_status: "awaiting_payment"}),
    do: "Waiting for payment"

  defp customer_my_order_status_label(%{payment_status: "unpaid", payment_method: "counter"}),
    do: "Pay at counter"

  defp customer_my_order_status_label(%{payment_status: "unpaid"}), do: "Unpaid"
  defp customer_my_order_status_label(%{status: "received"}), do: "Received"
  defp customer_my_order_status_label(%{status: status}), do: Orders.status_label(status)

  defp my_order_status_class(%{status: "cancelled"}), do: "menu-my-orders-status--cancelled"
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
          nil -> Menu.product_image(category.name, product)
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
      [_ | _] = prices ->
        amounts = Enum.map(prices, & &1.price)
        Menu.format_price(Enum.min(amounts, Decimal))

      _ ->
        ""
    end
  end

  defp size_label(%{size: size}) when is_binary(size) and size != "", do: size
  defp size_label(_price), do: nil

  defp detail_multi_size?(%{product: %{product_prices: prices}}) when length(prices) > 1, do: true
  defp detail_multi_size?(_detail), do: false

  defp detail_option_label(detail) do
    if detail_flavor_options?(detail), do: "Flavor", else: "Size"
  end

  defp detail_flavor_options?(%{product: %{product_prices: prices}}) when is_list(prices) do
    Enum.any?(prices, fn
      %{size: size} when is_binary(size) -> size in ~w(Plain Chocolate Strawberry)
      _ -> false
    end)
  end

  defp detail_flavor_options?(_), do: false

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

  defp menu_craving_chips do
    all_chip = %{
      key: "ALL",
      label: "All",
      event: "select_category",
      name: "ALL",
      id: nil,
      kind: :all
    }

    category_chips =
      Enum.map(craving_options(), fn option ->
        case option do
          %{filter: nil, category: category, label: label} ->
            %{
              key: category,
              label: label,
              event: "select_category",
              name: category,
              id: nil,
              kind: :category
            }

          %{filter: filter, id: id, label: label} when filter in [:matcha, :sweets] ->
            %{
              key: id,
              label: label,
              event: "select_craving",
              name: nil,
              id: id,
              kind: :filter
            }
        end
      end)

    [all_chip | category_chips]
  end

  defp chip_active?(%{kind: :filter, id: "matcha"}, _selected, :matcha), do: true
  defp chip_active?(%{kind: :filter, id: "sweets"}, _selected, :sweets), do: true
  defp chip_active?(%{kind: :all}, "ALL", nil), do: true
  defp chip_active?(%{kind: :category, name: name}, selected, nil), do: selected == name
  defp chip_active?(_chip, _selected, _filter), do: false

  defp category_swipe_enabled?(assigns) do
    assigns.menu_stage == :menu and
      not search_active?(assigns.search) and
      is_nil(assigns.detail) and
      not assigns.basket_open? and
      not assigns.saved_open? and
      not assigns.my_orders_open?
  end

  defp neighbor_menu_chip(assigns, dir) when dir in ["next", "prev"] do
    chips = menu_craving_chips()

    idx =
      Enum.find_index(chips, &chip_active?(&1, assigns.selected_category, assigns.menu_filter))

    delta = if dir == "next", do: 1, else: -1
    next_idx = if is_integer(idx), do: idx + delta, else: nil

    if is_integer(next_idx) and next_idx >= 0 do
      Enum.at(chips, next_idx)
    end
  end

  defp apply_menu_chip(socket, chip, opts)

  defp apply_menu_chip(socket, %{kind: :all}, opts) do
    socket
    |> push_patch(to: menu_path(socket, :menu, category: "ALL", filter: nil))
    |> push_chip_follow("menu-craving-chip-ALL", opts)
  end

  defp apply_menu_chip(socket, %{kind: :category, name: name}, opts) do
    if Enum.any?(socket.assigns.categories, &(&1.name == name)) do
      socket
      |> push_patch(to: menu_path(socket, :menu, category: name, filter: nil))
      |> push_chip_follow("menu-craving-chip-#{name}", opts)
    else
      socket
    end
  end

  defp apply_menu_chip(socket, %{kind: :filter, id: id}, opts) do
    case Enum.find(craving_options(), &(&1.id == id)) do
      nil ->
        socket

      option ->
        socket
        |> push_patch(to: craving_option_path(socket, option))
        |> push_chip_follow("menu-craving-chip-#{id}", opts)
    end
  end

  defp apply_menu_chip(socket, _chip, _opts), do: socket

  defp push_chip_follow(socket, chip_id, opts) do
    behavior = Keyword.get(opts, :chip_behavior, "auto")

    socket = push_event(socket, "scroll_active_chip", %{id: chip_id, behavior: behavior})

    if Keyword.get(opts, :scroll_content, true) do
      push_event(socket, "scroll_to_menu_content", %{})
    else
      socket
    end
  end

  defp craving_chip_aria_label(%{label: label}, true), do: "#{label}, selected"
  defp craving_chip_aria_label(%{label: label}, false), do: "Show #{label} menu"

  defp description?(description) when is_binary(description) do
    String.trim(description) != ""
  end

  defp description?(_description), do: false

  defp apply_table_param(socket, %{"table" => table}) do
    case Integer.parse(to_string(table)) do
      {n, ""} when n in 1..99 ->
        socket
        |> assign(:fulfillment, :dine_in)
        |> assign(:fulfillment_touched?, true)
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
        apply_visit_stage_param(socket, params)

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
          :matcha ->
            "menu-craving-chip-matcha"

          :sweets ->
            "menu-craving-chip-sweets"

          nil ->
            chip_id_for_category(Map.get(params, "category") || socket.assigns.selected_category)
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
    if Enum.any?(categories, &(&1.name == category)),
      do: category,
      else: default_category(categories)
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

  defp maybe_put_stage(params, :visit, category, filter, socket) do
    params = Map.put(params, "stage", "visit")

    if socket.assigns[:visit_return] == :menu do
      params
      |> Map.put("from", "menu")
      |> maybe_put_menu_category(category, filter, socket)
      |> maybe_put_menu_filter(filter, socket)
    else
      params
    end
  end

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

  defp apply_visit_stage_param(socket, params) do
    from_menu? = Map.get(params, "from") == "menu"

    socket =
      socket
      |> assign(:menu_stage, :visit)
      |> assign(:visit_return, if(from_menu?, do: :menu, else: :landing))

    if from_menu? do
      apply_menu_browse_param(socket, params)
    else
      socket
      |> assign(:selected_category, default_category(socket.assigns.categories))
      |> clear_transient_menu_state()
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
    cond do
      Map.has_key?(errors, :customer_name) -> "Please enter your name."
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

    errors
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

  defp unavailable_toast([name]),
    do: "#{name} is no longer available. Update your order and try again."

  defp unavailable_toast(names) when is_list(names) do
    "#{Enum.join(names, ", ")} are no longer available. Update your order and try again."
  end

  defp place_counter_order(socket) do
    socket = assign(socket, :placing_order?, true)

    case resolve_loyalty_and_create(socket, :counter) do
      {:ok, order} ->
        {:noreply, finalize_counter_order(socket, order)}

      {:error, :invalid_phone} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, %{loyalty_phone: "Enter a valid PH mobile number"})}

      {:error, {:unavailable, names}} ->
        {:noreply, order_failure(socket, unavailable_toast(names))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, checkout_errors_from_changeset(changeset))}

      {:error, reason} ->
        {:noreply, order_failure(socket, order_create_failure_message(reason))}
    end
  end

  defp place_qrph_order(socket, _channel) do
    socket = assign(socket, :placing_order?, true)

    case resolve_loyalty_and_create(socket, :online) do
      {:ok, order} ->
        {:noreply, finalize_counter_order(socket, order)}

      {:error, :invalid_phone} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, %{loyalty_phone: "Enter a valid PH mobile number"})}

      {:error, {:unavailable, names}} ->
        {:noreply, order_failure(socket, unavailable_toast(names))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, checkout_errors_from_changeset(changeset))}

      {:error, reason} ->
        {:noreply, order_failure(socket, order_create_failure_message(reason))}
    end
  end

  defp place_online_order(socket, channel) do
    socket = assign(socket, :placing_order?, true)

    case resolve_loyalty_and_create(socket, :online) do
      {:ok, order} ->
        finish_online_checkout(socket, order, channel)

      {:error, :invalid_phone} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, %{loyalty_phone: "Enter a valid PH mobile number"})}

      {:error, {:unavailable, names}} ->
        {:noreply, order_failure(socket, unavailable_toast(names))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:placing_order?, false)
         |> assign(:checkout_errors, checkout_errors_from_changeset(changeset))}

      {:error, reason} ->
        {:noreply, order_failure(socket, order_create_failure_message(reason))}
    end
  end

  defp resolve_loyalty_and_create(socket, payment_method) do
    attrs = order_attrs(socket, payment_method)
    phone = socket.assigns.loyalty_phone |> to_string() |> String.trim()

    cond do
      phone == "" ->
        Orders.create_order(socket.assigns.cart, attrs)

      true ->
        case Customers.find_or_create_by_phone(phone, %{name: socket.assigns.customer_name}) do
          {:ok, customer} ->
            Orders.create_order(socket.assigns.cart, Map.put(attrs, :customer_id, customer.id))

          {:error, :invalid_phone} ->
            {:error, :invalid_phone}

          {:error, reason} ->
            {:error, reason}
        end
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
         |> maybe_persist_loyalty_phone(order)
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
    |> maybe_persist_loyalty_phone(order)
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
    payment_intent =
      case socket.assigns.payment_method do
        :counter -> :cash
        channel when channel in [:gcash, :maya] -> channel
        _ -> nil
      end

    %{
      customer_name: socket.assigns.customer_name,
      fulfillment: socket.assigns.fulfillment,
      table_number: nil,
      notes: socket.assigns.notes,
      payment_method: payment_method,
      payment_intent: payment_intent
    }
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

  defp put_payment_method_from_params(socket, params) when is_map(params) do
    method = Map.get(params, "payment_method") || Map.get(params, "method")

    if is_binary(method) and method != "" do
      payment_method =
        resolve_payment_method(
          method,
          socket.assigns.payments_mode,
          socket.assigns.gcash_pay_available?,
          socket.assigns.maya_pay_available?
        )

      socket
      |> assign(:payment_method, payment_method)
      |> assign(:payment_touched?, true)
    else
      socket
    end
  end

  defp resolve_payment_method("gcash", mode, true, _maya)
       when mode in ["paymongo", "qrph_manual"],
       do: :gcash

  defp resolve_payment_method("maya", mode, _gcash, true)
       when mode in ["paymongo", "qrph_manual"],
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

  defp payment_checkout_note(:counter, _), do: "Pay at the counter when your order is ready."

  defp payment_checkout_note(:gcash, "paymongo"),
    do: "Continue to PayMongo to complete payment."

  defp payment_checkout_note(:maya, "paymongo"),
    do: "Continue to PayMongo to complete payment."

  defp payment_checkout_note(:gcash, "qrph_manual"),
    do: "You'll pay with GCash on the next screen."

  defp payment_checkout_note(:maya, "qrph_manual"),
    do: "You'll pay with Maya on the next screen."

  defp payment_checkout_note(_, _), do: "Pay at the counter when your order is ready."

  defp shop_day_menu_message(:closed),
    do: "The shop is closed for today. Please order tomorrow."

  defp shop_day_menu_message(_),
    do: "The shop is not open yet. Please order when the cafe opens."

  defp order_create_failure_message(:shop_not_open), do: shop_day_menu_message(:not_open)
  defp order_create_failure_message(:shop_day_closed), do: shop_day_menu_message(:closed)
  defp order_create_failure_message(_), do: "Could not place order — try again"
end

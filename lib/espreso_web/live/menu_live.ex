defmodule EspresoWeb.MenuLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot
  alias Espreso.Menu

  @instagram_images [
    "/images/coffeespot/IMG_3478.JPG",
    "/images/coffeespot/IMG_3482.JPG",
    "/images/coffeespot/IMG_3468.JPG",
    "/images/coffeespot/IMG_3475.JPG",
    "/images/coffeespot/IMG_3488.JPG",
    "/images/coffeespot/IMG_3457.JPG"
  ]

  @impl true
  def mount(_params, _session, socket) do
    categories = Menu.list_menu()
    selected = categories |> List.first() |> then(&(&1 && &1.name))

    {:ok,
     socket
     |> assign(:page_title, "Menu")
     |> assign(:categories, categories)
     |> assign(:instagram_images, @instagram_images)
     |> assign(:selected_category, selected)
     |> assign(:cart, [])
     |> assign(:basket_open?, false)
     |> assign(:basket_closing?, false)
     |> assign(:detail, nil)
     |> assign(:detail_closing?, false)
     |> assign(:toast, nil)
     |> assign(:basket_pulse?, false), layout: false}
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
       |> assign(:detail, nil)
       |> assign(:detail_closing?, false)
       |> push_event("scroll_to_items", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_detail", %{"id" => id}, socket) do
    case find_product(socket.assigns.categories, id) do
      nil ->
        {:noreply, socket}

      product ->
        price = List.first(product.product_prices)

        detail = %{
          product: product,
          selected_price_id: price && price.id,
          quantity: 1
        }

        {:noreply,
         socket
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
      with %{product: product, selected_price_id: price_id, quantity: qty} <- detail,
           %{} = price <- Enum.find(product.product_prices, &(&1.id == price_id)) do
        cart =
          add_line(
            socket.assigns.cart,
            product,
            price,
            qty,
            Menu.product_image(socket.assigns.selected_category, product.name)
          )
        Process.send_after(self(), :clear_toast, 2400)

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
     |> assign(:basket_closing?, false)}
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
        "menu-page site-page",
        (@detail || @basket_open?) && "menu-page-locked"
      ]}
    >
      <.site_header
        current="menu"
        show_basket?={true}
        basket_count={cart_count(@cart)}
        basket_pulse?={@basket_pulse?}
      />

      <section class="menu-hero" aria-label="CoffeeSpot menu">
        <figure class="menu-media menu-media-hero" data-image-slot="menu-hero">
          <div class="menu-media-frame">
            <img
              src={~p"/images/coffeespot/menu-hero.jpg"}
              alt="Latte and café interior at CoffeeSpot Lilac Marikina"
              class="menu-media-image"
              loading="eager"
            />
            <div class="menu-hero-overlay">
              <div class="menu-hero-copy">
                <p class="menu-brand">CoffeeSpot</p>
                <h1 class="menu-hero-title">
                  Order something good.<br />
                  <em>Brewed to linger.</em>
                </h1>
                <p class="menu-hero-statement">
                  Hot, cold, frappe, soda, and food — build your order, then send on WhatsApp.
                </p>
              </div>
            </div>
          </div>
        </figure>
      </section>

      <main class="contact-main menu-main">
      <div class="menu-browse">
        <div class="menu-categories-block">
          <p class="menu-categories-label">Categories</p>
          <nav class="menu-nav" aria-label="Menu categories">
            <button
              :for={category <- @categories}
              type="button"
              phx-click="select_category"
              phx-value-name={category.name}
              class={[
                "menu-nav-link",
                @selected_category == category.name && "menu-nav-link-active"
              ]}
              aria-pressed={to_string(@selected_category == category.name)}
            >
              {category.name}
            </button>
          </nav>
        </div>

        <div class="menu-main">
          <section
            :for={category <- visible_categories(@categories, @selected_category)}
            class={"menu-category menu-category--#{section_tone(category.name)}"}
            id={"category-#{category.name}"}
            data-category={category.name}
          >
            <div class="menu-category-heading">
              <h1 class="menu-category-title">{category_heading(category.name)}</h1>
              <p :if={lede = category_lede(category.name)} class="menu-category-lede">
                {lede}
              </p>
            </div>

            <div class="menu-shop" id="menu-items">
              <div :for={group <- category.groups} class="menu-shop-group">
                <h2 :if={group.name} class="menu-subgroup-title">{group.name}</h2>

                <ul class="menu-card-rail" id={"menu-cards-#{category.name}-#{group.name || "all"}"}>
                  <li :for={product <- group.products} class="menu-card">
                    <button
                      type="button"
                      class="menu-card-hit"
                      phx-click="open_detail"
                      phx-value-id={product.id}
                      aria-label={"View #{product.name}"}
                    >
                      <div class={"menu-card-visual menu-card-visual--#{section_tone(category.name)}"}>
                        <img
                          src={Menu.product_image(category.name, product.name)}
                          alt={product.name}
                          class="menu-card-photo"
                          loading="lazy"
                        />
                      </div>
                      <div class="menu-card-body">
                        <h3 class="menu-card-name">{product.name}</h3>
                        <p class="menu-card-price">{card_price_label(product)}</p>
                      </div>
                    </button>
                    <button
                      type="button"
                      class="menu-card-add"
                      phx-click="open_detail"
                      phx-value-id={product.id}
                      aria-label={"Buy #{product.name}"}
                    >
                      <span aria-hidden="true">+</span>
                    </button>
                  </li>
                </ul>
              </div>
            </div>
          </section>

        <section class="menu-closing" id="visit" aria-labelledby="menu-visit-title">
          <div class="menu-closing-copy">
            <p class="menu-eyebrow">Visit</p>
            <h2 id="menu-visit-title" class="menu-closing-title">
              Come sit in <em>Lilac.</em>
            </h2>
            <p class="menu-closing-body">
              Soft light, quiet corners, and a neighborhood pace —
              CoffeeSpot is built for lingering.
            </p>
            <p class="menu-closing-place">{CoffeeSpot.place_line()}</p>
            <.link navigate={~p"/contact"} class="menu-cta menu-visit-cta">Get in touch</.link>
          </div>
        </section>
        </div>
      </div>
      </main>

      <section class="site-instagram site-instagram-menu" aria-labelledby="menu-instagram-title">
        <header class="site-instagram-head">
          <h2 id="menu-instagram-title" class="site-instagram-title">
            <a
              href={CoffeeSpot.instagram_url()}
              target="_blank"
              rel="noopener noreferrer"
            >
              Follow us on Instagram
            </a>
          </h2>
        </header>

        <ul class="site-instagram-grid">
          <li :for={src <- @instagram_images} class="site-instagram-cell">
            <a
              href={CoffeeSpot.instagram_url()}
              target="_blank"
              rel="noopener noreferrer"
              tabindex="-1"
              aria-hidden="true"
            >
              <img src={src} alt="" loading="lazy" />
            </a>
          </li>
        </ul>
      </section>

      <footer class="site-footer menu-footer">
        <p class="site-footer-brand menu-footer-brand">CoffeeSpot</p>
        <p>{CoffeeSpot.place_line()}</p>
        <p class="site-footer-links menu-footer-links">
          <.link navigate={~p"/"} class="site-footer-link menu-footer-link">Home</.link>
          <span class="site-footer-sep menu-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/about"} class="site-footer-link menu-footer-link">About us</.link>
          <span class="site-footer-sep menu-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/contact"} class="site-footer-link menu-footer-link">Get in touch</.link>
        </p>
      </footer>

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

          <div class={"menu-buy-visual menu-detail-visual--#{section_tone(@selected_category)}"}>
            <img
              src={Menu.product_image(@selected_category, @detail.product.name)}
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

            <div :if={length(@detail.product.product_prices) > 1} class="menu-detail-sizes">
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
              aria-label={"Basket, #{cart_count(@cart)} items"}
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
            <div class="menu-basket-total">
              <span>Total</span>
              <strong>{Menu.format_price(cart_total(@cart))}</strong>
            </div>
            <a
              href={CoffeeSpot.order_whatsapp_url(@cart)}
              class="menu-basket-checkout"
              target="_blank"
              rel="noopener noreferrer"
            >
              Send order on WhatsApp
            </a>
            <p class="menu-basket-note">We’ll open WhatsApp with your order ready to send.</p>
          </footer>
        </aside>
      </div>
    </div>
    """
  end

  defp visible_categories(categories, selected_category) do
    Enum.filter(categories, &(&1.name == selected_category))
  end

  defp find_product(categories, id) when is_binary(id) do
    find_product(categories, String.to_integer(id))
  end

  defp find_product(categories, id) when is_integer(id) do
    categories
    |> Enum.flat_map(& &1.products)
    |> Enum.find(&(&1.id == id))
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

  defp category_heading("HOT"), do: "HOT"
  defp category_heading("COLD"), do: "COLD"
  defp category_heading("FRAPPE"), do: "FRAPPE"
  defp category_heading("SODA"), do: "SODA"
  defp category_heading("FOOD"), do: "FOOD"
  defp category_heading(name), do: name

  defp category_lede("HOT"), do: "Espresso and everyday cups — prepared with care."
  defp category_lede("COLD"), do: "Iced drinks for warm Lilac afternoons."
  defp category_lede("FRAPPE"), do: "Blended cups, topped and ready to share."
  defp category_lede("SODA"), do: "Light, bright, and easy to sip."
  defp category_lede("FOOD"), do: "Rice meals, chips, muffins, and cakes from the kitchen."
  defp category_lede(_name), do: nil

  defp description?(description) when is_binary(description) do
    String.trim(description) != ""
  end

  defp description?(_description), do: false
end

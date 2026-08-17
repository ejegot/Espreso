defmodule EspresoWeb.MenuLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot
  alias Espreso.Menu

  @impl true
  def mount(_params, _session, socket) do
    categories = Menu.list_menu()
    selected = categories |> List.first() |> then(&(&1 && &1.name))

    {:ok,
     socket
     |> assign(:page_title, "Menu")
     |> assign(:categories, categories)
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
       |> assign(:detail_closing?, false)}
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
        cart = add_line(socket.assigns.cart, product, price, qty)
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
    <div class={[
      "menu-page",
      (@detail || @basket_open?) && "menu-page-locked"
    ]}>
      <header class="menu-top">
        <.link navigate={~p"/"} class="menu-top-brand">CoffeeSpot</.link>
        <nav class="menu-top-nav" aria-label="Primary">
          <.link navigate={~p"/"} class="menu-top-link">Home</.link>
          <.link navigate={~p"/about"} class="menu-top-link">About us</.link>
          <.link navigate={~p"/contact"} class="menu-top-link">Get in touch</.link>
          <button
            type="button"
            class={["menu-basket-btn", @basket_pulse? && "menu-basket-btn-pulse"]}
            phx-click="open_basket"
            aria-label={"Basket, #{cart_count(@cart)} items"}
          >
            Basket
            <span class={["menu-basket-count", @basket_pulse? && "is-pulse"]}>
              {cart_count(@cart)}
            </span>
          </button>
        </nav>
      </header>

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
                  The menu.<br />
                  <em>Lilac mornings.</em>
                </h1>
                <p class="menu-hero-statement">
                  Hot, cold, frappe, soda, and food — everything we serve at CoffeeSpot Lilac Marikina.
                </p>
              </div>
            </div>
          </div>
        </figure>
      </section>

      <div class="menu-marquee" aria-hidden="true">
        <div class="menu-marquee-track">
          <span>Keep scrolling</span><span>·</span>
          <span>Lilac Marikina</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>CoffeeSpot</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>Lilac Marikina</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>CoffeeSpot</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>Lilac Marikina</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>CoffeeSpot</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>Lilac Marikina</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>CoffeeSpot</span><span>·</span>
        </div>
      </div>

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

        <main class="menu-main">
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

            <div class="menu-shop">
              <div :for={group <- category.groups} class="menu-shop-group">
                <h2 :if={group.name} class="menu-subgroup-title">{group.name}</h2>

                <ul class="menu-card-rail">
                  <li :for={product <- group.products} class="menu-card">
                    <button
                      type="button"
                      class="menu-card-hit"
                      phx-click="open_detail"
                      phx-value-id={product.id}
                      aria-label={"View #{product.name}"}
                    >
                      <div class={"menu-card-visual menu-card-visual--#{section_tone(category.name)}"}>
                        <span class="menu-card-initial" aria-hidden="true">
                          {product_initial(product.name)}
                        </span>
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

        <figure
          class="menu-media menu-media-moment menu-media-atmosphere"
          data-image-slot="cafe-atmosphere-01"
        >
          <div class="menu-media-frame">
            <img
              src={~p"/images/coffeespot/cafe-atmosphere-01.jpg"}
              alt="Quiet corner inside CoffeeSpot Lilac Marikina"
              class="menu-media-image"
              loading="lazy"
            />
          </div>
        </figure>

        <section class="menu-closing" id="visit" aria-labelledby="menu-visit-title">
          <figure
            class="menu-media menu-media-visit"
            data-image-slot="visit-interior-01"
          >
            <div class="menu-media-frame">
              <img
                src={~p"/images/coffeespot/visit-interior-01.jpg"}
                alt="Warm booth seating and pendant lights inside CoffeeSpot Lilac Marikina"
                class="menu-media-image"
                width="817"
                height="1024"
                loading="lazy"
              />
            </div>
          </figure>
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
      </main>
      </div>

      <footer class="menu-footer">
        <p class="menu-footer-brand">CoffeeSpot</p>
        <p>Lilac Marikina</p>
        <p class="menu-footer-links">
          <.link navigate={~p"/"} class="menu-footer-link">Home</.link>
          <span class="menu-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/about"} class="menu-footer-link">About us</.link>
          <span class="menu-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/contact"} class="menu-footer-link">Get in touch</.link>
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

          <header class="menu-buy-top">
            <button type="button" class="menu-buy-back" phx-click="close_detail" aria-label="Back to menu">
              ←
            </button>
          </header>

          <div class={"menu-buy-visual menu-detail-visual--#{section_tone(@selected_category)}"}>
            <span class="menu-buy-initial" aria-hidden="true">
              {product_initial(@detail.product.name)}
            </span>
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
              Buy now
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
              <h2 id="menu-basket-title">Basket</h2>
              <p class="menu-basket-count-label">
                {cart_count(@cart)} {if cart_count(@cart) == 1, do: "item", else: "items"}
              </p>
            </div>
            <button type="button" class="menu-basket-close" phx-click="close_basket" aria-label="Close">
              ✕
            </button>
          </header>

          <div :if={@cart == []} class="menu-basket-empty">
            <p class="menu-basket-empty-mark" aria-hidden="true">◇</p>
            <p class="menu-basket-empty-title">Nothing here yet</p>
            <p>Pick a drink from the menu, then tap Buy now.</p>
            <button type="button" class="menu-basket-empty-cta" phx-click="close_basket">
              Keep browsing
            </button>
          </div>

          <ul :if={@cart != []} class="menu-basket-list">
            <li :for={line <- @cart} class="menu-basket-line">
              <div class="menu-basket-line-visual" aria-hidden="true">
                {product_initial(line.name)}
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
            <p class="menu-basket-note">Opens WhatsApp with your order ready to send.</p>
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

  defp add_line(cart, product, price, quantity) do
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
              quantity: quantity
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

  defp product_initial(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      char -> String.upcase(char)
    end
  end

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

defmodule EspresoWeb.MenuLive do
  use EspresoWeb, :live_view

  alias Espreso.Menu

  @impl true
  def mount(_params, _session, socket) do
    categories = Menu.list_menu()

    {:ok,
     socket
     |> assign(:page_title, "Menu")
     |> assign(:categories, categories), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page">
      <header class="menu-header">
        <div class="menu-header-copy">
          <p class="menu-brand">CoffeeSpot</p>
          <p class="menu-location">Lilac Marikina</p>
          <p class="menu-tagline">Hot · Cold · Frappe · Soda · Food</p>
        </div>

        <figure class="menu-media menu-media-hero" data-image-slot="menu-hero">
          <div class="menu-media-frame">
            <img
              src={~p"/images/coffeespot/menu-hero.jpg"}
              alt="CoffeeSpot café atmosphere in Lilac Marikina"
              class="menu-media-image"
              loading="eager"
            />
          </div>
        </figure>
      </header>

      <nav class="menu-nav" aria-label="Menu categories">
        <a
          :for={category <- @categories}
          href={"#category-#{category.name}"}
          class="menu-nav-link"
        >
          {category.name}
        </a>
      </nav>

      <main class="menu-main">
        <div :for={category <- @categories}>
          <section class="menu-category" id={"category-#{category.name}"}>
            <h2 class="menu-category-title">{category.name}</h2>

            <div class="menu-groups">
              <div :for={group <- category.groups} class="menu-subgroup">
                <h3 :if={group.name} class="menu-subgroup-title">{group.name}</h3>

                <ul class="menu-product-list">
                  <li :for={product <- group.products} class="menu-product">
                    <div :if={inline_price?(product)} class="menu-product-inline">
                      <h4 class="menu-product-name">{product.name}</h4>
                      <span class="menu-price-rule" aria-hidden="true"></span>
                      <span class="menu-amount">
                        {Menu.format_price(hd(product.product_prices).price)}
                      </span>
                    </div>

                    <h4 :if={!inline_price?(product)} class="menu-product-name">{product.name}</h4>

                    <p :if={description?(product.description)} class="menu-product-description">
                      {product.description}
                    </p>

                    <ul :if={!inline_price?(product)} class="menu-price-list">
                      <li :for={price <- product.product_prices} class="menu-price">
                        <span :if={price.size} class="menu-size">{price.size}</span>
                        <span class="menu-price-rule" aria-hidden="true"></span>
                        <span class="menu-amount">{Menu.format_price(price.price)}</span>
                      </li>
                    </ul>
                  </li>
                </ul>
              </div>
            </div>
          </section>

          <figure
            :if={category.name == "COLD"}
            class="menu-media menu-media-moment"
            data-image-slot="menu-drink-01"
          >
            <div class="menu-media-frame">
              <img
                src={~p"/images/coffeespot/menu-drink-01.jpg"}
                alt="CoffeeSpot specialty drinks from the Lilac Marikina menu"
                class="menu-media-image"
                loading="lazy"
              />
            </div>
          </figure>

          <figure
            :if={category.name == "FOOD"}
            class="menu-media menu-media-moment"
            data-image-slot="menu-food-01"
          >
            <div class="menu-media-frame">
              <img
                src={~p"/images/coffeespot/menu-food-01.jpg"}
                alt="CoffeeSpot food from the Lilac Marikina kitchen"
                class="menu-media-image"
                loading="lazy"
              />
            </div>
          </figure>
        </div>

        <figure
          class="menu-media menu-media-moment"
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
      </main>

      <footer class="menu-footer">
        <p>CoffeeSpot · Lilac Marikina</p>
      </footer>
    </div>
    """
  end

  defp description?(description) when is_binary(description) do
    String.trim(description) != ""
  end

  defp description?(_description), do: false

  # Single price without a size → classic editorial "Name …… ₱" row.
  defp inline_price?(%{product_prices: [%{size: size}]}) when size in [nil, ""], do: true
  defp inline_price?(_product), do: false
end

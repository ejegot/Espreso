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
      <div class="menu-atmosphere" aria-hidden="true"></div>

      <header class="menu-header">
        <p class="menu-brand">CoffeeSpot</p>
        <p class="menu-location">Lilac Marikina</p>
        <p class="menu-tagline">Hot · Cold · Frappe · Soda · Food</p>
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
        <section :for={category <- @categories} class="menu-category" id={"category-#{category.name}"}>
          <h2 class="menu-category-title">{category.name}</h2>

          <div class="menu-groups">
            <div :for={group <- category.groups} class="menu-subgroup">
              <h3 :if={group.name} class="menu-subgroup-title">{group.name}</h3>

              <ul class="menu-product-list">
                <li :for={product <- group.products} class="menu-product">
                  <h4 class="menu-product-name">{product.name}</h4>

                  <p :if={description?(product.description)} class="menu-product-description">
                    {product.description}
                  </p>

                  <ul class="menu-price-list">
                    <li :for={price <- product.product_prices} class="menu-price">
                      <span :if={price.size} class="menu-size">{price.size}</span>
                      <span :if={price.size} class="menu-price-rule" aria-hidden="true"></span>
                      <span class={["menu-amount", !price.size && "menu-amount-only"]}>
                        {Menu.format_price(price.price)}
                      </span>
                    </li>
                  </ul>
                </li>
              </ul>
            </div>
          </div>
        </section>
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
end

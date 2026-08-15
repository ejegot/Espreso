defmodule EspresoWeb.HomeLive do
  use EspresoWeb, :live_view

  alias Espreso.Menu

  @featured_names [
    "Americano",
    "Café Latte",
    "Salted Caramel",
    "Chicken Flakes",
    "Solo Fries"
  ]

  @impl true
  def mount(_params, _session, socket) do
    featured = featured_products(Menu.list_menu())

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:featured_products, featured), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-page">
      <div class="home-atmosphere" aria-hidden="true"></div>

      <header class="home-topbar">
        <a href={~p"/"} class="home-topbar-brand">CoffeeSpot</a>
        <a href={~p"/menu"} class="home-topbar-link">Menu</a>
      </header>

      <section class="home-hero">
        <div class="home-hero-copy">
          <p class="home-brand">CoffeeSpot</p>
          <p class="home-location">Lilac Marikina</p>
          <p class="home-lede">
            A neighborhood café for slow mornings, familiar cups, and food made to share.
          </p>
          <a href={~p"/menu"} class="home-cta">View the menu</a>
        </div>

        <figure class="home-media home-media-hero" data-image-slot="hero">
          <div class="home-media-frame" role="img" aria-label="CoffeeSpot photo coming soon"></div>
          <figcaption class="home-media-caption">Photo coming soon</figcaption>
        </figure>
      </section>

      <section class="home-section home-story">
        <div class="home-section-copy">
          <p class="home-eyebrow">Our story</p>
          <h2 class="home-section-title">Coffee, food, and a place to linger.</h2>
          <p class="home-body">
            CoffeeSpot is a café in Lilac Marikina — a warm stop for everyday drinks,
            comforting plates, and unhurried time with people you know.
          </p>
        </div>

        <figure class="home-media home-media-story" data-image-slot="story">
          <div class="home-media-frame" role="img" aria-label="CoffeeSpot story photo coming soon"></div>
          <figcaption class="home-media-caption">Photo coming soon</figcaption>
        </figure>
      </section>

      <section class="home-section home-featured">
        <div class="home-section-heading">
          <p class="home-eyebrow">Featured menu</p>
          <h2 class="home-section-title">A few favorites from the counter.</h2>
          <p class="home-body">
            A small taste of what's brewing and baking. See the full board anytime.
          </p>
        </div>

        <ul :if={@featured_products != []} class="home-featured-list">
          <li :for={product <- @featured_products} class="home-featured-item">
            <h3 class="home-featured-name">{product.name}</h3>
            <ul class="home-featured-prices">
              <li :for={price <- product.product_prices} class="home-featured-price">
                <span :if={price.size} class="home-featured-size">{price.size}</span>
                <span class="home-featured-amount">{Menu.format_price(price.price)}</span>
              </li>
            </ul>
          </li>
        </ul>

        <a href={~p"/menu"} class="home-cta home-cta-secondary">Explore the full menu</a>
      </section>

      <section class="home-section home-space">
        <div class="home-section-heading">
          <p class="home-eyebrow">The space</p>
          <h2 class="home-section-title">Lilac Marikina, poured slowly.</h2>
          <p class="home-body">
            Real CoffeeSpot photos of the café will live here soon.
          </p>
        </div>

        <div class="home-space-grid">
          <figure class="home-media home-media-space" data-image-slot="space-01">
            <div class="home-media-frame" role="img" aria-label="CoffeeSpot space photo coming soon"></div>
            <figcaption class="home-media-caption">Photo coming soon</figcaption>
          </figure>
          <figure class="home-media home-media-space" data-image-slot="space-02">
            <div class="home-media-frame" role="img" aria-label="CoffeeSpot space photo coming soon"></div>
            <figcaption class="home-media-caption">Photo coming soon</figcaption>
          </figure>
          <figure class="home-media home-media-space" data-image-slot="space-03">
            <div class="home-media-frame" role="img" aria-label="CoffeeSpot space photo coming soon"></div>
            <figcaption class="home-media-caption">Photo coming soon</figcaption>
          </figure>
        </div>
      </section>

      <section class="home-section home-visit">
        <p class="home-eyebrow">Visit us</p>
        <h2 class="home-section-title">Lilac Marikina</h2>
        <p class="home-body">
          Find CoffeeSpot in Lilac Marikina. More visit details will be added here soon.
        </p>
      </section>

      <footer class="home-footer">
        <p class="home-footer-brand">CoffeeSpot</p>
        <p class="home-footer-location">Lilac Marikina</p>
        <a href={~p"/menu"} class="home-footer-link">Menu</a>
      </footer>
    </div>
    """
  end

  defp featured_products(menu) do
    products_by_name =
      menu
      |> Enum.flat_map(& &1.products)
      |> Map.new(&{&1.name, &1})

    @featured_names
    |> Enum.map(&Map.get(products_by_name, &1))
    |> Enum.reject(&is_nil/1)
  end
end

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
        <h1 class="menu-intro">Menu</h1>

        <section
          :for={category <- @categories}
          class={"menu-category menu-category--#{section_tone(category.name)}"}
          id={"category-#{category.name}"}
          data-category={category.name}
        >
          <figure
            :if={photo = category_photo(category.name)}
            class={"menu-media menu-media-category menu-media-category--#{photo.tone}"}
            data-image-slot={photo.slot}
          >
            <div class="menu-media-frame">
              <img
                src={~p"/images/coffeespot/#{photo.file}"}
                alt={photo.alt}
                class="menu-media-image"
                loading="lazy"
              />
            </div>
          </figure>

          <h2 class="menu-category-title">{category.name}</h2>

          <div class="menu-category-body">
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
      </main>

      <footer class="menu-footer">
        <p>CoffeeSpot · Lilac Marikina</p>
      </footer>
    </div>
    """
  end

  defp section_tone("HOT"), do: "hot"
  defp section_tone("COLD"), do: "cold"
  defp section_tone("FRAPPE"), do: "frappe"
  defp section_tone("SODA"), do: "soda"
  defp section_tone("FOOD"), do: "food"
  defp section_tone(_name), do: "default"

  defp category_photo("HOT") do
    %{
      file: "coffee-espresso-01.jpg",
      slot: "category-hot",
      tone: "hot",
      alt: "Espresso served at CoffeeSpot Lilac Marikina"
    }
  end

  defp category_photo("COLD") do
    %{
      file: "cold-signature-01.jpg",
      slot: "category-cold",
      tone: "cold",
      alt: "Iced coffee from the CoffeeSpot Lilac Marikina menu"
    }
  end

  defp category_photo("FRAPPE") do
    %{
      file: "IMG_3481.JPG",
      slot: "category-frappe",
      tone: "frappe",
      alt: "Blended frappe from CoffeeSpot Lilac Marikina"
    }
  end

  defp category_photo("FOOD") do
    %{
      file: "food-table-01.jpg",
      slot: "category-food",
      tone: "food",
      alt: "Food from the CoffeeSpot Lilac Marikina kitchen"
    }
  end

  defp category_photo(_name), do: nil

  defp description?(description) when is_binary(description) do
    String.trim(description) != ""
  end

  defp description?(_description), do: false

  defp inline_price?(%{product_prices: [%{size: size}]}) when size in [nil, ""], do: true
  defp inline_price?(_product), do: false
end

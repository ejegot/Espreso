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
     |> assign(:selected_category, selected), layout: false}
  end

  @impl true
  def handle_event("select_category", %{"name" => name}, socket) do
    if Enum.any?(socket.assigns.categories, &(&1.name == name)) do
      {:noreply, assign(socket, :selected_category, name)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page">
      <header class="menu-top">
        <.link navigate={~p"/"} class="menu-top-brand">CoffeeSpot</.link>
        <nav class="menu-top-nav" aria-label="Primary">
          <.link navigate={~p"/"} class="menu-top-link">Home</.link>
          <.link navigate={~p"/about"} class="menu-top-link">About us</.link>
          <.link navigate={~p"/contact"} class="menu-top-link">Get in touch</.link>
        </nav>
      </header>

      <section class="menu-hero" aria-label="CoffeeSpot menu">
        <figure class="menu-media menu-media-hero" data-image-slot="menu-hero">
          <div class="menu-media-frame">
            <img
              src={~p"/images/coffeespot/menu-hero.jpg"}
              alt="CoffeeSpot café atmosphere in Lilac Marikina"
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
          <span>Hot</span><span>·</span>
          <span>Cold</span><span>·</span>
          <span>Frappe</span><span>·</span>
          <span>Soda</span><span>·</span>
          <span>Food</span><span>·</span>
          <span>Hot</span><span>·</span>
          <span>Cold</span><span>·</span>
          <span>Frappe</span><span>·</span>
          <span>Soda</span><span>·</span>
          <span>Food</span><span>·</span>
          <span>Hot</span><span>·</span>
          <span>Cold</span><span>·</span>
          <span>Frappe</span><span>·</span>
          <span>Soda</span><span>·</span>
          <span>Food</span><span>·</span>
          <span>Hot</span><span>·</span>
          <span>Cold</span><span>·</span>
          <span>Frappe</span><span>·</span>
          <span>Soda</span><span>·</span>
          <span>Food</span><span>·</span>
        </div>
      </div>

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

      <main class="menu-main">
        <section
          :for={category <- visible_categories(@categories, @selected_category)}
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

          <div class="menu-category-heading">
            <p class="menu-eyebrow">{category_eyebrow(category.name)}</p>
            <h2 class="menu-category-title">
              {category_heading(category.name)}
            </h2>
            <p :if={lede = category_lede(category.name)} class="menu-category-lede">
              {lede}
            </p>
          </div>

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
    </div>
    """
  end

  defp visible_categories(categories, selected_category) do
    Enum.filter(categories, &(&1.name == selected_category))
  end

  defp section_tone("HOT"), do: "hot"
  defp section_tone("COLD"), do: "cold"
  defp section_tone("FRAPPE"), do: "frappe"
  defp section_tone("SODA"), do: "soda"
  defp section_tone("FOOD"), do: "food"
  defp section_tone(_name), do: "default"

  defp category_eyebrow("HOT"), do: "01 / Hot"
  defp category_eyebrow("COLD"), do: "02 / Cold"
  defp category_eyebrow("FRAPPE"), do: "03 / Frappe"
  defp category_eyebrow("SODA"), do: "04 / Soda"
  defp category_eyebrow("FOOD"), do: "05 / Food"
  defp category_eyebrow(_name), do: "Menu"

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

  defp category_photo("SODA") do
    %{
      file: "soda-signature-01.jpg",
      slot: "category-soda",
      tone: "soda",
      alt: "Tropical fruit soda served at CoffeeSpot Lilac Marikina"
    }
  end

  defp category_photo("FOOD") do
    %{
      file: "food-savory-01.jpg",
      slot: "category-food",
      tone: "food",
      alt: "Chicken and chips from the CoffeeSpot Lilac Marikina kitchen"
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

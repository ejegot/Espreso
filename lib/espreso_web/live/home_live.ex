defmodule EspresoWeb.HomeLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot

  @happenings [
    %{
      title: "The art of coffee",
      image: "/images/coffeespot/coffee-espresso-01.jpg",
      alt: "Espresso and craft at CoffeeSpot"
    },
    %{
      title: "Soft mornings in Lilac",
      image: "/images/coffeespot/cafe-atmosphere-01.jpg",
      alt: "Quiet corner inside CoffeeSpot"
    },
    %{
      title: "Come sit with us",
      image: "/images/coffeespot/visit-interior-01.jpg",
      alt: "Warm booth seating at CoffeeSpot"
    },
    %{
      title: "Let it brew slow",
      image: "/images/coffeespot/atmosphere-table-01.jpg",
      alt: "Window light and a quiet table at CoffeeSpot"
    },
    %{
      title: "Something cold",
      image: "/images/coffeespot/cold-signature-01.jpg",
      alt: "Cold drink at CoffeeSpot"
    },
    %{
      title: "Bites between sips",
      image: "/images/coffeespot/food-signature-01.jpg",
      alt: "Food at CoffeeSpot"
    }
  ]

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
    {:ok,
     socket
     |> assign(:page_title, "CoffeeSpot")
     |> assign(:happenings, @happenings)
     |> assign(:instagram_images, @instagram_images), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-page home-page-shade">
      <section class="home-hero" aria-label="CoffeeSpot Lilac Marikina">
        <figure class="home-media home-media-hero" data-home-image="home-hero">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/home-hero-brew.jpg"}
              alt="Coffee beans, portafilter, and latte on a wooden board"
              class="home-media-image"
              loading="eager"
            />
            <div class="home-hero-overlay">
              <.site_header current="home" variant="overlay" />

              <div class="home-hero-copy">
                <h1 class="home-hero-title">
                  An oasis to slow down and enjoy really good coffee.
                </h1>
                <p class="home-hero-place">{CoffeeSpot.address_display()}</p>
                <div class="home-hero-actions">
                  <.link navigate={~p"/menu"} class="home-cta home-cta-hero">Order now</.link>
                  <.link navigate={~p"/about"} class="home-cta-ghost home-cta-hero-ghost">
                    Our story
                  </.link>
                </div>
              </div>
            </div>
          </div>
        </figure>
      </section>

      <section class="home-happenings" aria-labelledby="home-happenings-title">
        <header class="home-happenings-head">
          <h2 id="home-happenings-title" class="home-happenings-title">What's happening</h2>
          <p class="home-happenings-lede">
            Moments from the shop — brew, food, and the quiet pace of Lilac.
          </p>
        </header>

        <ul class="home-happenings-grid">
          <li :for={item <- @happenings} class="home-happening">
            <figure class="home-happening-media">
              <img src={item.image} alt={item.alt} loading="lazy" />
            </figure>
            <p class="home-happening-title">{item.title}</p>
          </li>
        </ul>

        <div class="home-happenings-cta">
          <.link navigate={~p"/menu"} class="home-cta">Browse the menu</.link>
        </div>
      </section>

      <figure class="home-break" data-home-image="home-break">
        <img
          src={~p"/images/coffeespot/coffee-table-01.jpg"}
          alt="A cup of coffee on the table at CoffeeSpot Lilac Marikina"
          loading="lazy"
        />
      </figure>

      <section class="site-instagram" aria-labelledby="home-instagram-title">
        <header class="site-instagram-head">
          <h2 id="home-instagram-title" class="site-instagram-title">
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

      <footer class="site-footer">
        <p class="site-footer-brand">CoffeeSpot</p>
        <p>{CoffeeSpot.place_line()}</p>
        <p class="site-footer-links">
          <.link navigate={~p"/menu"} class="site-footer-link">Menu</.link>
          <span class="site-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/about"} class="site-footer-link">About us</.link>
          <span class="site-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/contact"} class="site-footer-link">Get in touch</.link>
        </p>
      </footer>
    </div>
    """
  end
end

defmodule EspresoWeb.HomeLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot

  @hero_images [
    %{
      src: "/images/coffeespot/cafe-atmosphere-01.jpg",
      alt: "Outdoor seating at CoffeeSpot Lilac",
      tilt: "left"
    },
    %{
      src: "/images/coffeespot/visit-interior-01.jpg",
      alt: "Coffee bar inside CoffeeSpot",
      tilt: "center"
    },
    %{
      src: "/images/coffeespot/cold-signature-01.jpg",
      alt: "Cold drink at CoffeeSpot",
      tilt: "right"
    }
  ]

  @instagram_images [
    "/images/coffeespot/IMG_3478.JPG",
    "/images/coffeespot/IMG_3482.JPG",
    "/images/coffeespot/IMG_3468.JPG",
    "/images/coffeespot/IMG_3475.JPG",
    "/images/coffeespot/IMG_3488.JPG"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "CoffeeSpot")
     |> assign(:hero_images, @hero_images)
     |> assign(:instagram_images, @instagram_images), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page">
      <.brune_header current="home" />

      <%!-- Hero --%>
      <section class="brune-hero" aria-label="CoffeeSpot">
        <div class="brune-hero-copy">
          <h1 class="brune-hero-title">CoffeeSpot</h1>
          <p class="brune-hero-lede">{CoffeeSpot.tagline()}</p>
        </div>

        <ul class="brune-hero-gallery" aria-hidden="true">
          <li
            :for={image <- @hero_images}
            class={["brune-hero-shot", "brune-hero-shot--#{image.tilt}"]}
          >
            <img src={image.src} alt={image.alt} loading="eager" />
          </li>
        </ul>

        <div class="brune-hero-actions">
          <.link navigate={~p"/menu"} class="brune-primary-btn">View our menu</.link>
        </div>
      </section>

      <%!-- Promos --%>
      <.brune_promos />

      <%!-- Find us / Hours --%>
      <section class="brune-visit" aria-label="Visit CoffeeSpot">
        <div class="brune-visit-grid">
          <div class="brune-visit-block">
            <p class="brune-visit-label">Find us</p>
            <p class="brune-visit-text">{CoffeeSpot.address_short()}</p>
            <a href={"tel:#{CoffeeSpot.phone_tel()}"} class="brune-visit-link">
              {CoffeeSpot.phone_display()}
            </a>
            <a href={CoffeeSpot.email_url()} class="brune-visit-link">{CoffeeSpot.email()}</a>
          </div>

          <div class="brune-visit-art" aria-hidden="true">
            <.brune_cups />
          </div>

          <div class="brune-visit-block brune-visit-block-end">
            <p class="brune-visit-label">Our hours</p>
            <p :for={line <- CoffeeSpot.hours_lines()} class="brune-visit-text">{line}</p>
          </div>
        </div>
      </section>

      <%!-- The vibes --%>
      <section class="brune-vibes" aria-labelledby="brune-vibes-title">
        <p class="brune-vibes-eyebrow">{CoffeeSpot.vibes_eyebrow()}</p>
        <h2 id="brune-vibes-title" class="brune-vibes-quote">{CoffeeSpot.vibes_quote()}</h2>
      </section>

      <%!-- Instagram --%>
      <section class="site-instagram site-instagram-menu" aria-labelledby="home-instagram-title">
        <header class="site-instagram-head">
          <h2 id="home-instagram-title" class="site-instagram-title">
            <a href={CoffeeSpot.instagram_url()} target="_blank" rel="noopener noreferrer">
              Check us out on Instagram
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

      <%!-- Socials --%>
      <section class="brune-socials" aria-label="Follow CoffeeSpot">
        <div class="brune-socials-grid">
          <a
            href={CoffeeSpot.facebook_url()}
            target="_blank"
            rel="noopener noreferrer"
            class="brune-social-card"
            aria-label="Facebook"
          >
            <.social_icon name={:facebook} />
          </a>
          <a
            href={CoffeeSpot.tiktok_url()}
            target="_blank"
            rel="noopener noreferrer"
            class="brune-social-card"
            aria-label="TikTok"
          >
            <.social_icon name={:tiktok} />
          </a>
          <a
            href={CoffeeSpot.instagram_url()}
            target="_blank"
            rel="noopener noreferrer"
            class="brune-social-card"
            aria-label="Instagram"
          >
            <.social_icon name={:instagram} />
          </a>
        </div>
      </section>

      <%!-- Mega footer --%>
      <footer class="brune-mega-footer" aria-label="CoffeeSpot footer">
        <p class="brune-mega-brand">Elilai</p>

        <div class="brune-mega-grid">
          <div class="brune-mega-block">
            <p class="brune-mega-label">Hours</p>
            <p :for={line <- CoffeeSpot.hours_lines()} class="brune-mega-text">{line}</p>
          </div>

          <div class="brune-mega-block">
            <p class="brune-mega-label">Contact</p>
            <a href={CoffeeSpot.email_url()} class="brune-mega-link">{CoffeeSpot.email()}</a>
            <a href={"tel:#{CoffeeSpot.phone_tel()}"} class="brune-mega-link">
              {CoffeeSpot.phone_display()}
            </a>
          </div>

          <div class="brune-mega-block">
            <p class="brune-mega-label">Location</p>
            <a
              href={CoffeeSpot.map_link_url()}
              target="_blank"
              rel="noopener noreferrer"
              class="brune-mega-link"
            >
              {CoffeeSpot.address_short()}
            </a>
          </div>
        </div>
      </footer>
    </div>
    """
  end
end

defmodule EspresoWeb.AboutLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot

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
     |> assign(:page_title, "About us")
     |> assign(:instagram_images, @instagram_images), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page">
      <.brune_header current="about" />

      <%!-- Hero text --%>
      <section class="brune-about-hero" aria-label="About CoffeeSpot">
        <p class="brune-about-eyebrow">About us</p>
        <h1 class="brune-about-title">
          Welcome to CoffeeSpot,<br />your local haven for coffee.
        </h1>
        <p class="brune-about-lede">
          At CoffeeSpot, we believe that every cup of coffee tells a story, and we're here to share ours with you.
        </p>
      </section>

      <%!-- Full-width image --%>
      <figure class="brune-about-image">
        <img
          src="/images/coffeespot/cafe-atmosphere-01.jpg"
          alt="Inside CoffeeSpot Lilac Marikina"
          loading="eager"
        />
      </figure>

      <%!-- Our Story --%>
      <section class="brune-about-story" aria-labelledby="about-story-title">
        <div class="brune-about-story-copy">
          <p class="brune-about-story-eyebrow">Our story</p>
          <h2 id="about-story-title" class="brune-about-story-title">Every sip tells a tale.</h2>
          <p class="brune-about-story-body">{CoffeeSpot.intro()}</p>
        </div>
        <div class="brune-about-story-art" aria-hidden="true">
          <.brune_cups />
        </div>
      </section>

      <%!-- Specialties --%>
      <section class="brune-about-section" aria-labelledby="about-services-title">
        <p class="brune-about-section-eyebrow">Services</p>
        <h2 id="about-services-title" class="brune-about-section-title">What we offer</h2>
        <ul class="brune-about-specialties">
          <li :for={specialty <- CoffeeSpot.specialties()} class="brune-about-specialty">
            {specialty}
          </li>
        </ul>
      </section>

      <%!-- Reviews --%>
      <section class="brune-about-section" aria-labelledby="about-reviews-title">
        <p class="brune-about-section-eyebrow">Reviews</p>
        <h2 id="about-reviews-title" class="brune-about-section-title">From our guests</h2>
        <div class="brune-about-reviews">
          <article :for={review <- CoffeeSpot.reviews()} class="brune-about-review">
            <p class="brune-about-review-name">{review.name}</p>
            <p class="brune-about-review-stars" aria-label={"#{review.rating} star rating"}>
              <%= for _ <- 1..review.rating do %>
                <span aria-hidden="true">★</span>
              <% end %>
            </p>
            <p :if={review.recommend?} class="brune-about-review-rec">Recommends CoffeeSpot</p>
            <p class="brune-about-review-body">{review.body}</p>
          </article>
        </div>
      </section>

      <%!-- Instagram --%>
      <section class="site-instagram site-instagram-menu" aria-labelledby="about-instagram-title">
        <header class="site-instagram-head">
          <h2 id="about-instagram-title" class="site-instagram-title">
            <a href={CoffeeSpot.instagram_url()} target="_blank" rel="noopener noreferrer">
              Check us out on Instagram
            </a>
          </h2>
        </header>
        <ul class="site-instagram-grid">
          <li :for={src <- @instagram_images} class="site-instagram-cell">
            <a href={CoffeeSpot.instagram_url()} target="_blank" rel="noopener noreferrer" tabindex="-1" aria-hidden="true">
              <img src={src} alt="" loading="lazy" />
            </a>
          </li>
        </ul>
      </section>

      <%!-- Mega footer with Hours, Contact, Location --%>
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
            <a href={"tel:#{CoffeeSpot.phone_tel()}"} class="brune-mega-link">{CoffeeSpot.phone_display()}</a>
          </div>

          <div class="brune-mega-block">
            <p class="brune-mega-label">Location</p>
            <a href={CoffeeSpot.map_link_url()} target="_blank" rel="noopener noreferrer" class="brune-mega-link">
              {CoffeeSpot.address_short()}
            </a>
          </div>
        </div>

      </footer>
    </div>
    """
  end
end

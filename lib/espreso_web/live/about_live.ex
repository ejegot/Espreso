defmodule EspresoWeb.AboutLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "About us"), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="about-page contact-page site-page">
      <.site_header current="about" />

      <main class="contact-main">
        <header class="contact-hero">
          <p class="contact-eyebrow">About us</p>
          <h1 class="contact-title">CoffeeSpot</h1>
          <p class="contact-lede">An oasis in Lilac, Marikina</p>
        </header>

        <section class="contact-section" aria-labelledby="about-intro-title">
          <p class="contact-section-eyebrow">Intro</p>
          <h2 id="about-intro-title" class="contact-section-title">
            A place to <em>linger</em>
          </h2>
          <p class="contact-intro-body">{CoffeeSpot.intro()}</p>
        </section>

        <section class="contact-section" aria-labelledby="about-services-title">
          <p class="contact-section-eyebrow">Services</p>
          <h2 id="about-services-title" class="contact-section-title">
            Specialties
          </h2>
          <ul class="contact-specialties">
            <li :for={specialty <- CoffeeSpot.specialties()} class="contact-specialty">
              {specialty}
            </li>
          </ul>
        </section>

        <section class="contact-section" aria-labelledby="about-reviews-title">
          <p class="contact-section-eyebrow">Reviews</p>
          <h2 id="about-reviews-title" class="contact-section-title">
            From guests
          </h2>
          <p class="contact-reviews-count">{length(CoffeeSpot.reviews())} reviews</p>

          <div class="contact-reviews">
            <article :for={review <- CoffeeSpot.reviews()} class="contact-review">
              <p class="contact-review-name">{review.name}</p>
              <p class="contact-review-stars" aria-label={"#{review.rating} star rating"}>
                <%= for _ <- 1..review.rating do %>
                  <span aria-hidden="true">★</span>
                <% end %>
              </p>
              <p :if={review.recommend?} class="contact-review-recommend">
                Recommends CoffeeSpot – Lilac, Marikina
              </p>
              <p class="contact-review-body">{review.body}</p>
            </article>
          </div>
        </section>

        <div class="contact-order-cta">
          <.link navigate={~p"/menu"} class="site-cta">Order from the menu</.link>
        </div>
      </main>

      <footer class="site-footer">
        <p class="site-footer-brand">CoffeeSpot</p>
        <p>{CoffeeSpot.place_line()}</p>
        <p class="site-footer-links">
          <.link navigate={~p"/"} class="site-footer-link">Home</.link>
          <span class="site-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/menu"} class="site-footer-link">Menu</.link>
          <span class="site-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/contact"} class="site-footer-link">Get in touch</.link>
        </p>
      </footer>
    </div>
    """
  end
end

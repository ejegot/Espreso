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
    <div class="about-page contact-page">
      <header class="contact-top">
        <.link navigate={~p"/"} class="contact-top-brand">CoffeeSpot</.link>
        <nav class="contact-top-nav" aria-label="Primary">
          <.link navigate={~p"/menu"} class="contact-top-link">Menu</.link>
          <.link navigate={~p"/about"} class="contact-top-link contact-top-link-current">
            About us
          </.link>
          <.link navigate={~p"/contact"} class="contact-top-link">Get in touch</.link>
        </nav>
      </header>

      <main class="contact-main">
        <header class="contact-hero">
          <p class="contact-eyebrow">About us</p>
          <h1 class="contact-title">CoffeeSpot</h1>
          <p class="contact-lede">Lilac, Marikina</p>
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
      </main>

      <footer class="contact-footer">
        <p class="contact-footer-brand">CoffeeSpot</p>
        <p>Lilac Marikina</p>
        <p class="contact-footer-links">
          <.link navigate={~p"/"} class="contact-footer-link">Home</.link>
          <span class="contact-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/menu"} class="contact-footer-link">Menu</.link>
          <span class="contact-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/contact"} class="contact-footer-link">Get in touch</.link>
        </p>
      </footer>
    </div>
    """
  end
end

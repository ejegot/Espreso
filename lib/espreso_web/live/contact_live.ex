defmodule EspresoWeb.ContactLive do
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
     |> assign(:page_title, "Contact")
     |> assign(:instagram_images, @instagram_images), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page">
      <.brune_header current="contact" />

      <%!-- Two-column layout: left info, right form --%>
      <section class="brune-contact-main">
        <div class="brune-contact-left">
          <div class="brune-contact-brand">
            <p class="brune-contact-brand-name">CoffeeSpot</p>
            <h1 class="brune-contact-brand-title">Contact</h1>
          </div>

          <div class="brune-contact-block">
            <p class="brune-contact-label">Reach us</p>
            <a href={"tel:#{CoffeeSpot.phone_tel()}"} class="brune-contact-value">
              {CoffeeSpot.phone_display()}
            </a>
            <a href={CoffeeSpot.email_url()} class="brune-contact-value">{CoffeeSpot.email()}</a>
          </div>

          <div class="brune-contact-block">
            <p class="brune-contact-label">Find us</p>
            <p class="brune-contact-value">{CoffeeSpot.address_short()}</p>
            <p class="brune-contact-value">{CoffeeSpot.hours_label()}</p>
          </div>

          <figure class="brune-contact-image">
            <img
              src="/images/coffeespot/visit-interior-01.jpg"
              alt="Inside CoffeeSpot"
              loading="lazy"
            />
          </figure>
        </div>

        <div class="brune-contact-right">
          <h2 class="brune-contact-form-title">How can we help you?</h2>

          <form class="brune-contact-form" phx-submit="send_message">
            <div class="brune-contact-field">
              <label for="contact-name" class="brune-contact-field-label">Full name</label>
              <input type="text" id="contact-name" name="name" class="brune-contact-input" required />
            </div>

            <div class="brune-contact-field">
              <label for="contact-phone" class="brune-contact-field-label">Phone number</label>
              <input type="tel" id="contact-phone" name="phone" class="brune-contact-input" />
            </div>

            <div class="brune-contact-field">
              <label for="contact-message" class="brune-contact-field-label">Message</label>
              <textarea
                id="contact-message"
                name="message"
                rows="4"
                class="brune-contact-textarea"
                required
              ></textarea>
            </div>

            <button type="submit" class="brune-contact-submit">Send Message</button>
          </form>
        </div>
      </section>

      <%!-- Instagram --%>
      <section class="site-instagram site-instagram-menu" aria-labelledby="contact-instagram-title">
        <header class="site-instagram-head">
          <h2 id="contact-instagram-title" class="site-instagram-title">
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

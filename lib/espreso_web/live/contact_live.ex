defmodule EspresoWeb.ContactLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Get in touch"), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="contact-page">
      <header class="contact-top">
        <.link navigate={~p"/"} class="contact-top-brand">CoffeeSpot</.link>
        <nav class="contact-top-nav" aria-label="Primary">
          <.link navigate={~p"/menu"} class="contact-top-link">Menu</.link>
          <.link navigate={~p"/about"} class="contact-top-link">About us</.link>
          <.link navigate={~p"/contact"} class="contact-top-link contact-top-link-current">
            Get in touch
          </.link>
        </nav>
      </header>

      <main class="contact-main">
        <header class="contact-hero">
          <p class="contact-eyebrow">Get in touch</p>
          <h1 class="contact-title">CoffeeSpot</h1>
          <p class="contact-lede">Lilac, Marikina</p>
        </header>

        <section class="contact-section contact-section-find" aria-labelledby="contact-find-title">
          <p class="contact-section-eyebrow">Find us</p>
          <h2 id="contact-find-title" class="contact-section-title">
            Come sit in <em>Lilac.</em>
          </h2>

          <div class="contact-map">
            <iframe
              class="contact-map-frame"
              src={CoffeeSpot.map_embed_url()}
              title="Map of CoffeeSpot on Lilac Street, Marikina"
              loading="lazy"
              referrerpolicy="no-referrer-when-downgrade"
              allowfullscreen
            >
            </iframe>
          </div>

          <div class="contact-details">
            <div class="contact-detail">
              <p class="contact-detail-value">{CoffeeSpot.address_display()}</p>
              <p class="contact-detail-label">Address</p>
              <a
                href={CoffeeSpot.map_link_url()}
                class="contact-map-link"
                target="_blank"
                rel="noopener noreferrer"
              >
                Open in Google Maps
              </a>
            </div>

            <div class="contact-detail">
              <p class="contact-detail-value">{CoffeeSpot.hours_label()}</p>
              <p class="contact-detail-label">{CoffeeSpot.hours_note()}</p>
            </div>

            <div class="contact-detail">
              <p class="contact-detail-value">{CoffeeSpot.service_area()}</p>
              <p class="contact-detail-label">Service area</p>
            </div>
          </div>
        </section>

        <section class="contact-section contact-section-channels" aria-labelledby="contact-channels-title">
          <p class="contact-section-eyebrow">Contact</p>
          <h2 id="contact-channels-title" class="contact-section-title">
            Say <em>hello</em>
          </h2>
          <.contact_links variant="contact" links={CoffeeSpot.contact_links()} />
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
          <.link navigate={~p"/about"} class="contact-footer-link">About us</.link>
        </p>
      </footer>
    </div>
    """
  end
end

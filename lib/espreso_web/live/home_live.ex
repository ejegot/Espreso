defmodule EspresoWeb.HomeLive do
  use EspresoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "CoffeeSpot"), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-page home-page-landing">
      <section class="home-hero" aria-label="CoffeeSpot Lilac Marikina">
        <figure class="home-media home-media-hero" data-home-image="home-hero">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/home-hero.jpg"}
              alt="CoffeeSpot Lilac Marikina café interior"
              class="home-media-image"
              loading="eager"
            />
            <div class="home-hero-overlay">
              <header class="home-top home-top-over">
                <.link navigate={~p"/"} class="home-top-brand">CoffeeSpot</.link>
                <nav class="home-top-nav" aria-label="Primary">
                  <.link navigate={~p"/menu"} class="home-top-link">Menu</.link>
                  <.link navigate={~p"/about"} class="home-top-link">About us</.link>
                  <.link navigate={~p"/contact"} class="home-top-link">Get in touch</.link>
                </nav>
              </header>

              <div class="home-hero-copy">
                <p class="home-hero-kicker">Freshly brewed daily</p>
                <p class="home-hero-brand">CoffeeSpot</p>
                <h1 class="home-hero-title">
                  Where every cup tells a <em>story</em>
                </h1>
                <p class="home-hero-statement">
                  Experience the rich aroma of thoughtfully made coffee in Lilac, Marikina —
                  crafted with care, poured without hurry, and served fresh every morning.
                </p>
                <div class="home-hero-actions">
                  <.link navigate={~p"/menu"} class="home-cta home-cta-hero">Explore Menu</.link>
                  <.link navigate={~p"/about"} class="home-cta-ghost home-cta-hero-ghost">Our Story</.link>
                </div>
              </div>
            </div>
          </div>
        </figure>
      </section>
    </div>
    """
  end
end

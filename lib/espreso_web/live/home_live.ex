defmodule EspresoWeb.HomeLive do
  use EspresoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "CoffeeSpot"), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-page">
      <header class="home-top">
        <p class="home-top-brand">CoffeeSpot</p>
        <nav class="home-top-nav" aria-label="Primary">
          <.link navigate={~p"/menu"} class="home-top-link">Menu</.link>
        </nav>
      </header>

      <section class="home-hero" aria-label="CoffeeSpot Lilac Marikina">
        <div class="home-hero-copy">
          <h1 class="home-hero-brand">CoffeeSpot</h1>
          <p class="home-hero-location">Lilac, Marikina</p>
          <p class="home-hero-statement">
            A quiet specialty café — for coffee, company, and a little time.
          </p>
          <.link navigate={~p"/menu"} class="home-cta">View Menu</.link>
        </div>

        <figure class="home-media home-media-hero" data-home-image="atmosphere-table-01">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/atmosphere-table-01.jpg"}
              alt="Quiet window seat at CoffeeSpot Lilac Marikina"
              class="home-media-image"
              loading="eager"
            />
          </div>
        </figure>
      </section>

      <section class="home-intro">
        <p class="home-intro-eyebrow">Welcome</p>
        <h2 class="home-intro-title">A neighborhood café in Lilac</h2>
        <p class="home-intro-body">
          CoffeeSpot is a calm place to sit with a drink, something simple to eat,
          and the soft pace of an afternoon in Marikina.
        </p>
      </section>

      <section class="home-moment home-moment-coffee">
        <figure class="home-media home-media-wide" data-home-image="coffee-table-01">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/coffee-table-01.jpg"}
              alt="Coffee on a wooden table at CoffeeSpot"
              class="home-media-image"
              loading="lazy"
            />
          </div>
        </figure>
        <div class="home-moment-copy">
          <h2 class="home-moment-title">Coffee, made quietly</h2>
          <p class="home-moment-body">
            Espresso and everyday cups — prepared with care, served without hurry.
          </p>
        </div>
      </section>

      <section class="home-moment home-moment-espresso">
        <figure class="home-media home-media-intimate" data-home-image="coffee-espresso-01">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/coffee-espresso-01.jpg"}
              alt="Fresh espresso in a ceramic cup"
              class="home-media-image"
              loading="lazy"
            />
          </div>
        </figure>
        <p class="home-moment-caption">The small details of a well-made cup.</p>
      </section>

      <section class="home-moment home-moment-cold">
        <div class="home-moment-copy home-moment-copy-lead">
          <h2 class="home-moment-title">More than coffee</h2>
          <p class="home-moment-body">
            Cold drinks for warm afternoons — simple, refreshing, and thoughtfully made.
          </p>
        </div>
        <figure class="home-media home-media-portrait" data-home-image="cold-signature-01">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/cold-signature-01.jpg"}
              alt="Iced coffee from the CoffeeSpot cold drinks menu"
              class="home-media-image"
              loading="lazy"
            />
          </div>
        </figure>
      </section>

      <section class="home-story">
        <figure class="home-media home-media-story" data-home-image="atmosphere-interior-01">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/atmosphere-interior-01.jpg"}
              alt="Interior of CoffeeSpot in Lilac Marikina"
              class="home-media-image"
              loading="lazy"
            />
          </div>
        </figure>
        <div class="home-story-copy">
          <p class="home-intro-eyebrow">The space</p>
          <h2 class="home-moment-title">Come sit for a while</h2>
          <p class="home-moment-body">
            Soft light, quiet corners, and a neighborhood pace —
            CoffeeSpot is built for lingering.
          </p>
        </div>
      </section>

      <section class="home-menu-invite">
        <h2 class="home-invite-title">Explore the menu</h2>
        <p class="home-invite-body">
          Hot, cold, frappe, soda, and food — everything we serve at CoffeeSpot.
        </p>
        <.link navigate={~p"/menu"} class="home-cta home-cta-secondary">View Menu</.link>
      </section>

      <footer class="home-footer">
        <p>CoffeeSpot · Lilac Marikina</p>
        <p class="home-footer-links">
          <.link navigate={~p"/menu"} class="home-footer-link">Menu</.link>
        </p>
      </footer>
    </div>
    """
  end
end

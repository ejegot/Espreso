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
            A quiet specialty café for coffee, company, and a little time.
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
        <p class="home-intro-eyebrow">Lilac</p>
        <h2 class="home-intro-title">A neighborhood café, without the rush.</h2>
        <p class="home-intro-body">
          Come for a cup. Stay for the light, the quiet, and whatever the afternoon needs.
        </p>
      </section>

      <section class="home-moment home-moment-coffee">
        <figure class="home-media home-media-feature" data-home-image="coffee-table-01">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/coffee-table-01.jpg"}
              alt="Coffee on a wooden table at CoffeeSpot"
              class="home-media-image"
              loading="lazy"
            />
          </div>
        </figure>
        <p class="home-moment-caption home-moment-caption-feature">
          Coffee, made quietly — prepared with care, served without hurry.
        </p>
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
        <figure class="home-media home-media-shift" data-home-image="cold-signature-01">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/cold-signature-01.jpg"}
              alt="Iced coffee from the CoffeeSpot cold drinks menu"
              class="home-media-image"
              loading="lazy"
            />
          </div>
        </figure>
        <div class="home-cold-note">
          <h2 class="home-cold-title">More than coffee</h2>
          <p class="home-cold-body">Cold drinks for warm Marikina afternoons.</p>
        </div>
      </section>

      <section class="home-story">
        <div class="home-story-copy">
          <p class="home-intro-eyebrow">The space</p>
          <h2 class="home-story-title">Come sit for a while</h2>
          <p class="home-story-body">
            Soft light and quiet corners — a neighborhood place to linger.
          </p>
        </div>
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
      </section>

      <section class="home-menu-invite">
        <p class="home-invite-lead">When you’re ready</p>
        <h2 class="home-invite-title">Explore the menu</h2>
        <.link navigate={~p"/menu"} class="home-invite-link">View Menu</.link>
      </section>

      <footer class="home-footer">
        <p>CoffeeSpot · Lilac Marikina</p>
      </footer>
    </div>
    """
  end
end

defmodule EspresoWeb.HomeLive do
  use EspresoWeb, :live_view

  alias Espreso.CoffeeSpot

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
          <.link navigate={~p"/about"} class="home-top-link">About us</.link>
          <.link navigate={~p"/contact"} class="home-top-link">Get in touch</.link>
        </nav>
      </header>

      <section class="home-hero" aria-label="CoffeeSpot Lilac Marikina">
        <figure class="home-media home-media-hero" data-home-image="menu-hero">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/menu-hero.jpg"}
              alt="Latte and café interior at CoffeeSpot Lilac Marikina"
              class="home-media-image"
              loading="eager"
            />
            <div class="home-hero-overlay">
              <div class="home-hero-copy">
                <p class="home-hero-brand">CoffeeSpot</p>
                <h1 class="home-hero-title">
                  Specialty coffee.<br />
                  <em>Lilac mornings.</em>
                </h1>
                <p class="home-hero-statement">
                  A neighborhood café in Lilac, Marikina — espresso, cold cups, and simple plates,
                  made without hurry.
                </p>
              </div>
            </div>
          </div>
        </figure>
      </section>

      <div class="home-marquee" aria-hidden="true">
        <div class="home-marquee-track">
          <span>Keep scrolling</span><span>·</span>
          <span>Lilac Marikina</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>CoffeeSpot</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>Lilac Marikina</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>CoffeeSpot</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>Lilac Marikina</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>CoffeeSpot</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>Lilac Marikina</span><span>·</span>
          <span>Keep scrolling</span><span>·</span>
          <span>CoffeeSpot</span><span>·</span>
        </div>
      </div>

      <section class="home-story" aria-labelledby="home-story-title">
        <p class="home-eyebrow">Our place</p>
        <h2 id="home-story-title" class="home-story-title">
          A café <em>reinvented</em> for lingering
        </h2>
        <p class="home-story-lead">
          CoffeeSpot believes a cup can hold more than a recipe — soft light, quiet corners,
          and the easy pace of an afternoon in Marikina.
        </p>
        <p class="home-story-body">
          Hot drinks, cold cups, frappes, sodas, and food from the kitchen.
          Everything we serve is meant to be enjoyed slowly.
        </p>
      </section>

      <section class="home-moments" aria-label="Coffee, cold, and kitchen">
        <p class="home-moments-label">Moments from Lilac</p>
        <div class="home-moments-rail">
          <article class="home-moment" data-home-image="coffee-table-01">
            <figure class="home-moment-media">
              <img
                src={~p"/images/coffeespot/coffee-table-01.jpg"}
                alt="Coffee on a wooden table at CoffeeSpot"
                loading="lazy"
              />
            </figure>
            <div class="home-moment-copy">
              <p class="home-eyebrow">Coffee</p>
              <h2 class="home-moment-title">Made <em>quietly</em></h2>
              <p class="home-moment-body">
                Espresso and everyday cups — prepared with care, served without hurry.
              </p>
            </div>
          </article>

          <article class="home-moment" data-home-image="cold-signature-01">
            <figure class="home-moment-media">
              <img
                src={~p"/images/coffeespot/cold-signature-01.jpg"}
                alt="Iced coffee at CoffeeSpot"
                loading="lazy"
              />
            </figure>
            <div class="home-moment-copy">
              <p class="home-eyebrow">Cold</p>
              <h2 class="home-moment-title">For warm <em>afternoons</em></h2>
              <p class="home-moment-body">
                Iced drinks for Lilac heat — simple, refreshing, thoughtfully made.
              </p>
            </div>
          </article>

          <article class="home-moment" data-home-image="food-savory-01">
            <figure class="home-moment-media">
              <img
                src={~p"/images/coffeespot/food-savory-01.jpg"}
                alt="Chicken and chips at CoffeeSpot Lilac Marikina"
                loading="lazy"
              />
            </figure>
            <div class="home-moment-copy">
              <p class="home-eyebrow">Kitchen</p>
              <h2 class="home-moment-title">Something to <em>share</em></h2>
              <p class="home-moment-body">
                Rice meals, chips, muffins, and cakes — for a slow meal between cups.
              </p>
            </div>
          </article>
        </div>
      </section>

      <section class="home-invite">
        <p class="home-eyebrow">The menu</p>
        <h2 class="home-invite-title">
          Find your <em>favorite</em>
        </h2>
        <p class="home-invite-body">
          Hot, cold, frappe, soda, and food — everything we serve at CoffeeSpot.
        </p>
        <.link navigate={~p"/menu"} class="home-cta">Open the menu</.link>
      </section>

      <section class="home-visit" id="visit" aria-labelledby="home-visit-title">
        <figure class="home-media home-media-visit" data-home-image="visit-interior-01">
          <div class="home-media-frame">
            <img
              src={~p"/images/coffeespot/visit-interior-01.jpg"}
              alt="Warm booth seating and pendant lights inside CoffeeSpot Lilac Marikina"
              class="home-media-image"
              width="817"
              height="1024"
              loading="lazy"
            />
          </div>
        </figure>
        <div class="home-visit-copy">
          <p class="home-eyebrow">Visit</p>
          <h2 id="home-visit-title" class="home-visit-title">
            Come sit in <em>Lilac.</em>
          </h2>
          <p class="home-visit-body">
            Soft light, quiet corners, and a neighborhood pace —
            CoffeeSpot is built for lingering.
          </p>
          <p class="home-visit-place">{CoffeeSpot.place_line()}</p>
          <.link navigate={~p"/contact"} class="home-cta home-visit-cta">Get in touch</.link>
        </div>
      </section>

      <footer class="home-footer">
        <p class="home-footer-brand">CoffeeSpot</p>
        <p>Lilac Marikina</p>
        <p class="home-footer-links">
          <.link navigate={~p"/menu"} class="home-footer-link">Menu</.link>
          <span class="home-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/about"} class="home-footer-link">About us</.link>
          <span class="home-footer-sep" aria-hidden="true">·</span>
          <.link navigate={~p"/contact"} class="home-footer-link">Get in touch</.link>
        </p>
      </footer>
    </div>
    """
  end
end

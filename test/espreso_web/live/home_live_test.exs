defmodule EspresoWeb.HomeLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / loads CoffeeSpot Shade homepage", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "CoffeeSpot"
    assert html =~ "Lilac"
    assert has_element?(view, ".home-page-shade")
    assert has_element?(view, ".site-instagram")
    refute has_element?(view, ".home-page-landing")
    refute has_element?(view, ".home-marquee")
  end

  test "homepage links to the menu from nav and hero", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".site-top-over a[href='/menu']", "Menu")
    assert has_element?(view, ".home-hero a[href='/menu']", "Order now")
    assert has_element?(view, ".home-hero a[href='/about']", "Our story")
  end

  test "homepage top nav includes Home, About us, and Get in touch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".site-top-over a[href='/']", "Home")
    assert has_element?(view, ".site-top-over a.is-current[href='/']", "Home")
    assert has_element?(view, ".site-top-over a[href='/about']", "About us")
    assert has_element?(view, ".site-top-over a[href='/contact']", "Get in touch")
  end

  test "homepage Get in touch navigates to /contact", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, contact_view, html} =
      view
      |> element(".site-top-over a[href='/contact']", "Get in touch")
      |> render_click()
      |> follow_redirect(conn, ~p"/contact")

    assert has_element?(contact_view, ".contact-page")
    assert html =~ "Get in touch"
    assert html =~ "84 Lilac St."
  end

  test "homepage Menu navigates to /menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, menu_view, _html} =
      view
      |> element(".site-top-over a[href='/menu']", "Menu")
      |> render_click()
      |> follow_redirect(conn, ~p"/menu")

    assert has_element?(menu_view, ".menu-page")
  end

  test "homepage hero uses Shade brew photography and headline", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert has_element?(view, ".site-top-over .site-top-brand", "CoffeeSpot")
    assert html =~ "An oasis to slow down"
    assert html =~ "really good coffee"
    assert has_element?(
             view,
             ~s([data-home-image="home-hero"] img[src="/images/coffeespot/home-hero-brew.jpg"])
           )
  end

  test "homepage includes Instagram grid and social icons", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Follow us on Instagram"
    assert has_element?(view, ".site-instagram-grid .site-instagram-cell img")
    assert has_element?(view, ".site-top-social[aria-label*='Instagram']")
    assert has_element?(view, ".site-top-social[aria-label*='Facebook']")
    assert has_element?(view, ".site-top-social[aria-label*='TikTok']")
  end
end

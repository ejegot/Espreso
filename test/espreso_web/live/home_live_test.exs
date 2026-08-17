defmodule EspresoWeb.HomeLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / loads CoffeeSpot landing homepage", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "CoffeeSpot"
    assert html =~ "Lilac"
    assert has_element?(view, ".home-page-landing")
    refute has_element?(view, ".home-moments")
    refute has_element?(view, ".home-marquee")
    refute has_element?(view, ".home-story")
    refute has_element?(view, ".home-visit")
    refute has_element?(view, ".home-footer")
  end

  test "homepage links to the menu from nav and hero", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".home-top a[href='/menu']", "Menu")
    assert has_element?(view, ".home-hero a[href='/menu']", "Explore Menu")
    assert has_element?(view, ".home-hero a[href='/about']", "Our Story")
  end

  test "homepage top nav includes About us and Get in touch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".home-top a[href='/about']", "About us")
    assert has_element?(view, ".home-top a[href='/contact']", "Get in touch")
  end

  test "homepage Get in touch navigates to /contact", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, contact_view, html} =
      view
      |> element(".home-top a[href='/contact']", "Get in touch")
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
      |> element(".home-top a[href='/menu']", "Menu")
      |> render_click()
      |> follow_redirect(conn, ~p"/menu")

    assert has_element?(menu_view, ".menu-page")
  end

  test "homepage hero fills the first screen for QR visitors", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert has_element?(view, ".home-top-over")
    assert has_element?(view, ".home-hero-overlay .home-hero-brand", "CoffeeSpot")
    assert has_element?(view, ".home-hero-kicker", "Freshly brewed daily")
    assert html =~ "Where every cup tells a"
    assert html =~ "story"
    assert has_element?(
             view,
             ~s([data-home-image="home-hero"] img[src="/images/coffeespot/home-hero.jpg"])
           )
  end
end

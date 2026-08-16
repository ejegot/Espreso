defmodule EspresoWeb.HomeLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / loads CoffeeSpot homepage", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "CoffeeSpot"
    assert html =~ "Lilac"
    assert has_element?(view, ".home-page")
  end

  test "homepage links to the menu from the top nav", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".home-top a[href='/menu']", "Menu")
    refute has_element?(view, ".home-hero a", "View the menu")
    refute has_element?(view, ".home-hero a", "Get in touch")
  end

  test "homepage top nav includes About us and Get in touch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".home-top a[href='/about']", "About us")
    assert has_element?(view, ".home-top a[href='/contact']", "Get in touch")
  end

  test "homepage uses curated CoffeeSpot photography", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             ~s([data-home-image="coffee-table-01"] img[src="/images/coffeespot/coffee-table-01.jpg"])
           )

    assert has_element?(
             view,
             ~s([data-home-image="cold-signature-01"] img[src="/images/coffeespot/cold-signature-01.jpg"])
           )

    assert has_element?(
             view,
             ~s([data-home-image="food-savory-01"] img[src="/images/coffeespot/food-savory-01.jpg"])
           )

    assert has_element?(
             view,
             ~s([data-home-image="visit-interior-01"] img[src="/images/coffeespot/visit-interior-01.jpg"])
           )
  end

  test "homepage moments include Coffee, Cold, and Kitchen messages", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert has_element?(view, ".home-moments")
    assert html =~ "Moments from Lilac"
    assert html =~ "Made"
    assert html =~ "quietly"
    assert html =~ "For warm"
    assert html =~ "afternoons"
    assert html =~ "Something to"
    assert html =~ "share"
    assert html =~ "Espresso and everyday cups"
    assert html =~ "Iced drinks for Lilac heat"
    assert html =~ "Rice meals, chips, muffins"
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

  test "homepage hero keeps text over the image", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".home-hero-overlay .home-hero-brand", "CoffeeSpot")
    assert has_element?(view, ".home-hero-overlay .home-hero-title")
  end
end

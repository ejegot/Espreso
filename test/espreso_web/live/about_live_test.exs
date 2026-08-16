defmodule EspresoWeb.AboutLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET /about loads About us page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/about")

    assert has_element?(view, ".about-page")
    assert html =~ "CoffeeSpot"
    assert html =~ "About us"
  end

  test "about page includes intro, services, and reviews", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/about")

    assert html =~ "Italian-sourced beans"
    assert html =~ "Online booking"
    assert html =~ "Dine-in"
    assert html =~ "Phillip Aseron"
    assert html =~ "Phem Baylen"
    assert html =~ "masarap ang coffee"
    assert has_element?(view, "#about-intro-title")
    assert has_element?(view, "#about-services-title")
    assert has_element?(view, "#about-reviews-title")
    refute has_element?(view, "iframe.contact-map-frame")
  end

  test "about page top nav includes Menu and Get in touch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/about")

    assert has_element?(view, ".contact-top a[href='/']", "CoffeeSpot")
    assert has_element?(view, ".contact-top a[href='/menu']", "Menu")
    assert has_element?(view, ".contact-top a[href='/contact']", "Get in touch")
  end
end

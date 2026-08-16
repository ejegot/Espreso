defmodule EspresoWeb.ContactLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET /contact loads Get in touch page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/contact")

    assert has_element?(view, ".contact-page")
    assert html =~ "CoffeeSpot"
    assert html =~ "Get in touch"
    assert html =~ "84 Lilac St"
    assert html =~ "Concepcion Dos"
    assert has_element?(view, ".contact-visit-icon")
  end

  test "contact page keeps find us and contact channels", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/contact")

    assert has_element?(view, "iframe.contact-map-frame")
    assert has_element?(view, "#contact-find-title")
    assert has_element?(view, "#contact-channels-title")
    assert html =~ "Open in Google Maps"
    refute has_element?(view, "#contact-intro-title")
    refute has_element?(view, "#contact-services-title")
    refute has_element?(view, "#contact-reviews-title")
  end

  test "contact page top nav includes About us and Menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/contact")

    assert has_element?(view, ".contact-top a[href='/']", "CoffeeSpot")
    assert has_element?(view, ".contact-top a[href='/menu']", "Menu")
    assert has_element?(view, ".contact-top a[href='/about']", "About us")
  end
end

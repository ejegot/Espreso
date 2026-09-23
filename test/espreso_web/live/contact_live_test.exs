defmodule EspresoWeb.ContactLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET /contact loads Get in touch page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/contact")

    assert has_element?(view, ".brune-contact-main")
    assert html =~ "CoffeeSpot"
    assert html =~ "Contact"
    assert html =~ "84 Lilac St"
    assert html =~ "Concepcion Dos"
  end

  test "contact page keeps find us and contact channels", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/contact")

    assert html =~ "Find us"
    assert html =~ "Reach us"
    assert has_element?(view, "#contact-instagram-title")
    refute has_element?(view, "iframe.contact-map-frame")
    refute has_element?(view, "#contact-intro-title")
    refute has_element?(view, "#contact-services-title")
    refute has_element?(view, "#contact-reviews-title")
  end

  test "contact page top nav includes About and Menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/contact")

    assert has_element?(view, ".brune-drawer-link[href='/']", "Home")
    assert has_element?(view, ".brune-drawer-link[href='/menu']", "Menu")
    assert has_element?(view, ".brune-drawer-link[href='/about']", "About")
    assert has_element?(view, ".brune-drawer-link.is-current[href='/contact']", "Contact")
  end
end

defmodule EspresoWeb.HomeLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / loads CoffeeSpot homepage", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "CoffeeSpot"
    assert html =~ "Lilac"
    assert has_element?(view, ".home-page")
  end

  test "homepage links to the menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "a[href='/menu']", "View Menu")
  end

  test "homepage uses curated CoffeeSpot photography", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             ~s([data-home-image="atmosphere-table-01"] img[src="/images/coffeespot/atmosphere-table-01.jpg"])
           )

    assert has_element?(
             view,
             ~s([data-home-image="coffee-table-01"] img[src="/images/coffeespot/coffee-table-01.jpg"])
           )

    assert has_element?(
             view,
             ~s([data-home-image="cold-signature-01"] img[src="/images/coffeespot/cold-signature-01.jpg"])
           )
  end

  test "homepage View Menu navigates to /menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, menu_view, _html} =
      view
      |> element(".home-hero a.home-cta", "View Menu")
      |> render_click()
      |> follow_redirect(conn, ~p"/menu")

    assert has_element?(menu_view, ".menu-page")
  end
end

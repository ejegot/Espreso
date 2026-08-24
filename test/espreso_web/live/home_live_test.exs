defmodule EspresoWeb.HomeLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Repo

  setup do
    hot = insert_category!("HOT")
    cold = insert_category!("COLD")
    _frappe = insert_category!("FRAPPE")
    _soda = insert_category!("SODA")

    insert_product!(hot, "Americano", true, [{"8oz", "110"}, {"12oz", "120"}])
    insert_product!(hot, "Espresso", true, [{nil, "75"}])
    insert_product!(cold, "Hazelnut", true, [{"16oz", "180"}])

    :ok
  end

  test "GET / loads CoffeeSpot single page with menu", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "CoffeeSpot"
    assert has_element?(view, ".menu-page-brune")
    assert has_element?(view, ".brune-hero-gallery")
    assert has_element?(view, ".brune-visit")
    assert has_element?(view, ".brune-vibes")
    assert has_element?(view, ".brune-menu-shell")
    assert has_element?(view, ".brune-socials")
    assert has_element?(view, ".brune-mega-footer")
    assert has_element?(view, ".site-instagram")
    refute has_element?(view, ".home-page-shade")
  end

  test "homepage has Brune header with basket", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".brune-top-brand", "CoffeeSpot")
    assert has_element?(view, ".brune-basket-btn", "Basket")
    assert has_element?(view, ".brune-basket-count", "0")
  end

  test "homepage shows hero with gallery and tagline", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "bold coffee meets good vibes"

    assert has_element?(
             view,
             ".brune-hero-shot img[src='/images/coffeespot/cafe-atmosphere-01.jpg']"
           )

    assert has_element?(
             view,
             ".brune-hero-shot img[src='/images/coffeespot/visit-interior-01.jpg']"
           )

    assert has_element?(
             view,
             ".brune-hero-shot img[src='/images/coffeespot/cold-signature-01.jpg']"
           )
  end

  test "homepage menu tabs filter categories", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Our Menu"
    assert has_element?(view, ".brune-menu-tab-active", "Hot")
    assert has_element?(view, "#category-HOT")
    assert html =~ "Americano"
    refute has_element?(view, "#category-COLD")

    view |> element("button.brune-menu-tab", "Cold") |> render_click()
    assert has_element?(view, ".brune-menu-tab-active", "Cold")
    assert has_element?(view, "#category-COLD")
    assert render(view) =~ "Hazelnut"
    refute has_element?(view, "#category-HOT")
  end

  test "homepage ordering flow works", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button[aria-label='Order Espresso']") |> render_click()
    assert has_element?(view, "#menu-detail")
    assert has_element?(view, "button.menu-buy-now", "Add to basket")

    view |> element("button.menu-buy-now") |> render_click()
    assert has_element?(view, ".menu-toast", "Added to basket")
    assert has_element?(view, ".brune-basket-count", "1")
  end

  test "homepage shows social icons for FB, TikTok, Instagram", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".brune-social-card[aria-label='Facebook']")
    assert has_element?(view, ".brune-social-card[aria-label='TikTok']")
    assert has_element?(view, ".brune-social-card[aria-label='Instagram']")
  end

  test "homepage mega footer has hours, contact, location", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".brune-mega-brand", "CoffeeSpot")
    assert has_element?(view, ".brune-mega-label", "Hours")
    assert has_element?(view, ".brune-mega-label", "Contact")
    assert has_element?(view, ".brune-mega-label", "Location")
  end

  test "/menu loads the same single page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, ".menu-page-brune")
    assert has_element?(view, ".brune-menu-shell")
    assert has_element?(view, ".brune-hero-gallery")
  end

  defp insert_category!(name) do
    %Category{} |> Category.changeset(%{name: name}) |> Repo.insert!()
  end

  defp insert_product!(category, name, available, prices) do
    product =
      %Product{}
      |> Product.changeset(%{name: name, category_id: category.id, available: available})
      |> Repo.insert!()

    Enum.each(prices, fn {size, price} ->
      %ProductPrice{}
      |> ProductPrice.changeset(%{product_id: product.id, size: size, price: Decimal.new(price)})
      |> Repo.insert!()
    end)

    product
  end
end

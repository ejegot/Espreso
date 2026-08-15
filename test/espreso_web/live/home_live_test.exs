defmodule EspresoWeb.HomeLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Repo

  setup do
    hot = insert_category!("HOT")
    food = insert_category!("FOOD")

    insert_product!(hot, "Americano", true, [{"8oz", "110"}, {"12oz", "120"}])
    insert_product!(hot, "Café Latte", true, [{"8oz", "150"}])
    insert_product!(hot, "Secret Blend", false, [{nil, "999"}])
    insert_product!(food, "Chicken Flakes", true, [{nil, "179"}])
    insert_product!(food, "Solo Fries", true, [{nil, "99"}])

    :ok
  end

  test "GET / renders CoffeeSpot", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "CoffeeSpot"
    assert has_element?(view, ".home-page")
  end

  test "GET / shows Lilac Marikina", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Lilac Marikina"
  end

  test "GET / includes menu CTA", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "a[href='/menu']", "View the menu")
    assert has_element?(view, "a[href='/menu']", "Explore the full menu")
  end

  test "GET / features available products from the menu", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Americano"
    assert html =~ "Café Latte"
    assert html =~ "Chicken Flakes"
    assert html =~ "Solo Fries"
    assert html =~ "₱110"
    assert html =~ "₱179"
  end

  test "GET / does not feature unavailable products", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    refute html =~ "Secret Blend"
    refute html =~ "₱999"
  end

  defp insert_category!(name) do
    %Category{}
    |> Category.changeset(%{name: name})
    |> Repo.insert!()
  end

  defp insert_product!(category, name, available, prices) do
    product =
      %Product{}
      |> Product.changeset(%{
        name: name,
        category_id: category.id,
        available: available
      })
      |> Repo.insert!()

    Enum.each(prices, fn {size, price} ->
      %ProductPrice{}
      |> ProductPrice.changeset(%{
        product_id: product.id,
        size: size,
        price: Decimal.new(price)
      })
      |> Repo.insert!()
    end)

    product
  end
end

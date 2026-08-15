defmodule EspresoWeb.MenuLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Repo

  setup do
    hot = insert_category!("HOT")
    cold = insert_category!("COLD")
    frappe = insert_category!("FRAPPE")
    soda = insert_category!("SODA")
    _food = insert_category!("FOOD")

    americano =
      insert_product!(hot, "Americano", true, [
        {"8oz", "110"},
        {"12oz", "120"}
      ])

    espresso = insert_product!(hot, "Espresso", true, [{nil, "75"}])
    _unavailable = insert_product!(hot, "Secret Blend", false, [{nil, "999"}])

    insert_product!(cold, "Hazelnut", true, [{"16oz", "180"}])
    insert_product!(frappe, "Biscoff", true, [{"16oz", "180"}])
    insert_product!(soda, "Hummingbird", true, [{"16oz", "120"}])

    %{
      hot: hot,
      cold: cold,
      americano: americano,
      espresso: espresso
    }
  end

  test "GET /menu loads successfully", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/menu")

    assert html =~ "CoffeeSpot"
    assert has_element?(view, ".menu-page")
  end

  test "/menu displays categories in order", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    html = render(view)

    assert html =~ "HOT"
    assert html =~ "COLD"
    assert html =~ "FRAPPE"
    assert html =~ "SODA"
    assert html =~ "FOOD"

    hot_index = :binary.match(html, "HOT") |> elem(0)
    cold_index = :binary.match(html, "COLD") |> elem(0)
    frappe_index = :binary.match(html, "FRAPPE") |> elem(0)
    soda_index = :binary.match(html, "SODA") |> elem(0)
    food_index = :binary.match(html, "FOOD") |> elem(0)

    assert hot_index < cold_index
    assert cold_index < frappe_index
    assert frappe_index < soda_index
    assert soda_index < food_index
  end

  test "/menu displays HOT products", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/menu")

    assert html =~ "Americano"
    assert html =~ "Espresso"
  end

  test "/menu displays COLD products", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/menu")

    assert html =~ "Hazelnut"
  end

  test "/menu displays FRAPPE products", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/menu")

    assert html =~ "Biscoff"
  end

  test "/menu displays SODA products", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/menu")

    assert html =~ "Hummingbird"
  end

  test "/menu displays FOOD category even without products", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, "#category-FOOD")
    assert render(view) =~ "Coming soon"
  end

  test "/menu does not display unavailable products", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/menu")

    refute html =~ "Secret Blend"
    refute html =~ "₱999"
  end

  test "/menu displays product sizes and prices correctly", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/menu")

    assert html =~ "8oz"
    assert html =~ "₱110"
    assert html =~ "12oz"
    assert html =~ "₱120"
    assert html =~ "₱75"
    assert html =~ "16oz"
    assert html =~ "₱180"
    assert html =~ "₱120"
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

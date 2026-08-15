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
    food = insert_category!("FOOD")

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
      food: food,
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
    refute has_element?(view, "#category-FOOD")

    hot_index = :binary.match(html, "HOT") |> elem(0)
    cold_index = :binary.match(html, "COLD") |> elem(0)
    frappe_index = :binary.match(html, "FRAPPE") |> elem(0)
    soda_index = :binary.match(html, "SODA") |> elem(0)

    assert hot_index < cold_index
    assert cold_index < frappe_index
    assert frappe_index < soda_index
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

  test "/menu does not display empty categories", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/menu")

    refute has_element?(view, "#category-FOOD")
    refute html =~ "Coming soon"
  end

  test "/menu groups FOOD products by subcategory", %{conn: conn, food: food} do
    insert_product!(food, "Chicken Flakes", true, [{nil, "179"}])
    insert_product!(food, "Solo Fries", true, [{nil, "99"}])
    insert_product!(food, "Red Velvet", true, [{nil, "75"}])
    insert_product!(food, "Choco Chip Cookies", true, [{nil, "65"}])

    {:ok, view, html} = live(conn, ~p"/menu")

    assert has_element?(view, "#category-FOOD")
    assert html =~ "Rice Meal"
    assert html =~ "Appetizers"
    assert html =~ "Muffins"
    assert html =~ "Cakes / Breads"
    assert html =~ "Chicken Flakes"
    assert html =~ "Solo Fries"
    assert html =~ "Red Velvet"
    assert html =~ "Choco Chip Cookies"
    assert html =~ "₱179"
    assert html =~ "₱99"
    assert html =~ "₱65"

    rice_index = :binary.match(html, "Rice Meal") |> elem(0)
    appetizers_index = :binary.match(html, "Appetizers") |> elem(0)
    muffins_index = :binary.match(html, "Muffins") |> elem(0)
    cakes_index = :binary.match(html, "Cakes / Breads") |> elem(0)

    assert rice_index < appetizers_index
    assert appetizers_index < muffins_index
    assert muffins_index < cakes_index
  end

  test "/menu does not display unavailable products", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/menu")

    refute html =~ "Secret Blend"
    refute html =~ "₱999"
  end

  test "/menu hides FOOD subgroups when all products are unavailable", %{conn: conn, food: food} do
    insert_product!(food, "Chicken Flakes", true, [{nil, "179"}])
    insert_product!(food, "Solo Fries", false, [{nil, "99"}])
    insert_product!(food, "Beef Nachos", false, [{nil, "249"}])

    {:ok, _view, html} = live(conn, ~p"/menu")

    assert html =~ "Rice Meal"
    assert html =~ "Chicken Flakes"
    refute html =~ "Appetizers"
    refute html =~ "Solo Fries"
    refute html =~ "Beef Nachos"
  end

  test "/menu hides categories when all products are unavailable", %{conn: conn, cold: cold} do
    cold
    |> then(fn category ->
      Repo.get_by!(Product, name: "Hazelnut", category_id: category.id)
    end)
    |> Product.changeset(%{available: false})
    |> Repo.update!()

    {:ok, view, html} = live(conn, ~p"/menu")

    refute has_element?(view, "#category-COLD")
    refute html =~ "Hazelnut"
    assert has_element?(view, "#category-HOT")
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

  test "/menu keeps sticky category anchors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, "a.menu-nav-link[href='#category-HOT']", "HOT")
    assert has_element?(view, "#category-HOT")
  end

  test "/menu renders product description only when present", %{conn: conn, hot: hot} do
    insert_product!(hot, "Spanish Latte", true, [{"8oz", "160"}], "Rich and creamy")

    {:ok, view, html} = live(conn, ~p"/menu")

    assert has_element?(view, ".menu-product-description", "Rich and creamy")
    refute html =~ ~r/Espresso<\/h4>\s*<p class="menu-product-description"/
  end

  test "/menu prepares CoffeeSpot image slots", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, ~s([data-image-slot="menu-hero"]))
    assert has_element?(view, ~s([data-image-slot="menu-drink-01"]))
  end

  defp insert_category!(name) do
    %Category{}
    |> Category.changeset(%{name: name})
    |> Repo.insert!()
  end

  defp insert_product!(category, name, available, prices, description \\ nil) do
    product =
      %Product{}
      |> Product.changeset(%{
        name: name,
        category_id: category.id,
        available: available,
        description: description
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

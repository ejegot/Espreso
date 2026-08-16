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

  test "/menu displays HOT products by default", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/menu")

    assert html =~ "Americano"
    assert html =~ "Espresso"
    assert has_element?(view, "#category-HOT")
    refute has_element?(view, "#category-COLD")
    refute html =~ "Hazelnut"
  end

  test "/menu displays only the selected category", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view |> element("button.menu-nav-link", "COLD") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-COLD")
    assert html =~ "Hazelnut"
    refute has_element?(view, "#category-HOT")
    refute html =~ "Americano"

    view |> element("button.menu-nav-link", "FRAPPE") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-FRAPPE")
    assert html =~ "Biscoff"
    refute has_element?(view, "#category-COLD")

    view |> element("button.menu-nav-link", "SODA") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-SODA")
    assert html =~ "Hummingbird"
    refute has_element?(view, "#category-FRAPPE")
  end

  test "/menu keeps Visit section while filtering categories", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, "#visit")
    assert has_element?(view, ~s([data-image-slot="visit-interior-01"]))

    view |> element("button.menu-nav-link", "SODA") |> render_click()

    assert has_element?(view, "#visit")
    assert has_element?(view, ~s([data-image-slot="cafe-atmosphere-01"]))
    assert has_element?(view, "a[href='/contact']", "Get in touch")
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

    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("button.menu-nav-link", "FOOD") |> render_click()
    html = render(view)

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

    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("button.menu-nav-link", "FOOD") |> render_click()
    html = render(view)

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
    {:ok, view, html} = live(conn, ~p"/menu")

    assert html =~ "8oz"
    assert html =~ "₱110"
    assert html =~ "12oz"
    assert html =~ "₱120"
    assert html =~ "₱75"

    view |> element("button.menu-nav-link", "COLD") |> render_click()
    html = render(view)
    assert html =~ "16oz"
    assert html =~ "₱180"

    view |> element("button.menu-nav-link", "SODA") |> render_click()
    html = render(view)
    assert html =~ "₱120"
  end

  test "/menu filters categories from sticky nav", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, "button.menu-nav-link-active", "HOT")
    assert has_element?(view, "#category-HOT")

    view |> element("button.menu-nav-link", "COLD") |> render_click()

    assert has_element?(view, "button.menu-nav-link-active", "COLD")
    assert has_element?(view, "#category-COLD")
    refute has_element?(view, "#category-HOT")
  end

  test "/menu renders product description only when present", %{conn: conn, hot: hot} do
    insert_product!(hot, "Spanish Latte", true, [{"8oz", "160"}], "Rich and creamy")

    {:ok, view, html} = live(conn, ~p"/menu")

    assert has_element?(view, ".menu-product-description", "Rich and creamy")
    refute html =~ ~r/Espresso<\/h4>\s*<p class="menu-product-description"/
  end

  test "/menu prepares CoffeeSpot image slots", %{conn: conn, food: food} do
    insert_product!(food, "Chicken & Chips", true, [{nil, "149"}])

    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, ~s([data-image-slot="menu-hero"] img[src="/images/coffeespot/menu-hero.jpg"]))
    assert has_element?(view, ~s([data-image-slot="category-hot"] img[src="/images/coffeespot/coffee-espresso-01.jpg"]))
    assert has_element?(view, ~s([data-image-slot="cafe-atmosphere-01"] img[src="/images/coffeespot/cafe-atmosphere-01.jpg"]))
    assert has_element?(view, ~s([data-image-slot="visit-interior-01"] img[src="/images/coffeespot/visit-interior-01.jpg"]))

    view |> element("button.menu-nav-link", "COLD") |> render_click()
    assert has_element?(view, ~s([data-image-slot="category-cold"] img[src="/images/coffeespot/cold-signature-01.jpg"]))

    view |> element("button.menu-nav-link", "FRAPPE") |> render_click()
    assert has_element?(view, ~s([data-image-slot="category-frappe"] img[src="/images/coffeespot/IMG_3481.JPG"]))

    view |> element("button.menu-nav-link", "SODA") |> render_click()
    assert has_element?(view, ~s([data-image-slot="category-soda"] img[src="/images/coffeespot/soda-signature-01.jpg"]))

    view |> element("button.menu-nav-link", "FOOD") |> render_click()
    assert has_element?(view, ~s([data-image-slot="category-food"] img[src="/images/coffeespot/food-savory-01.jpg"]))
    assert has_element?(view, "a[href='/contact']", "Get in touch")
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

defmodule EspresoWeb.MenuLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
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
    assert has_element?(view, ".menu-page-brune")
    assert has_element?(view, ".brune-menu-shell")
    assert has_element?(view, ".brune-menu-heading-title", "Menu")
    assert has_element?(view, "#menu-search")
    assert has_element?(view, "#menu-items")
    refute has_element?(view, ".brune-menu-hero")
    refute has_element?(view, ".site-instagram-menu")
    refute has_element?(view, ".menu-marquee")
    refute has_element?(view, ".contact-hero")
  end

  test "GET /menu?table=12 prefills dine-in table for checkout", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?table=12")

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    view |> element("button.menu-buy-now", "Add to basket") |> render_click()
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "#checkout-table[value='12']")
    assert has_element?(view, "button.menu-checkout-option.is-active", "Dine-in")
  end

  test "/menu displays categories in order", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    labels =
      view
      |> element(".brune-menu-tabs-line")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("button.brune-menu-tab-link")
      |> Enum.map(fn node -> node |> Floki.text() |> String.trim() end)

    assert labels == ["Hot", "Cold", "Frappe", "Soda"]
    refute has_element?(view, "#category-FOOD")
  end

  test "/menu displays HOT products by default", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/menu")

    assert html =~ "Americano"
    assert html =~ "Espresso"
    assert has_element?(view, "#category-HOT")

    assert has_element?(
             view,
             ~s(.brune-menu-item-photo[src="/images/coffeespot/coffee-espresso-01.jpg"][alt="Americano"])
           )

    assert has_element?(
             view,
             ~s(.brune-menu-item-photo[src="/images/coffeespot/coffee-espresso-01.jpg"][alt="Espresso"])
           )

    refute has_element?(view, ".menu-card-initial")
    refute has_element?(view, "#category-COLD")
    refute html =~ "Hazelnut"
  end

  test "/menu displays only the selected category", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view |> element("button.brune-menu-tab-link", "Cold") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-COLD")
    assert html =~ "Hazelnut"
    refute has_element?(view, "#category-HOT")
    refute html =~ "Americano"

    view |> element("button.brune-menu-tab-link", "Frappe") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-FRAPPE")
    assert html =~ "Biscoff"
    refute has_element?(view, "#category-COLD")

    view |> element("button.brune-menu-tab-link", "Soda") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-SODA")
    assert html =~ "Hummingbird"
    refute has_element?(view, "#category-FRAPPE")
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
    view |> element("button.brune-menu-tab-link", "Food") |> render_click()
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
    view |> element("button.brune-menu-tab-link", "Food") |> render_click()
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

  test "/menu shows starting prices on cards and sizes in detail", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/menu")

    assert html =~ "from ₱110"
    assert html =~ "₱75"

    view |> element("button[aria-label='Add Americano']") |> render_click()
    html = render(view)

    assert has_element?(view, "#menu-detail")
    assert html =~ "8oz"
    assert html =~ "12oz"
    assert html =~ "₱110"

    view |> element("button.brune-menu-tab-link", "Cold") |> render_click()
    html = render(view)
    assert html =~ "₱180"

    view |> element("button.brune-menu-tab-link", "Soda") |> render_click()
    html = render(view)
    assert html =~ "₱120"
  end

  test "/menu filters categories from pill tabs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, ".brune-menu-tab-link-active", "Hot")
    assert has_element?(view, "#category-HOT")

    view |> element("button.brune-menu-tab-link", "Cold") |> render_click()

    assert has_element?(view, ".brune-menu-tab-link-active", "Cold")
    assert has_element?(view, "#category-COLD")
    refute has_element?(view, "#category-HOT")
  end

  test "/menu shows product description in detail when present", %{conn: conn, hot: hot} do
    insert_product!(hot, "Spanish Latte", true, [{"8oz", "160"}], "Rich and creamy")

    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("button[aria-label='Add Spanish Latte']") |> render_click()

    assert has_element?(view, ".menu-detail-description", "Rich and creamy")
  end

  test "/menu order links open modal and toast into basket", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, ".brune-menu-tabs-line")
    assert has_element?(view, "button.brune-icon-bag[aria-label='Checkout, 0 items']")
    refute has_element?(view, ".brune-bag-count")

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    assert has_element?(view, "#menu-detail")
    assert has_element?(view, ".menu-buy-modal")
    assert has_element?(view, ".menu-buy-handle")
    assert has_element?(view, "#menu-detail-title", "Espresso")

    assert has_element?(
             view,
             ~s(.menu-buy-photo[src="/images/coffeespot/coffee-espresso-01.jpg"][alt="Espresso"])
           )

    assert has_element?(view, "button.menu-buy-now", "Add to basket")

    view |> element("button.menu-buy-now", "Add to basket") |> render_click()
    refute has_element?(view, "#menu-detail")
    refute has_element?(view, "#menu-basket")
    assert has_element?(view, ".menu-toast", "Added to basket")
    assert has_element?(view, ".brune-bag-count", "1")

    view |> element("button.menu-toast-action", "View") |> render_click()
    assert has_element?(view, "#menu-basket")
    assert has_element?(view, ".menu-basket-count-label", "1 item")
    assert has_element?(view, ".menu-basket-line-name", "Espresso")

    assert has_element?(
             view,
             ~s(.menu-basket-line-photo[src="/images/coffeespot/coffee-espresso-01.jpg"])
           )

    view |> element("button.menu-basket-close") |> render_click()
    Process.sleep(300)
    html = render(view)
    refute html =~ ~s(id="menu-basket")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    assert has_element?(view, "#menu-detail")
    assert has_element?(view, "#menu-detail-title", "Americano")

    view |> element("button.menu-size-pill", "12oz") |> render_click()
    view |> element("button.menu-buy-now", "Add to basket") |> render_click()

    assert has_element?(view, ".brune-bag-count", "2")
    assert has_element?(view, ".menu-toast", "Added to basket")

    view |> element("button.brune-icon-bag") |> render_click()
    assert has_element?(view, ".menu-basket-line-name", "Americano")
    assert has_element?(view, ".menu-basket-line-size", "12oz")

    assert has_element?(view, "button.menu-basket-checkout", "Place order")
    assert has_element?(view, ".menu-checkout-payment .menu-checkout-option.is-active", "Pay at counter")
    refute render(view) =~ "Pay online"
    refute render(view) =~ "Online payment"

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Juan",
      table_number: "7",
      notes: "less ice"
    })
    |> render_change()

    assert has_element?(view, "button.menu-basket-checkout", "Place order · Pay at counter")
    refute render(view) =~ "Pay online"
    assert has_element?(view, "a.menu-basket-whatsapp", "Or send on WhatsApp")

    href =
      view
      |> element("a.menu-basket-whatsapp")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> List.first()

    assert href =~ "https://wa.me/639566728906?text="
    assert href =~ URI.encode_www_form("Espresso")
    assert href =~ URI.encode_www_form("Americano")
    assert href =~ URI.encode_www_form("Juan")
    assert href =~ URI.encode_www_form("Table 7")
    assert href =~ URI.encode_www_form("less ice")

    {:ok, order_view, _html} =
      view
      |> element("button.menu-basket-checkout", "Place order · Pay at counter")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(order_view, ".order-number")
    assert has_element?(order_view, "#order-status-message", "Order received")
    assert has_element?(order_view, ".order-card", "Juan")
    assert render(order_view) =~ "Table 7"
    assert render(order_view) =~ "Pay at counter"
  end

  test "/menu rejects place when a cart product becomes unavailable", %{
    conn: conn,
    espresso: espresso
  } do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    view |> element("button.menu-buy-now", "Add to basket") |> render_click()

    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Mia",
      table_number: "3"
    })
    |> render_change()

    espresso
    |> Product.changeset(%{available: false})
    |> Repo.update!()

    view
    |> element("button.menu-basket-checkout", "Place order · Pay at counter")
    |> render_click()

    assert has_element?(view, ".menu-toast", "Espresso is no longer available")
    assert has_element?(view, ".menu-basket-line-name", "Espresso")
    assert Orders.list_active_orders() == []
  end

  test "/menu keeps product-first chrome and CoffeeSpot footer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, ".brune-menu-heading-title", "Menu")
    assert has_element?(view, ".brune-top-brand", "CoffeeSpot")
    assert has_element?(view, ".brune-menu-tabs-line")
    assert has_element?(view, "#menu-search.brune-menu-search--compact")
    assert has_element?(view, ".brune-student-promo")
    assert has_element?(view, ".brune-mega-footer--secondary")
    assert has_element?(view, ".brune-mega-brand", "CoffeeSpot")
    assert has_element?(view, ".brune-mega-label", "Hours")
    assert has_element?(view, ".brune-mega-label", "Contact")
    assert has_element?(view, ".brune-mega-label", "Location")
    refute has_element?(view, ".brune-menu-hero")
    refute has_element?(view, ".site-instagram-menu")
    refute has_element?(view, ".brune-mega-brand", "Elilai")
    refute has_element?(view, ~s([data-image-slot="menu-hero"]))
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

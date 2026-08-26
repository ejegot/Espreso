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

  test "GET /menu opens QR landing without site navigation", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/menu")

    assert html =~ "CoffeeSpot"
    assert has_element?(view, "#menu-landing")
    assert has_element?(view, ".menu-qr-landing-brand", "CoffeeSpot")
    assert has_element?(view, ".menu-qr-landing-headline", "Order from your table.")
    assert has_element?(view, ".menu-qr-landing-lede", "Browse, pay at the counter, we prepare it.")
    assert has_element?(view, "#menu-cta-view-menu", "View the menu")
    assert has_element?(view, "#menu-cta-come-say-hi", "Come say hi")
    assert has_element?(
             view,
             ~s(.menu-qr-landing-photo[src="/images/coffeespot/cold-signature-01.jpg"])
           )

    refute has_element?(view, "#menu-cta-order-online")
    refute html =~ "Order online"
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-drawer")
    refute has_element?(view, ".brune-top-nav")
    refute has_element?(view, ".brune-search-btn")
    refute has_element?(view, "#menu-items")
    refute has_element?(view, ".brune-menu-shell")
  end

  test "/menu View the menu enters craving chooser", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view |> element("#menu-cta-view-menu") |> render_click()
    assert has_element?(view, "#menu-craving-chooser")
    assert has_element?(view, "#menu-craving-chooser-title", "What are you craving?")
    assert has_element?(view, ".menu-qr-craving-brand", "CoffeeSpot")
    assert has_element?(view, ".menu-qr-craving-hero")
    assert has_element?(view, ".menu-qr-craving-body")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, "#menu-items")

    view |> element("#menu-craving-chooser .menu-qr-craving-back") |> render_click()
    assert has_element?(view, "#menu-landing")
  end

  test "/menu craving chooser shows exactly seven options without Brunch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()

    assert has_element?(view, "#menu-craving-option-coffee", "Coffee")
    assert has_element?(view, "#menu-craving-option-iced", "Iced")
    assert has_element?(view, "#menu-craving-option-frappe", "Frappe")
    assert has_element?(view, "#menu-craving-option-soda", "Soda")
    assert has_element?(view, "#menu-craving-option-food", "Food")
    assert has_element?(view, "#menu-craving-option-matcha", "Matcha")
    assert has_element?(view, "#menu-craving-option-sweets", "Sweets")

    html = render(view)
    assert html |> Floki.parse_document!() |> Floki.find(".menu-qr-craving-option") |> length() == 7
    refute html =~ "Brunch"
    refute has_element?(view, "#menu-craving-option-brunch")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-drawer")
    refute has_element?(view, ".brune-top-nav")
  end

  test "/menu craving Coffee selects HOT", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-coffee") |> render_click()

    assert has_element?(view, "#menu-items")
    assert has_element?(view, "#category-HOT")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Coffee")
    refute has_element?(view, "#menu-craving-chooser")
  end

  test "/menu craving Iced selects COLD", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-iced") |> render_click()

    assert has_element?(view, "#category-COLD")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Iced")
    assert has_element?(view, ".brune-menu-item-name", "Hazelnut")
  end

  test "/menu craving Frappe selects FRAPPE", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-frappe") |> render_click()

    assert has_element?(view, "#category-FRAPPE")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Frappe")
    assert has_element?(view, ".brune-menu-item-name", "Biscoff")
  end

  test "/menu craving Soda selects SODA", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-soda") |> render_click()

    assert has_element?(view, "#category-SODA")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Soda")
    assert has_element?(view, ".brune-menu-item-name", "Hummingbird")
  end

  test "/menu craving Food selects FOOD", %{conn: conn, food: food} do
    insert_product!(food, "Beef Tapa", true, [{nil, "150"}])

    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-food") |> render_click()

    assert has_element?(view, "#category-FOOD")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Food")
    assert has_element?(view, ".brune-menu-item-name", "Beef Tapa")
  end

  test "/menu craving Matcha filters existing matcha products", %{
    conn: conn,
    hot: hot,
    cold: cold
  } do
    frappe = Repo.get_by!(Category, name: "FRAPPE")
    insert_product!(hot, "Matcha Latte", true, [{"12oz", "160"}])
    insert_product!(cold, "Matcha Caramel", true, [{"16oz", "180"}])
    insert_product!(cold, "Strawberry Matcha", true, [{"16oz", "180"}])
    insert_product!(frappe, "Matcha", true, [{"16oz", "190"}])
    insert_product!(hot, "Café Latte", true, [{"12oz", "140"}])

    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-matcha") |> render_click()

    assert has_element?(view, "#menu-items")
    assert has_element?(view, ".brune-menu-heading-title", "Matcha")
    assert has_element?(view, "#menu-craving-chip-matcha.is-active", "Matcha")
    assert has_element?(view, "#menu-qr-chrome")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-top-nav")
    assert has_element?(view, ".brune-menu-item-name", "Matcha Latte")
    assert has_element?(view, ".brune-menu-item-name", "Matcha Caramel")
    assert has_element?(view, ".brune-menu-item-name", "Strawberry Matcha")
    assert has_element?(view, ".brune-menu-item-name", "Matcha")
    refute has_element?(view, ".brune-menu-item-name", "Café Latte")
    refute has_element?(view, ".brune-menu-item-name", "Americano")
    refute has_element?(view, ".brune-menu-item-name", "Biscoff")
    refute has_element?(view, ".brune-menu-item-name", "Hazelnut")
  end

  test "/menu craving Sweets filters existing FOOD sweets", %{conn: conn, food: food} do
    insert_product!(food, "Beef Tapa", true, [{nil, "150"}])
    insert_product!(food, "Solo Fries", true, [{nil, "90"}])
    insert_product!(food, "BNN Cream Cheese", true, [{nil, "95"}])
    insert_product!(food, "BNN Choco Overload", true, [{nil, "95"}])
    insert_product!(food, "Choco Chip Cookies", true, [{nil, "85"}])
    insert_product!(food, "Dark Choco Dream Cake", true, [{nil, "120"}])
    insert_product!(food, "Carrot Moist Slice", true, [{nil, "110"}])

    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-sweets") |> render_click()

    assert has_element?(view, "#category-FOOD")
    assert has_element?(view, ".brune-menu-heading-title", "Sweets")
    assert has_element?(view, "#menu-craving-chip-sweets.is-active", "Sweets")
    assert has_element?(view, ".brune-menu-category-title", "Sweets")
    assert has_element?(view, ".brune-menu-item-name", "BNN Cream Cheese")
    assert has_element?(view, ".brune-menu-item-name", "BNN Choco Overload")
    assert has_element?(view, ".brune-menu-item-name", "Choco Chip Cookies")
    assert has_element?(view, ".brune-menu-item-name", "Dark Choco Dream Cake")
    assert has_element?(view, ".brune-menu-item-name", "Carrot Moist Slice")
    refute has_element?(view, ".brune-menu-item-name", "Beef Tapa")
    refute has_element?(view, ".brune-menu-item-name", "Solo Fries")
    refute has_element?(view, ".brune-menu-subgroup", "Rice Meal")
    refute has_element?(view, ".brune-menu-subgroup", "Appetizers")
  end

  test "/menu Back from menu returns to Craving", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-coffee") |> render_click()

    assert has_element?(view, "#menu-items")
    assert has_element?(view, "#menu-qr-back", "Back")
    refute has_element?(view, ".brune-drawer")
    refute has_element?(view, ".brune-top-nav")

    view |> element("#menu-qr-back") |> render_click()
    assert has_element?(view, "#menu-craving-chooser")
    refute has_element?(view, "#menu-items")
    refute has_element?(view, "#menu-landing")
  end

  test "/menu QR menu flow has no public website navbar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-iced") |> render_click()

    assert has_element?(view, "#menu-qr-chrome")
    assert has_element?(view, ".menu-qr-chrome-brand", "CoffeeSpot")
    assert has_element?(view, "#menu-search")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-top-nav")
    refute has_element?(view, ".brune-drawer")
    refute has_element?(view, ~s(a.brune-top-link[href="/"]))
    refute has_element?(view, ~s(a.brune-drawer-link[href="/about"]))
    refute has_element?(view, ~s(a.brune-drawer-link[href="/contact"]))
  end

  test "public site routes remain available outside QR menu flow", %{conn: conn} do
    assert %{status: 200} = get(conn, ~p"/")
    assert %{status: 200} = get(conn, ~p"/about")
    assert %{status: 200} = get(conn, ~p"/contact")
  end

  test "/menu craving Food still returns full FOOD browsing", %{conn: conn, food: food} do
    insert_product!(food, "Beef Tapa", true, [{nil, "150"}])
    insert_product!(food, "BNN Cream Cheese", true, [{nil, "95"}])

    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-food") |> render_click()

    assert has_element?(view, "#category-FOOD")
    assert has_element?(view, ".brune-menu-item-name", "Beef Tapa")
    assert has_element?(view, ".brune-menu-item-name", "BNN Cream Cheese")
    assert has_element?(view, ".brune-menu-subgroup", "Rice Meal")
    assert has_element?(view, ".brune-menu-subgroup", "Muffins")
  end

  test "/menu craving Matcha empty state when no matcha products", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-matcha") |> render_click()

    assert has_element?(view, "#menu-filter-empty")
    assert has_element?(view, ".menu-filter-empty-title", "Nothing here right now")
    refute has_element?(view, ".brune-menu-item-name")
  end

  test "/menu?table=12 survives Landing → Craving → selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?table=12")

    view |> element("#menu-cta-view-menu") |> render_click()
    assert has_element?(view, "#menu-craving-chooser")

    view |> element("#menu-craving-option-coffee") |> render_click()
    assert has_element?(view, "#menu-items")

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    view |> element("button.menu-buy-now", "Add to bag") |> render_click()
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "#checkout-table[value='12']")
  end

  test "/menu Come say hi opens visit stub without About/Contact pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view |> element("#menu-cta-come-say-hi") |> render_click()
    assert has_element?(view, "#menu-visit-stub")
    assert has_element?(view, ".menu-qr-stub-title", "Come say hi")
    refute has_element?(view, ".about-page")
    refute has_element?(view, ".contact-page")
    refute has_element?(view, ".brune-top-nav")
  end

  test "GET /menu loads browse menu after landing flow", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)
    html = render(view)

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

    view = enter_menu_browse(view)

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    view |> element("button.menu-buy-now", "Add to bag") |> render_click()
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "#checkout-table[value='12']")
    assert has_element?(view, "button.menu-checkout-option.is-active", "Dine-in")
  end

  test "/menu displays categories in order", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

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
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)
    html = render(view)

    assert html =~ "Americano"
    assert html =~ "Espresso"
    assert has_element?(view, "#category-HOT")

    assert has_element?(
             view,
             ~s(.brune-menu-item-photo[src="/images/coffeespot/coffee-table-01.jpg"][alt="Americano"])
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

    view = enter_menu_browse(view)

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
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)
    html = render(view)

    refute has_element?(view, "#category-FOOD")
    refute html =~ "Coming soon"
  end

  test "/menu groups FOOD products by subcategory", %{conn: conn, food: food} do
    insert_product!(food, "Chicken Flakes", true, [{nil, "179"}])
    insert_product!(food, "Solo Fries", true, [{nil, "99"}])
    insert_product!(food, "Red Velvet", true, [{nil, "75"}])
    insert_product!(food, "Choco Chip Cookies", true, [{nil, "65"}])

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

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
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)
    html = render(view)

    refute html =~ "Secret Blend"
    refute html =~ "₱999"
  end

  test "/menu hides FOOD subgroups when all products are unavailable", %{conn: conn, food: food} do
    insert_product!(food, "Chicken Flakes", true, [{nil, "179"}])
    insert_product!(food, "Solo Fries", false, [{nil, "99"}])
    insert_product!(food, "Beef Nachos", false, [{nil, "249"}])

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

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

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)
    html = render(view)

    refute has_element?(view, "#category-COLD")
    refute html =~ "Hazelnut"
    assert has_element?(view, "#category-HOT")
  end

  test "/menu shows starting prices on cards and sizes in detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)
    html = render(view)

    assert html =~ "from ₱110"
    assert html =~ "₱75"

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    refute has_element?(view, ".menu-size-pill")
    assert has_element?(view, "button.menu-buy-now", "Add to bag")

    view |> element("button[aria-label='Close']") |> render_click()

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

    view = enter_menu_browse(view)

    assert has_element?(view, ".brune-menu-tab-link-active", "Hot")
    assert has_element?(view, "#category-HOT")

    view |> element("button.brune-menu-tab-link", "Cold") |> render_click()

    assert has_element?(view, ".brune-menu-tab-link-active", "Cold")
    assert has_element?(view, "#category-COLD")
    refute has_element?(view, "#category-HOT")
  end

  test "/menu craving rail selects categories in sync with pills", %{conn: conn, food: food} do
    insert_product!(food, "Beef Tapa", true, [{nil, "180"}])

    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    assert has_element?(view, "#menu-craving")
    assert has_element?(view, "#menu-craving-title", "What are you craving?")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Coffee")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Iced")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Frappe")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Soda")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Food")
    assert has_element?(view, "#menu-craving-chip-matcha", "Matcha")
    assert has_element?(view, "#menu-craving-chip-sweets", "Sweets")

    assert has_element?(view, "#menu-craving button.menu-craving-chip.is-active", "Coffee")
    assert has_element?(view, ".brune-menu-tab-link-active", "Hot")
    assert has_element?(view, "#category-HOT")

    view |> element("#menu-craving button.menu-craving-chip", "Iced") |> render_click()

    assert has_element?(view, "#menu-craving button.menu-craving-chip.is-active", "Iced")
    assert has_element?(view, ".brune-menu-tab-link-active", "Cold")
    assert has_element?(view, "#category-COLD")
    refute has_element?(view, "#category-HOT")
    assert has_element?(view, "#menu-items", "Hazelnut")

    view |> element("button.brune-menu-tab-link", "Soda") |> render_click()

    assert has_element?(view, "#menu-craving button.menu-craving-chip.is-active", "Soda")
    assert has_element?(view, ".brune-menu-tab-link-active", "Soda")
    assert has_element?(view, "#category-SODA")

    view |> element("#menu-craving button.menu-craving-chip", "Food") |> render_click()

    assert has_element?(view, "#menu-craving button.menu-craving-chip.is-active", "Food")
    assert has_element?(view, ".brune-menu-tab-link-active", "Food")
    assert has_element?(view, "#category-FOOD")
    assert has_element?(view, "#menu-items", "Beef Tapa")

    assert has_element?(view, "#menu-search")
    view |> form("#menu-search form", %{search: "Espresso"}) |> render_change()
    assert has_element?(view, "#menu-items", "Espresso")
    assert has_element?(view, "#menu-craving")
  end

  test "/menu shows product description in detail when present", %{conn: conn, hot: hot} do
    insert_product!(hot, "Spanish Latte", true, [{"8oz", "160"}], "Rich and creamy")

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view |> element("button[aria-label='Add Spanish Latte']") |> render_click()

    assert has_element?(view, ".menu-detail-description", "Rich and creamy")
  end

  test "/menu order links open modal and toast into basket", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

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

    assert has_element?(view, "button.menu-buy-now", "Add to bag")

    view |> element("button.menu-buy-now", "Add to bag") |> render_click()
    refute has_element?(view, "#menu-detail")
    refute has_element?(view, "#menu-basket")
    assert has_element?(view, ".menu-toast", "Added to bag")
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
    view |> element("button.menu-buy-now", "Add to bag") |> render_click()

    assert has_element?(view, ".brune-bag-count", "2")
    assert has_element?(view, ".menu-toast", "Added to bag")

    view |> element("button.brune-icon-bag") |> render_click()
    assert has_element?(view, ".menu-basket-line-name", "Americano")
    assert has_element?(view, ".menu-basket-line-size", "12oz")

    assert has_element?(view, "button.menu-basket-checkout", "Place order")
    assert has_element?(view, "#menu-basket-submit")
    assert has_element?(view, "#menu-basket-submit .menu-basket-total", "₱195")
    assert has_element?(view, "#menu-basket-submit .menu-basket-submit-payment", "Pay at counter")
    assert has_element?(view, ".menu-checkout-payment-info-value", "Pay at counter")
    refute has_element?(view, ".menu-checkout-payment .menu-checkout-option")
    refute render(view) =~ "Pay online"
    refute render(view) =~ "Online payment"

    view |> element("button.menu-basket-checkout", "Place order") |> render_click()
    assert has_element?(view, "#menu-checkout-summary", "Enter your name and table number.")

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Juan",
      table_number: "7",
      notes: "less ice"
    })
    |> render_change()

    refute has_element?(view, "#menu-checkout-summary")
    assert has_element?(view, "button.menu-basket-checkout", "Place order · Pay at counter")
    refute render(view) =~ "Pay online"
    assert has_element?(view, ".menu-basket-alt-label", "Other ways to order")
    assert has_element?(view, "a.menu-basket-whatsapp", "Message us on WhatsApp instead")
    assert has_element?(
             view,
             ".menu-basket-whatsapp-note",
             "WhatsApp orders don’t create a tracked order number."
           )
    assert has_element?(view, "label[for='checkout-notes']", "Add a note")

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

    view = enter_menu_browse(view)

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    view |> element("button.menu-buy-now", "Add to bag") |> render_click()

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

  test "/menu basket keeps sticky submit outside checkout scroll", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    view |> element("button.menu-buy-now", "Add to bag") |> render_click()
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "#menu-basket-panel .menu-basket-body")
    assert has_element?(view, "#menu-basket-panel .menu-basket-checkout-fields #menu-checkout-form")
    assert has_element?(view, "#menu-basket-submit")
    assert has_element?(view, "#menu-basket-submit button.menu-basket-checkout")
    assert has_element?(view, ".menu-checkout-payment-info")
    refute has_element?(view, ".menu-basket-body button.menu-basket-checkout")
    refute has_element?(view, ".menu-basket-footer")

    view |> element("button.menu-checkout-option", "Pickup at counter") |> render_click()
    refute has_element?(view, "#checkout-table")
    assert has_element?(view, "button.menu-checkout-option.is-active", "Pickup at counter")

    view |> element("button.menu-basket-checkout", "Place order") |> render_click()
    assert has_element?(view, "#menu-checkout-summary", "Please enter your name.")
  end

  test "/menu keeps product-first chrome and CoffeeSpot footer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    assert has_element?(view, ".brune-menu-heading-title", "Menu")
    assert has_element?(view, "#menu-craving")
    assert has_element?(view, "#menu-qr-chrome")
    assert has_element?(view, ".menu-qr-chrome-brand", "CoffeeSpot")
    assert has_element?(view, ".brune-menu-tabs-line")
    assert has_element?(view, "#menu-search.brune-menu-search--compact")
    assert has_element?(view, ".brune-student-promo")
    assert has_element?(view, ".brune-mega-footer--secondary")
    assert has_element?(view, ".brune-mega-brand", "CoffeeSpot")
    assert has_element?(view, ".brune-mega-label", "Hours")
    assert has_element?(view, ".brune-mega-label", "Contact")
    assert has_element?(view, ".brune-mega-label", "Location")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-top-nav")
    refute has_element?(view, ".brune-menu-hero")
    refute has_element?(view, ".site-instagram-menu")
    refute has_element?(view, ".brune-mega-brand", "Elilai")
    refute has_element?(view, ~s([data-image-slot="menu-hero"]))
  end

  test "/menu floating bag discoverability", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    refute has_element?(view, "#menu-floating-bag")

    view |> element("button[aria-label='Add Espresso']") |> render_click()
    refute has_element?(view, "#menu-floating-bag")

    view |> element("button.menu-buy-now", "Add to bag") |> render_click()
    assert has_element?(view, "#menu-floating-bag")
    assert has_element?(view, ".menu-floating-bag-summary", "Your order · 1 item · ₱75")
    assert has_element?(view, "button.menu-floating-bag-cta", "View bag")

    view |> element("button.menu-floating-bag-cta", "View bag") |> render_click()
    assert has_element?(view, "#menu-basket")
    refute has_element?(view, "#menu-floating-bag")

    view |> element("button.menu-basket-close") |> render_click()
    Process.sleep(300)
    assert has_element?(view, "#menu-floating-bag")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    refute has_element?(view, "#menu-floating-bag")

    view |> element("button.menu-buy-now", "Add to bag") |> render_click()
    assert has_element?(view, "#menu-floating-bag")
    assert has_element?(view, ".menu-floating-bag-summary", "Your order · 2 items · ₱195")
  end

  defp enter_menu_browse(view) do
    view |> element("#menu-cta-view-menu") |> render_click()
    view |> element("#menu-craving-option-coffee") |> render_click()
    view
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

defmodule EspresoWeb.MenuLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.CoffeeSpot
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
    assert has_element?(view, "#menu-landing.menu-qr-landing--signature")
    assert has_element?(view, ".menu-qr-landing-top-brand", "CoffeeSpot")
    assert has_element?(view, "#menu-landing-carousel[phx-hook='LandingCarousel']")
    assert has_element?(view, "#menu-landing-slide-welcome")
    assert has_element?(view, "#menu-landing-slide-visit")
    refute has_element?(view, ".menu-qr-landing-headline", "Your coffee moment starts here.")
    assert has_element?(view, ".menu-qr-landing-headline", "Visit CoffeeSpot")
    refute has_element?(view, ".menu-qr-landing-lede", "Browse the menu. Order from your table.")
    assert has_element?(view, "#menu-cta-view-menu", "Get Started")
    assert has_element?(view, "#menu-cta-visit-coffeespot", "See hours & directions")

    assert has_element?(
             view,
             ~s(.menu-qr-landing-photo--signature[src="/images/coffeespot/signature-pure-tableya-portrait.jpg"])
           )

    assert has_element?(view, ".menu-qr-landing-tradition", "More than a drink,")
    assert has_element?(view, ".menu-qr-landing-tradition", "A Filipino tradition.")
    assert has_element?(view, ".menu-qr-landing-tradition-mark")

    assert has_element?(
             view,
             ~s(.menu-qr-landing-photo--visit[src="/images/coffeespot/IMG_3497.jpg"])
           )

    assert has_element?(view, ".menu-qr-landing-dots [data-landing-dot='0']")
    assert has_element?(view, ".menu-qr-landing-dots [data-landing-dot='1']")
    refute has_element?(view, ".menu-qr-landing-footer")
    refute has_element?(view, "#menu-landing-instagram")

    refute has_element?(view, ".menu-qr-landing-cravings")
    refute has_element?(view, "#menu-landing-cravings-title")
    refute has_element?(view, "#menu-craving-option-coffee")
    refute has_element?(view, "#menu-cta-order-online")
    refute html =~ "Order online"
    refute html =~ "What are you craving?"
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-drawer")
    refute has_element?(view, ".brune-top-nav")
    refute has_element?(view, ".brune-search-btn")
    refute has_element?(view, "#menu-items")
    refute has_element?(view, ".brune-menu-shell")
  end

  test "/menu View the menu enters Menu directly", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view |> element("#menu-cta-view-menu") |> render_click()
    assert has_element?(view, "#menu-items")
    assert has_element?(view, "#category-HOT")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Hot coffee")
    refute has_element?(view, "#menu-craving-chooser")
    refute has_element?(view, "#menu-landing")
    refute has_element?(view, ".brune-top")
  end

  test "/menu sticky craving chips still offer eight options without Brunch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()

    assert has_element?(view, "#menu-craving-chip-ALL", "All")
    assert has_element?(view, "#menu-craving-chip-HOT", "Hot coffee")
    assert has_element?(view, "#menu-craving-chip-COLD", "Iced coffee")
    assert has_element?(view, "#menu-craving-chip-FRAPPE", "Frappe")
    assert has_element?(view, "#menu-craving-chip-SODA", "Soda")
    assert has_element?(view, "#menu-craving-chip-FOOD", "Food")
    assert has_element?(view, "#menu-craving-chip-matcha", "Matcha")
    assert has_element?(view, "#menu-craving-chip-sweets", "Sweets")

    html = render(view)

    assert html
           |> Floki.parse_document!()
           |> Floki.find("#menu-craving button.menu-craving-chip")
           |> length() == 8

    refute html =~ "Brunch"
    refute has_element?(view, "#menu-craving-chip-brunch")
    refute has_element?(view, ".menu-qr-landing-cravings")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-drawer")
    refute has_element?(view, ".brune-top-nav")
  end

  test "/menu craving Coffee selects HOT", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
    view |> element("#menu-craving-option-coffee") |> render_click()

    assert has_element?(view, "#menu-items")
    assert has_element?(view, "#category-HOT")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Hot coffee")
    refute has_element?(view, "#menu-craving-chip-FOOD.is-active")
    refute has_element?(view, "button.menu-craving-chip.is-active", "Food")
    assert has_element?(view, "#menu-search")
    refute has_element?(view, "#menu-craving-chooser")
  end

  test "/menu View the menu defaults to HOT not Food", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view |> element("#menu-cta-view-menu") |> render_click()

    active =
      view
      |> element("#menu-craving")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("button.menu-craving-chip.is-active .menu-craving-label")
      |> Enum.map(fn node -> node |> Floki.text() |> String.trim() end)

    assert active == ["Hot coffee"]
    assert has_element?(view, "#category-HOT")
    refute has_element?(view, "#category-FOOD")
  end

  test "/menu?stage=menu without category defaults to HOT not Food", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu")

    assert has_element?(view, "#menu-craving-chip-HOT.is-active", "Hot coffee")
    refute has_element?(view, "#menu-craving-chip-FOOD.is-active")
    assert has_element?(view, "#category-HOT")
    assert has_element?(view, "#menu-search")
  end

  test "/menu category switch keeps search in the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view |> element("#menu-craving-chip-COLD") |> render_click()

    assert has_element?(view, "#menu-craving-chip-COLD.is-active", "Iced coffee")
    assert has_element?(view, "#menu-search")
    assert has_element?(view, "#category-COLD")
  end

  test "/menu craving Iced selects COLD", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
    view |> element("#menu-craving-option-iced") |> render_click()

    assert has_element?(view, "#category-COLD")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Iced coffee")
    assert has_element?(view, ".brune-menu-item-name", "Hazelnut")
  end

  test "/menu craving Frappe selects FRAPPE", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
    view |> element("#menu-craving-option-frappe") |> render_click()

    assert has_element?(view, "#category-FRAPPE")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Frappe")
    assert has_element?(view, ".brune-menu-item-name", "Biscoff")
  end

  test "/menu craving Soda selects SODA", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
    view |> element("#menu-craving-option-soda") |> render_click()

    assert has_element?(view, "#category-SODA")
    assert has_element?(view, "button.menu-craving-chip.is-active", "Soda")
    assert has_element?(view, ".brune-menu-item-name", "Hummingbird")
  end

  test "/menu craving Food selects FOOD", %{conn: conn, food: food} do
    insert_product!(food, "Beef Tapa", true, [{nil, "150"}])

    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
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

    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
    view |> element("#menu-craving-option-matcha") |> render_click()

    assert has_element?(view, "#menu-items")
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
    insert_product!(food, "Big Assorted Muffin", true, [{nil, "99"}])
    insert_product!(food, "BNN Cream Cheese", false, [{nil, "95"}])
    insert_product!(food, "Choco Chip Cookies", true, [{nil, "85"}])
    insert_product!(food, "Dark Choco Dream Cake", true, [{nil, "120"}])
    insert_product!(food, "Carrot Moist Slice", true, [{nil, "110"}])

    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
    view |> element("#menu-craving-option-sweets") |> render_click()

    assert has_element?(view, "#category-FOOD")
    assert has_element?(view, "#menu-craving-chip-sweets.is-active", "Sweets")
    assert has_element?(view, ".brune-menu-category-title", "Sweets")
    assert has_element?(view, ".brune-menu-item-name", "Big Assorted Muffin")
    assert has_element?(view, ".brune-menu-item-name", "Choco Chip Cookies")
    assert has_element?(view, ".brune-menu-item-name", "Dark Choco Dream Cake")
    assert has_element?(view, ".brune-menu-item-name", "Carrot Moist Slice")
    refute has_element?(view, ".brune-menu-item-name", "BNN Cream Cheese")
    refute has_element?(view, ".brune-menu-item-name", "Beef Tapa")
    refute has_element?(view, ".brune-menu-item-name", "Solo Fries")
    refute has_element?(view, ".brune-menu-subgroup", "Rice Meal")
    refute has_element?(view, ".brune-menu-subgroup", "Appetizers")
  end

  test "/menu Back from menu returns to Landing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view |> element("#menu-cta-view-menu") |> render_click()

    assert has_element?(view, "#menu-items")
    assert has_element?(view, "#menu-qr-back[aria-label='Back to CoffeeSpot home']")
    refute has_element?(view, "#menu-qr-back", "Back")
    refute has_element?(view, ".brune-drawer")
    refute has_element?(view, ".brune-top-nav")

    view |> element("#menu-qr-back") |> render_click()
    assert has_element?(view, "#menu-landing")
    refute has_element?(view, ".menu-qr-landing-cravings")
    refute has_element?(view, "#menu-landing-cravings-title")
    refute has_element?(view, "#menu-items")
    refute has_element?(view, "#menu-craving-chooser")
  end

  test "/menu QR menu flow has no public website navbar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
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
    insert_product!(food, "Big Assorted Muffin", true, [{nil, "99"}])
    insert_product!(food, "Slow-Roasted Chicken Sourdough", true, [{nil, "249"}])

    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
    view |> element("#menu-craving-option-food") |> render_click()

    assert has_element?(view, "#category-FOOD")
    assert has_element?(view, ".brune-menu-item-name", "Beef Tapa")
    assert has_element?(view, ".brune-menu-item-name", "Big Assorted Muffin")
    assert has_element?(view, ".brune-menu-item-name", "Slow-Roasted Chicken Sourdough")
    assert has_element?(view, ".brune-menu-subgroup", "Rice Meal")
    assert has_element?(view, ".brune-menu-subgroup", "Sandwiches & Wraps")
    assert has_element?(view, ".brune-menu-subgroup", "Muffins")
  end

  test "/menu craving Matcha empty state when no matcha products", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")
    view |> element("#menu-craving-option-matcha") |> render_click()

    assert has_element?(view, "#menu-filter-empty")
    assert has_element?(view, ".menu-filter-empty-title", "Nothing here right now")
    refute has_element?(view, ".brune-menu-item-name")
  end

  test "/menu?table=12 survives Landing → Menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?table=12")

    view |> element("#menu-cta-view-menu") |> render_click()
    assert has_element?(view, "#menu-items")
    refute has_element?(view, "#menu-craving-chooser")

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "button.menu-checkout-option.is-active", "Dine-in")
    refute has_element?(view, "#checkout-table")
  end

  test "/menu?table=12 survives craving selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?table=12&stage=craving")

    view |> element("#menu-craving-option-coffee") |> render_click()
    assert has_element?(view, "#menu-items")

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "button.menu-checkout-option.is-active", "Dine-in")
    refute has_element?(view, "#checkout-table")
  end

  test "/menu Visit CoffeeSpot opens visit panel without About/Contact pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view |> element("#menu-cta-visit-coffeespot") |> render_click()
    assert has_element?(view, "#menu-visit")
    assert has_element?(view, ".menu-qr-visit-title", "Visit CoffeeSpot")
    assert has_element?(view, ".menu-qr-visit-brand", "CoffeeSpot")
    assert has_element?(view, ".menu-qr-visit-place", "Lilac, Marikina")

    assert has_element?(
             view,
             ".menu-qr-visit-text",
             "84 Lilac St., Concepcion Dos, Marikina City, Philippines"
           )

    assert has_element?(view, "#menu-visit-maps", "Open in Maps")
    assert has_element?(view, ".menu-qr-visit-text", "Sun–Wed · 11:00 AM – 11:00 PM")
    assert has_element?(view, ".menu-qr-visit-text", "Thu · 11:00 AM – 12:00 AM")
    assert has_element?(view, ".menu-qr-visit-text", "Fri–Sat · 11:00 AM – 2:00 AM")
    assert has_element?(view, ".menu-qr-visit-text", "Holiday hours on Instagram")
    refute render(view) =~ "Student Hour"
    assert has_element?(view, "#menu-visit-phone", "+639566728906")
    assert has_element?(view, "#menu-visit-email", "elilaicorp.ph@gmail.com")
    assert has_element?(view, "#menu-visit-instagram")
    assert has_element?(view, "#menu-visit-facebook")
    assert has_element?(view, "#menu-visit-tiktok")
    assert has_element?(view, ".menu-qr-visit-socials")

    maps_href =
      view
      |> element("#menu-visit-maps")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> List.first()

    assert maps_href =~ "google.com/maps"

    ig_href =
      view
      |> element("#menu-visit-instagram")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> List.first()

    assert ig_href =~ "instagram.com"

    refute has_element?(view, ".about-page")
    refute has_element?(view, ".contact-page")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-top-nav")
    refute has_element?(view, ".brune-drawer")

    view |> element("#menu-visit .menu-qr-visit-back") |> render_click()
    assert has_element?(view, "#menu-landing")
    refute has_element?(view, "#menu-visit")
  end

  test "/menu?table=12 survives Visit CoffeeSpot path", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?table=12")

    view |> element("#menu-cta-visit-coffeespot") |> render_click()
    assert has_element?(view, "#menu-visit")

    view |> element("#menu-visit-view-menu") |> render_click()
    assert has_element?(view, "#menu-items")
    refute has_element?(view, "#menu-craving-chooser")

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "button.menu-checkout-option.is-active", "Dine-in")
    refute has_element?(view, "#checkout-table")
  end

  test "GET /menu loads browse menu after landing flow", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)
    html = render(view)

    assert html =~ "CoffeeSpot"
    assert has_element?(view, ".menu-page-brune")
    assert has_element?(view, ".brune-menu-shell")
    assert has_element?(view, "#menu-search")
    assert has_element?(view, "#menu-items")
    refute has_element?(view, ".brune-menu-hero")
    refute has_element?(view, ".site-instagram-menu")
    refute has_element?(view, ".menu-marquee")
    refute has_element?(view, ".contact-hero")
  end

  test "GET /menu?table=12 prefills dine-in for checkout without table field", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?table=12")

    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "button.menu-checkout-option.is-active", "Dine-in")
    refute has_element?(view, "#checkout-table")
  end

  test "/menu chrome is back arrow, brand, and bag", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu")

    assert has_element?(view, "#menu-qr-back[aria-label='Back to CoffeeSpot home']")
    refute has_element?(view, "#menu-qr-back", "Back")
    assert has_element?(view, "#menu-qr-back .hero-arrow-left")
    assert has_element?(view, "#menu-qr-chrome .menu-qr-chrome-brand", "CoffeeSpot")
    assert has_element?(view, "#menu-qr-bag .hero-shopping-bag")
    assert has_element?(view, "#menu-qr-bag[aria-label='Your order, 0 items']")
    refute has_element?(view, "#menu-qr-chrome #menu-qr-search-toggle")
    refute has_element?(view, "#menu-search.is-open")
  end

  test "/menu product cards use plus-only add controls with orange accent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu")
    html = render(view)

    refute html =~ "+ Add"
    refute html =~ ">Add</button>"
    assert has_element?(view, "button.brune-menu-add--icon[aria-label='Add Espresso'] .hero-plus")

    assert has_element?(
             view,
             "button.brune-menu-add--icon[aria-label='Add Americano'] .hero-plus"
           )

    add_button =
      view
      |> element("button[aria-label='Add Espresso']")
      |> render()

    assert add_button =~ "brune-menu-add--icon"
    assert add_button =~ "hero-plus"
  end

  test "/menu My Orders restored before browse appears on menu stage without refresh", %{
    conn: conn
  } do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Restore Test",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/menu")
    refute has_element?(view, "#menu-qr-my-orders")

    render_hook(view, "restore_my_orders", %{"numbers" => [order.number]})
    refute has_element?(view, "#menu-qr-my-orders")

    view = enter_menu_browse(view)
    assert has_element?(view, "#menu-qr-my-orders", "Orders")

    view |> element("#menu-craving-chip-COLD") |> render_click()
    assert has_element?(view, "#menu-qr-my-orders", "Orders")

    view |> element("#menu-qr-my-orders") |> render_click()
    assert has_element?(view, "#menu-my-order-#{order.number}", order.number)
    assert has_element?(view, "#menu-my-order-#{order.number}", "Pay at counter")
  end

  test "/menu?stage=menu shows My Orders when restored on connected menu", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Menu Stage",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu")
    refute has_element?(view, "#menu-qr-my-orders")

    render_hook(view, "restore_my_orders", %{"numbers" => [order.number]})
    assert has_element?(view, "#menu-qr-my-orders", "Orders")
  end

  test "/menu displays categories in order", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    labels =
      view
      |> element("#menu-craving")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("button.menu-craving-chip .menu-craving-label")
      |> Enum.map(fn node -> node |> Floki.text() |> String.trim() end)

    assert labels == [
             "All",
             "Hot coffee",
             "Iced coffee",
             "Frappe",
             "Soda",
             "Food",
             "Matcha",
             "Sweets"
           ]

    refute has_element?(view, ".brune-menu-tabs-line")
    refute has_element?(view, "#category-FOOD")
  end

  test "/menu floating Orders and Rewards nav uses short labels and icons", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    {:ok, received} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "One", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, ready} =
      Orders.create_order(
        [%{name: "Hazelnut", size: "16oz", quantity: 1, price: Decimal.new("180")}],
        %{customer_name: "Ready", fulfillment: :pickup, payment_method: :counter}
      )

    assert {:ok, _} = Orders.mark_paid(ready)
    assert {:ok, ready} = Orders.update_status(ready, "ready")

    render_hook(view, "restore_my_orders", %{"numbers" => [received.number]})
    assert has_element?(view, "#menu-qr-customer-nav")
    assert has_element?(view, "#menu-qr-my-orders", "Orders")
    assert has_element?(view, "#menu-qr-rewards", "Rewards")
    assert has_element?(view, "#menu-qr-my-orders .hero-shopping-bag")
    assert has_element?(view, "#menu-qr-rewards .hero-gift")
    refute render(view) =~ "My Order ·"
    refute has_element?(view, "#menu-qr-my-orders", "My")

    nav_html = view |> element("#menu-qr-customer-nav") |> render()
    assert nav_html =~ "menu-qr-customer-nav"
    assert nav_html =~ ~s(id="menu-qr-my-orders")
    assert nav_html =~ ~s(id="menu-qr-rewards")
    # Separate pills: each button carries its own surface styles (not one shared shell).
    assert nav_html =~ "menu-qr-customer-nav-btn"

    render_hook(view, "restore_my_orders", %{
      "numbers" => [received.number, ready.number]
    })

    assert has_element?(view, "#menu-qr-my-orders", "Orders")
    assert has_element?(view, "#menu-qr-rewards", "Rewards")
    assert has_element?(view, "#menu-qr-my-orders.menu-qr-my-orders--status")

    view |> element("#menu-qr-rewards") |> render_click()
    assert has_element?(view, "#menu-my-orders-panel")
    assert has_element?(view, "#menu-my-orders-title", "ELIlai Rewards")
    assert has_element?(view, "#menu-my-orders-rewards")
    refute has_element?(view, "#menu-my-orders-tabs")
    refute has_element?(view, "#menu-my-orders-tab-orders")
    refute has_element?(view, "#menu-my-orders-tab-rewards")
    refute has_element?(view, "#menu-my-orders-orders")
    refute has_element?(view, "#menu-qr-customer-nav")

    view |> element("button.menu-my-orders-close") |> render_click()
    assert has_element?(view, "#menu-qr-customer-nav")
    view |> element("#menu-qr-my-orders") |> render_click()
    assert has_element?(view, "#menu-my-orders-title", "My Orders")
    assert has_element?(view, "#menu-my-orders-orders")
    refute has_element?(view, "#menu-my-orders-rewards")
    refute has_element?(view, "#menu-my-orders-tab-orders")
    refute has_element?(view, "#menu-my-orders-tab-rewards")
  end

  test "/menu All chip is first and shows multiple category sections", %{conn: conn, food: food} do
    insert_product!(food, "Beef Tapa", true, [{nil, "180"}])

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    labels =
      view
      |> element("#menu-craving")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("button.menu-craving-chip .menu-craving-label")
      |> Enum.map(fn node -> node |> Floki.text() |> String.trim() end)

    assert List.first(labels) == "All"
    assert has_element?(view, "#menu-craving-chip-HOT.is-active", "Hot coffee")
    refute has_element?(view, "#menu-craving-chip-ALL.is-active")
    assert has_element?(view, "#category-HOT")
    refute has_element?(view, "#category-COLD")

    view |> element("#menu-craving-chip-ALL") |> render_click()

    assert has_element?(view, "#menu-craving-chip-ALL.is-active", "All")
    refute has_element?(view, "#menu-craving-chip-HOT.is-active")
    assert has_element?(view, "#category-HOT")
    assert has_element?(view, "#category-COLD")
    assert has_element?(view, "#category-FRAPPE")
    assert has_element?(view, "#category-SODA")
    assert has_element?(view, "#category-FOOD")
    assert has_element?(view, ".brune-menu-item-card")
    assert has_element?(view, ".brune-menu-item-name", "Espresso")
    assert has_element?(view, ".brune-menu-item-name", "Hazelnut")
    assert has_element?(view, ".brune-menu-item-name", "Beef Tapa")
  end

  test "/menu search expands beside Categories title above chips", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    assert has_element?(view, ".menu-craving-head #menu-qr-search-toggle")
    assert has_element?(view, ".menu-craving-head #menu-search")
    assert has_element?(view, "#menu-craving-context", "Categories")
    refute has_element?(view, "#menu-search.is-open")

    html =
      view
      |> element("#menu-qr-sticky")
      |> render()
      |> Floki.parse_fragment!()

    sticky_ids =
      html
      |> Floki.find("#menu-qr-chrome, #menu-craving")
      |> Enum.map(fn {_, attrs, _} ->
        attrs |> Enum.find_value(fn {k, v} -> if k == "id", do: v end)
      end)

    assert sticky_ids == ["menu-qr-chrome", "menu-craving"]
    assert has_element?(view, "#menu-search-input")

    view |> element("#menu-qr-search-toggle") |> render_click()
    assert has_element?(view, "#menu-search.is-open")
    assert has_element?(view, ".menu-craving-head #menu-search.is-open")
  end

  test "/menu?stage=menu&category=ALL restores All browse on mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=ALL")

    assert has_element?(view, "#menu-craving-chip-ALL.is-active", "All")
    assert has_element?(view, "#category-HOT")
    assert has_element?(view, "#category-COLD")
    refute has_element?(view, "#menu-landing")
  end

  test "/menu All keeps HOT as default entry and Matcha/Sweets intact", %{
    conn: conn,
    hot: hot,
    cold: cold,
    food: food
  } do
    insert_product!(hot, "Matcha Latte", true, [{"12oz", "160"}])
    insert_product!(cold, "Matcha Caramel", true, [{"16oz", "180"}])
    insert_product!(food, "Dark Choco Dream Cake", true, [{nil, "120"}])
    insert_product!(food, "Beef Tapa", true, [{nil, "180"}])

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu")

    assert has_element?(view, "#menu-craving-chip-HOT.is-active", "Hot coffee")
    refute has_element?(view, "#menu-craving-chip-ALL.is-active")
    assert has_element?(view, "#category-HOT")
    refute has_element?(view, "#category-FOOD")

    view |> element("#menu-craving-chip-ALL") |> render_click()
    assert has_element?(view, "#menu-craving-chip-ALL.is-active", "All")

    view |> element("#menu-craving-chip-matcha") |> render_click()
    assert has_element?(view, "#menu-craving-chip-matcha.is-active", "Matcha")
    assert has_element?(view, ".brune-menu-item-name", "Matcha Latte")
    assert has_element?(view, ".brune-menu-item-name", "Matcha Caramel")
    refute has_element?(view, ".brune-menu-item-name", "Beef Tapa")

    view |> element("#menu-craving-chip-sweets") |> render_click()
    assert has_element?(view, "#menu-craving-chip-sweets.is-active", "Sweets")
    assert has_element?(view, ".brune-menu-item-name", "Dark Choco Dream Cake")
    refute has_element?(view, ".brune-menu-item-name", "Beef Tapa")

    {:ok, hot_view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    assert has_element?(hot_view, "#menu-craving-chip-HOT.is-active", "Hot coffee")
    assert has_element?(hot_view, "#category-HOT")
    refute has_element?(hot_view, "#category-COLD")
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
             ~s(.brune-menu-item-photo[src="/images/coffeespot/gen-hot-americano.png"][alt="Americano"])
           )

    assert has_element?(
             view,
             ~s(.brune-menu-item-photo[src="/images/coffeespot/gen-hot-espresso.png"][alt="Espresso"])
           )

    assert has_element?(view, ".menu-temp-badge.menu-temp-badge--hot", "Hot")
    refute has_element?(view, ".menu-card-initial")
    refute has_element?(view, "#category-COLD")
    refute html =~ "Hazelnut"
  end

  test "/menu displays only the selected category", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    view |> element("#menu-craving-chip-COLD") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-COLD")
    assert has_element?(view, "#menu-craving-chip-COLD.is-active", "Iced coffee")
    assert has_element?(view, ".menu-temp-badge.menu-temp-badge--iced", "Iced")
    assert html =~ "Hazelnut"
    refute has_element?(view, "#category-HOT")
    refute html =~ "Americano"

    view |> element("#menu-craving-chip-FRAPPE") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-FRAPPE")
    assert has_element?(view, "#menu-craving-chip-FRAPPE.is-active", "Frappe")
    assert html =~ "Biscoff"
    refute has_element?(view, "#category-COLD")

    view |> element("#menu-craving-chip-SODA") |> render_click()
    html = render(view)
    assert has_element?(view, "#category-SODA")
    assert has_element?(view, "#menu-craving-chip-SODA.is-active", "Soda")
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
    insert_product!(food, "Slow-Roasted Chicken Sourdough", true, [{nil, "249"}])
    insert_product!(food, "Big Assorted Muffin", true, [{nil, "99"}])
    insert_product!(food, "Choco Chip Cookies", true, [{nil, "65"}])

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view |> element("#menu-craving-chip-FOOD") |> render_click()
    html = render(view)

    assert has_element?(view, "#category-FOOD")
    assert html =~ "Rice Meal"
    assert html =~ "Appetizers"
    assert has_element?(view, ".brune-menu-subgroup", "Sandwiches & Wraps")
    assert html =~ "Muffins"
    assert html =~ "Cakes / Breads"
    assert html =~ "Chicken Flakes"
    assert html =~ "Solo Fries"
    assert html =~ "Slow-Roasted Chicken Sourdough"
    assert html =~ "Big Assorted Muffin"
    assert html =~ "Choco Chip Cookies"
    assert html =~ "₱179"
    assert html =~ "₱99"
    assert html =~ "₱249"
    assert html =~ "₱65"

    rice_index = :binary.match(html, "Rice Meal") |> elem(0)
    appetizers_index = :binary.match(html, "Appetizers") |> elem(0)
    sandwiches_index = :binary.match(html, "Sandwiches &amp; Wraps") |> elem(0)
    muffins_index = :binary.match(html, "Muffins") |> elem(0)
    cakes_index = :binary.match(html, "Cakes / Breads") |> elem(0)

    assert rice_index < appetizers_index
    assert appetizers_index < sandwiches_index
    assert sandwiches_index < muffins_index
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

    view |> element("#menu-craving-chip-FOOD") |> render_click()
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
    assert has_element?(view, "#menu-detail")
    assert has_element?(view, "#menu-detail-title", "Espresso")
    view |> element("button.menu-buy-now", "Add to your order") |> render_click()
    assert has_element?(view, ".brune-bag-count", "1")
    assert has_element?(view, "#menu-qr-bag.is-bag-confirm")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    html = render(view)

    assert has_element?(view, "#menu-detail")
    assert html =~ "8oz"
    assert html =~ "12oz"
    assert html =~ "₱110"

    view |> element("#menu-craving-chip-COLD") |> render_click()
    html = render(view)
    assert html =~ "₱180"

    view |> element("#menu-craving-chip-SODA") |> render_click()
    html = render(view)
    assert html =~ "₱120"
  end

  test "/menu filters categories from QR rail", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    assert has_element?(view, "#menu-craving-chip-HOT.is-active", "Hot coffee")
    assert has_element?(view, "#category-HOT")
    refute has_element?(view, ".brune-menu-tabs-line")

    view |> element("#menu-craving-chip-COLD") |> render_click()

    assert has_element?(view, "#menu-craving-chip-COLD.is-active", "Iced coffee")
    assert has_element?(view, "#category-COLD")
    refute has_element?(view, "#category-HOT")
  end

  test "/menu QR rail is the single category navigation", %{conn: conn, food: food} do
    insert_product!(food, "Beef Tapa", true, [{nil, "180"}])

    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    assert has_element?(view, "#menu-craving.menu-craving--sticky")
    assert has_element?(view, "#menu-craving-context", "Categories")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Hot coffee")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Iced coffee")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Frappe")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Soda")
    assert has_element?(view, "#menu-craving button.menu-craving-chip", "Food")
    assert has_element?(view, "#menu-craving-chip-matcha", "Matcha")
    assert has_element?(view, "#menu-craving-chip-sweets", "Sweets")
    refute has_element?(view, ".brune-menu-tabs-line")
    refute has_element?(view, "#menu-craving-title")
    refute has_element?(view, "#menu-craving-chooser")

    assert has_element?(view, "#menu-craving button.menu-craving-chip.is-active", "Hot coffee")
    assert has_element?(view, "#category-HOT")

    view |> element("#menu-craving button.menu-craving-chip", "Iced coffee") |> render_click()

    assert has_element?(view, "#menu-craving button.menu-craving-chip.is-active", "Iced coffee")
    assert has_element?(view, "#category-COLD")
    refute has_element?(view, "#category-HOT")
    assert has_element?(view, "#menu-items", "Hazelnut")

    view |> element("#menu-craving-chip-SODA") |> render_click()

    assert has_element?(view, "#menu-craving button.menu-craving-chip.is-active", "Soda")
    assert has_element?(view, "#category-SODA")

    view |> element("#menu-craving button.menu-craving-chip", "Food") |> render_click()

    assert has_element?(view, "#menu-craving button.menu-craving-chip.is-active", "Food")
    assert has_element?(view, "#category-FOOD")
    assert has_element?(view, "#menu-items", "Beef Tapa")

    assert has_element?(view, "#menu-search")
    view |> form("#menu-search form", %{search: "Espresso"}) |> render_change()
    assert has_element?(view, "#menu-items", "Espresso")
    assert has_element?(view, "#menu-craving")
  end

  test "/menu shows product description in detail when present", %{conn: conn, hot: hot} do
    insert_product!(
      hot,
      "Spanish Latte",
      true,
      [{"8oz", "160"}, {"12oz", "170"}],
      "Rich and creamy"
    )

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view |> element("button[aria-label='Add Spanish Latte']") |> render_click()

    assert has_element?(view, ".menu-detail-description", "Rich and creamy")
  end

  test "/menu order links open modal and toast into basket", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    assert has_element?(view, "#menu-qr-sticky")
    assert has_element?(view, "#menu-craving.menu-craving--sticky")
    assert has_element?(view, "button.brune-icon-bag[aria-label='Your order, 0 items']")
    refute has_element?(view, "#menu-qr-sticky #menu-qr-my-orders")
    refute has_element?(view, ".brune-menu-tabs-line")
    refute has_element?(view, ".brune-bag-count")

    view = add_to_order(view, "Espresso")
    refute has_element?(view, "#menu-detail")
    refute has_element?(view, "#menu-basket")
    refute has_element?(view, ".menu-toast", "Added to bag")
    assert has_element?(view, "#menu-qr-bag.is-bag-confirm")
    assert has_element?(view, ".menu-qr-bag-plus", "+1")
    assert has_element?(view, ".brune-bag-count", "1")
    assert has_element?(view, "button.brune-menu-add--icon[aria-label='Add Espresso'] .hero-plus")

    view |> element("#menu-qr-bag") |> render_click()
    assert has_element?(view, "#menu-basket")
    assert has_element?(view, ".menu-basket-layer--fullscreen")
    assert has_element?(view, ".menu-basket-panel--fullscreen")
    assert has_element?(view, "#menu-basket-title", "Your order")
    assert has_element?(view, ".menu-basket-line-name", "Espresso")

    assert has_element?(
             view,
             ~s(.menu-basket-line-photo[src="/images/coffeespot/gen-hot-espresso.png"])
           )

    view |> element("button[aria-label='Back to menu']") |> render_click()
    Process.sleep(300)
    html = render(view)
    refute html =~ ~s(id="menu-basket")
    assert has_element?(view, ".brune-bag-count", "1")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    assert has_element?(view, "#menu-detail")
    assert has_element?(view, "#menu-detail-title", "Americano")

    view |> element("button.menu-size-pill", "12oz") |> render_click()
    view |> element("button.menu-buy-now", "Add to your order") |> render_click()

    assert has_element?(view, ".brune-bag-count", "2")
    assert has_element?(view, "#menu-qr-bag.is-bag-confirm")
    refute has_element?(view, ".menu-toast", "Added to bag")

    view |> element("button.brune-icon-bag") |> render_click()
    assert has_element?(view, ".menu-basket-line-name", "Americano")
    assert has_element?(view, ".menu-basket-line-size", "12oz")

    assert has_element?(view, "button.menu-basket-checkout", "Enter your details")
    assert has_element?(view, "#menu-basket-submit")
    assert has_element?(view, "#menu-basket-submit .menu-basket-total strong", "₱195")
    assert has_element?(view, ".menu-basket-total-meta", "2 items total")
    refute has_element?(view, ".menu-checkout-payment .menu-checkout-option")

    view |> element("button.menu-basket-checkout", "Enter your details") |> render_click()
    assert has_element?(view, "#menu-checkout-summary", "Please enter your name.")

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Juan"
    })
    |> render_change()

    refute has_element?(view, "#menu-checkout-summary")
    refute has_element?(view, ".menu-checkout-payment .menu-checkout-option")

    assert has_element?(
             view,
             "button.menu-basket-checkout[data-dismiss-keyboard]",
             "Place order"
           )

    assert has_element?(
             view,
             ".menu-checkout-payment-note",
             "Pay at the counter when your order is ready."
           )

    refute has_element?(view, ".menu-basket-submit-payment")
    refute has_element?(view, ".menu-basket-alt-label")
    refute has_element?(view, ".menu-basket-body .menu-basket-alt")
    refute has_element?(view, "a.menu-basket-whatsapp")
    refute has_element?(view, "#checkout-notes-trigger")
    refute has_element?(view, "#checkout-notes")

    {:ok, order_view, html} =
      view
      |> element("button.menu-basket-checkout", "Place order")
      |> render_click()
      |> follow_redirect(conn)

    assert html =~ ~r/CS-[2-9A-HJ-NP-Z]{6}/
    assert has_element?(order_view, "#order-confirm")
    assert has_element?(order_view, "#order-confirm-title", "Order confirmed")
    assert has_element?(order_view, "#order-confirm-number")
    assert has_element?(order_view, "#order-view-my-order", "View My Order")
    assert has_element?(order_view, "#order-order-more", "Order More")

    order_number =
      order_view
      |> element("#order-confirm-number")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()
      |> String.trim()

    assert order_number =~ ~r/^CS-[2-9A-HJ-NP-Z]{6}$/

    view_href =
      order_view
      |> element("#order-view-my-order")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> List.first()

    more_href =
      order_view
      |> element("#order-order-more")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> List.first()

    assert view_href == "/order/#{order_number}"
    assert more_href == "/menu?stage=menu"

    {:ok, detail_view, _html} =
      order_view
      |> element("#order-view-my-order", "View My Order")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(detail_view, ".order-number", order_number)
    assert has_element?(detail_view, "#order-status-message", "Received — kitchen has it")
    assert has_element?(detail_view, ".order-card", "Juan")
    assert render(detail_view) =~ "Dine-in"
    refute render(detail_view) =~ "Table 7"
    assert render(detail_view) =~ "Pay at counter"
    assert has_element?(detail_view, "#order-receipt", "Espresso")
    assert has_element?(detail_view, "#order-receipt", "Americano")
    refute has_element?(detail_view, "#order-confirm")
  end

  test "/menu Cash at counter persists intent without settling payment", %{conn: conn} do
    set_payments_mode!("qrph_manual")
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{customer_name: "Cash Guest"})
    |> render_change()

    view |> element("#checkout-pay-counter") |> render_click()

    {:ok, _order_view, _html} =
      view
      |> element("button.menu-basket-checkout", "Place order")
      |> render_click()
      |> follow_redirect(conn)

    [order] = Orders.list_active_orders()
    assert order.source == "customer"
    assert order.payment_method == "counter"
    assert order.payment_intent == "cash"
    assert order.payment_status == "unpaid"
    assert order.paid_via == nil
  end

  test "/menu GCash checkout creates unpaid order and redirects to PayMongo", %{conn: conn} do
    set_payments_mode!("paymongo")
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Gina"
    })
    |> render_change()

    view |> element("button.menu-checkout-option", "GCash") |> render_click()
    refute has_element?(view, ".menu-checkout-payment-info")
    refute has_element?(view, ".menu-basket-submit-payment")

    assert has_element?(
             view,
             ".menu-checkout-payment-note",
             "Continue to PayMongo to complete payment."
           )

    assert has_element?(view, "button.menu-basket-checkout", "Continue to GCash")

    assert {:error, {:redirect, %{to: checkout_url}}} =
             view
             |> element("button.menu-basket-checkout", "Continue to GCash")
             |> render_click()

    assert checkout_url =~ "checkout.paymongo.test"

    [order] = Orders.list_active_orders()
    assert order.customer_name == "Gina"
    assert order.source == "customer"
    assert order.payment_method == "online"
    assert order.payment_intent == "gcash"
    assert order.payment_status == "unpaid"
    assert order.paid_via == nil
    assert is_binary(order.paymongo_checkout_session_id)
  end

  test "/menu Maya checkout shows Continue to Maya CTA and starts PayMongo flow", %{conn: conn} do
    set_payments_mode!("paymongo")
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Maya Test"
    })
    |> render_change()

    view |> element("button.menu-checkout-option", "Maya") |> render_click()
    assert has_element?(view, "button.menu-basket-checkout", "Continue to Maya")
    refute has_element?(view, ".menu-checkout-payment-info")
    refute has_element?(view, ".menu-basket-submit-payment")

    assert {:error, {:redirect, %{to: checkout_url}}} =
             view
             |> element("button.menu-basket-checkout", "Continue to Maya")
             |> render_click()

    assert checkout_url =~ "checkout.paymongo.test"

    [order] = Orders.list_active_orders()
    assert order.customer_name == "Maya Test"
    assert order.source == "customer"
    assert order.payment_method == "online"
    assert order.payment_intent == "maya"
    assert order.payment_status == "unpaid"
    assert order.paid_via == nil
  end

  test "/menu QRPh GCash checkout places awaiting_payment order without PayMongo", %{conn: conn} do
    set_payments_mode!("qrph_manual")
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: "QR Guest"
    })
    |> render_change()

    view |> element("button.menu-checkout-option", "GCash") |> render_click()
    assert has_element?(view, ".menu-checkout-payment-note", "Scan QR at counter after this.")

    {:ok, order_view, _html} =
      view
      |> element("button.menu-basket-checkout", "Place order")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(order_view, "#order-confirm")
    assert has_element?(order_view, "#order-chrome-title", "Pay at counter")
    assert has_element?(order_view, ~s(#order-confirm-qrph-open-gcash[href="gcash://"]))
    refute has_element?(order_view, "#order-confirm-title")
    refute render(order_view) =~ "/images/coffeespot/gcash-qrph.png"
    [order] = Orders.list_active_orders()
    assert order.customer_name == "QR Guest"
    assert order.payment_method == "online"
    assert order.payment_status == "awaiting_payment"
    assert order.payment_intent == "gcash"
    assert is_nil(order.paymongo_checkout_session_id)
  end

  test "/menu cancels orphan order when PayMongo checkout creation fails", %{conn: conn} do
    set_payments_mode!("paymongo")
    original = Application.get_env(:espreso, :paymongo)

    on_exit(fn ->
      Application.put_env(:espreso, :paymongo, original)
    end)

    Application.put_env(
      :espreso,
      :paymongo,
      Keyword.put(original, :client, EspresoWeb.MenuLiveTest.FailingCheckoutClient)
    )

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = prepare_gcash_checkout(view, "Checkout Fail")

    html =
      view
      |> element("button.menu-basket-checkout", "Continue to GCash")
      |> render_click()

    assert html =~ "Could not start online payment"
    assert Orders.list_active_orders() == []

    assert [%{status: "cancelled", payment_status: "unpaid", paymongo_checkout_session_id: nil}] =
             orders_named("Checkout Fail")
  end

  test "/menu cancels orphan order when session attach fails", %{conn: conn} do
    set_payments_mode!("paymongo")
    original = Application.get_env(:espreso, :paymongo)

    on_exit(fn ->
      Application.put_env(:espreso, :paymongo, original)
    end)

    {:ok, blocker} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Session Blocker",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, blocker} = Orders.attach_paymongo_session(blocker, "cs_menu_attach_taken")

    Application.put_env(
      :espreso,
      :paymongo,
      Keyword.put(original, :client, EspresoWeb.MenuLiveTest.FixedSessionClient)
    )

    {:ok, view, _html} = live(conn, ~p"/menu")
    view = prepare_gcash_checkout(view, "Attach Fail")

    html =
      view
      |> element("button.menu-basket-checkout", "Continue to GCash")
      |> render_click()

    assert html =~ "Could not start online payment"
    refute Enum.any?(Orders.list_active_orders(), &(&1.customer_name == "Attach Fail"))

    assert [%{status: "cancelled", payment_status: "unpaid", paymongo_checkout_session_id: nil}] =
             orders_named("Attach Fail")

    # Blocker with the taken session remains active until staff abandons it.
    assert Enum.any?(Orders.list_active_orders(), &(&1.id == blocker.id))
  end

  test "/menu Order More returns to menu browse with an empty cart", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Ana"
    })
    |> render_change()

    {:ok, confirm_view, _html} =
      view
      |> element("button.menu-basket-checkout", "Place order")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(confirm_view, "#order-confirm")
    assert has_element?(confirm_view, ~s(#order-confirm[phx-hook="OrderConfirm"]))
    assert has_element?(confirm_view, ~s(#order-confirm[data-order-number]))

    order_number =
      confirm_view
      |> element("#order-confirm-number")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()
      |> String.trim()

    {:ok, menu_view, html} =
      confirm_view
      |> element("#order-order-more", "Order More")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(menu_view, "#menu-items")
    refute has_element?(menu_view, "#menu-landing")
    refute has_element?(menu_view, "#menu-craving-chooser")
    refute has_element?(menu_view, ".brune-bag-count")
    refute has_element?(menu_view, "#menu-basket")
    refute has_element?(menu_view, "#menu-detail")
    assert html =~ ~s(data-cart="[]")
    assert Orders.list_active_orders() != []

    render_hook(menu_view, "restore_my_orders", %{"numbers" => [order_number]})

    assert has_element?(menu_view, "#menu-qr-my-orders", "Orders")
    menu_view |> element("#menu-qr-my-orders") |> render_click()
    assert has_element?(menu_view, "#menu-my-orders-panel")
    assert has_element?(menu_view, "#menu-my-orders-active-heading", "Active")
    assert has_element?(menu_view, "#menu-my-order-#{order_number}", order_number)

    {:ok, detail_view, _html} =
      menu_view
      |> element("#menu-my-order-#{order_number} a.menu-my-orders-view", "View Order")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(detail_view, ".order-number", order_number)
    assert has_element?(detail_view, "#order-status-message", "Received — kitchen has it")
  end

  test "/menu My Orders restores multiple orders and appends instead of replacing", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    refute has_element?(view, "#menu-qr-my-orders")

    {:ok, first} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "First",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, second} =
      Orders.create_order(
        [%{name: "Americano", size: "8oz", quantity: 2, price: Decimal.new("110")}],
        %{
          customer_name: "Second",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, third} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Third",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    render_hook(view, "restore_my_orders", %{
      "numbers" => [first.number, second.number, third.number, first.number]
    })

    assert has_element?(view, "#menu-qr-my-orders", "Orders")
    view |> element("#menu-qr-my-orders") |> render_click()

    assert has_element?(view, "#menu-my-order-#{first.number}")
    assert has_element?(view, "#menu-my-order-#{second.number}")
    assert has_element?(view, "#menu-my-order-#{third.number}")
    assert has_element?(view, "#menu-my-order-#{second.number}", "2 items")
    assert has_element?(view, "#menu-my-order-#{second.number}", "₱220")

    html = view |> element("#menu-my-orders-panel") |> render()
    first_matches = Regex.scan(~r/id="menu-my-order-#{Regex.escape(first.number)}"/, html)
    assert length(first_matches) == 1
  end

  test "/menu floating My Orders stays outside sticky and hides under overlays", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Float", fulfillment: :pickup, payment_method: :counter}
      )

    render_hook(view, "restore_my_orders", %{"numbers" => [order.number]})

    assert has_element?(view, "#menu-qr-my-orders", "Orders")
    refute has_element?(view, "#menu-qr-sticky #menu-qr-my-orders")

    view |> element("#menu-qr-my-orders") |> render_click()
    assert has_element?(view, "#menu-my-orders-panel")
    refute has_element?(view, "#menu-qr-my-orders")

    view |> element("button.menu-my-orders-close") |> render_click()
    assert has_element?(view, "#menu-qr-my-orders", "Orders")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    assert has_element?(view, "#menu-detail")
    refute has_element?(view, "#menu-qr-my-orders")

    view |> element("button[aria-label='Back to menu']") |> render_click()
    Process.sleep(300)
    assert has_element?(view, "#menu-qr-my-orders", "Orders")

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()
    assert has_element?(view, "#menu-basket")
    refute has_element?(view, "#menu-qr-my-orders")
  end

  test "/menu My Orders splits active and history by status", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    {:ok, received} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Rec", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, preparing} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Prep", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, ready} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Ready", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, completed} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 3, price: Decimal.new("75")}],
        %{customer_name: "Done", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, cancelled} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Cancel", fulfillment: :pickup, payment_method: :counter}
      )

    assert {:ok, _} = Orders.mark_paid(preparing)
    assert {:ok, preparing} = Orders.update_status(preparing, "preparing")
    assert {:ok, _} = Orders.mark_paid(ready)
    assert {:ok, ready} = Orders.update_status(ready, "ready")
    assert {:ok, _} = Orders.mark_paid(completed)
    assert {:ok, completed_ready} = Orders.update_status(completed, "ready")
    assert {:ok, completed} = Orders.complete_order(completed_ready)
    assert {:ok, _} = Orders.cancel_order(cancelled)

    render_hook(view, "restore_my_orders", %{
      "numbers" => [
        received.number,
        preparing.number,
        ready.number,
        completed.number,
        cancelled.number
      ]
    })

    assert has_element?(view, "#menu-qr-my-orders", "Orders")
    refute has_element?(view, ".menu-qr-my-orders-badge")
    refute has_element?(view, "#menu-qr-sticky #menu-qr-my-orders")

    view |> element("#menu-qr-my-orders") |> render_click()

    assert has_element?(view, "#menu-my-orders-active-heading", "Active")
    assert has_element?(view, "#menu-my-orders-history-heading", "History")
    assert has_element?(view, "#menu-my-order-#{received.number}", "Pay at counter")
    assert has_element?(view, "#menu-my-order-#{received.number} .menu-my-orders-status--unpaid")
    assert has_element?(view, "#menu-my-order-#{preparing.number}", "Preparing")
    assert has_element?(view, "#menu-my-order-#{ready.number}", "Ready — come to counter")
    assert has_element?(view, "#menu-my-order-#{ready.number} .menu-my-orders-status--ready")
    assert has_element?(view, "#menu-my-order-#{completed.number}", "Picked up ✓")
    assert has_element?(view, "#menu-my-order-#{completed.number}", "3 items")
    assert has_element?(view, "#menu-my-order-#{completed.number} .menu-my-orders-when", "Today")
    refute has_element?(view, "#menu-my-order-#{cancelled.number}")
    refute has_element?(view, "#menu-qr-my-orders")

    assert {:ok, _} = Orders.mark_paid(ready)
    assert {:ok, completed_ready_again} = Orders.complete_order(ready)
    assert completed_ready_again.status == "completed"
    refute has_element?(view, ~s(#menu-my-order-#{ready.number}[data-status="ready"]))
    assert has_element?(view, ~s(#menu-my-order-#{ready.number}[data-status="completed"]))
    assert has_element?(view, "#menu-my-order-#{ready.number}", "Picked up ✓")
  end

  test "/menu My Orders ignores malformed and missing numbers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Keep", fulfillment: :pickup, payment_method: :counter}
      )

    render_hook(view, "restore_my_orders", %{
      "numbers" => ["not-an-order", "CS-222222", order.number, "12"]
    })

    assert has_element?(view, "#menu-qr-my-orders")
    view |> element("#menu-qr-my-orders") |> render_click()
    assert has_element?(view, "#menu-my-order-#{order.number}")

    render_hook(view, "restore_my_orders", %{"numbers" => []})
    refute has_element?(view, "#menu-qr-my-orders")
  end

  test "/menu checkout places pickup order without notes field", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    refute has_element?(view, "#checkout-notes-trigger")
    refute has_element?(view, "#checkout-notes")

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Ana Lee"
    })
    |> render_change()

    view |> element("button.menu-checkout-option", "Takeout") |> render_click()

    {:ok, _order_view, _html} =
      view
      |> element("button.menu-basket-checkout", "Place order")
      |> render_click()
      |> follow_redirect(conn)

    [order] = Orders.list_active_orders()
    assert order.customer_name == "Ana Lee"
    assert order.notes == nil
    assert order.fulfillment == "pickup"
  end

  test "B1 checkout shows Takeout hint and hides Maya without QR", %{
    conn: conn
  } do
    set_payments_mode!("qrph_manual")
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    refute has_element?(view, "#checkout-table")
    assert has_element?(view, "#menu-checkout-payment")
    assert has_element?(view, "#checkout-pay-counter")
    assert has_element?(view, "#checkout-pay-gcash")
    refute has_element?(view, "#checkout-pay-maya")
    refute has_element?(view, "#menu-checkout-form button.menu-checkout-option.is-active")

    view |> element("#checkout-fulfillment-pickup") |> render_click()
    refute has_element?(view, "#checkout-table")
    assert has_element?(view, "#checkout-pickup-hint", "Takeout")
    assert has_element?(view, "#checkout-fulfillment-pickup.is-active", "Takeout")
    refute has_element?(view, "#checkout-fulfillment-dine-in.is-active")
    refute has_element?(view, "#checkout-pay-counter.is-active")

    view |> element("#checkout-fulfillment-dine-in") |> render_click()
    refute has_element?(view, "#checkout-table")
    assert has_element?(view, "#checkout-fulfillment-dine-in.is-active", "Dine-in")

    view
    |> form("#menu-checkout-form", %{customer_name: "B1 Guest"})
    |> render_change()

    view |> element("#checkout-pay-gcash") |> render_click()
    assert has_element?(view, "#checkout-pay-gcash.is-active", "GCash")
    refute has_element?(view, "#checkout-pay-counter.is-active")
    assert has_element?(view, "#checkout-payment-note", "Scan QR at counter after this.")
    assert has_element?(view, "button.menu-basket-checkout", "Place order")
  end

  test "/menu legacy restore_current_order still hydrates My Orders", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Legacy", fulfillment: :pickup, payment_method: :counter}
      )

    render_hook(view, "restore_current_order", %{"number" => order.number})
    assert has_element?(view, "#menu-qr-my-orders", "Orders")
  end

  test "/menu confirmation page carries order number for client persistence", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Persist"
    })
    |> render_change()

    {:ok, confirm_view, html} =
      view
      |> element("button.menu-basket-checkout", "Place order")
      |> render_click()
      |> follow_redirect(conn)

    order_number =
      confirm_view
      |> element("#order-confirm-number")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()
      |> String.trim()

    assert order_number =~ ~r/^CS-[2-9A-HJ-NP-Z]{6}$/
    assert html =~ ~s(data-order-number="#{order_number}")
    assert has_element?(confirm_view, ~s(#order-confirm[data-order-number="#{order_number}"]))
  end

  test "/menu rejects place when a cart product becomes unavailable", %{
    conn: conn,
    espresso: espresso
  } do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")

    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: "Mia"
    })
    |> render_change()

    espresso
    |> Product.changeset(%{available: false})
    |> Repo.update!()

    view
    |> element("button.menu-basket-checkout", "Place order")
    |> render_click()

    assert has_element?(view, ".menu-toast", "Espresso is no longer available")
    assert has_element?(view, ".menu-basket-line-name", "Espresso")
    assert Orders.list_active_orders() == []
  end

  test "/menu basket keeps sticky submit outside checkout scroll", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "#menu-basket-panel .menu-basket-body")

    assert has_element?(
             view,
             "#menu-basket-panel .menu-basket-checkout-fields #menu-checkout-form"
           )

    refute has_element?(view, "#menu-basket-panel #menu-basket-submit")
    assert has_element?(view, "#menu-basket-submit.menu-basket-submit--floating")
    assert has_element?(view, "#menu-basket-submit .menu-basket-submit-row")
    assert has_element?(view, "#menu-basket-submit .menu-basket-total-meta")
    assert has_element?(view, "#menu-basket-submit button.menu-basket-checkout")
    refute has_element?(view, ".menu-checkout-payment-info")
    refute has_element?(view, ".menu-basket-submit-payment")
    refute has_element?(view, "#menu-basket-submit > .menu-basket-note")
    refute has_element?(view, "#menu-basket-submit .menu-basket-alt")
    refute has_element?(view, ".menu-basket-body .menu-basket-alt")
    refute has_element?(view, ".menu-basket-body button.menu-basket-checkout")
    refute has_element?(view, ".menu-basket-footer")

    view |> element("button.menu-checkout-option", "Takeout") |> render_click()
    refute has_element?(view, "#checkout-table")
    assert has_element?(view, "button.menu-checkout-option.is-active", "Takeout")

    assert has_element?(
             view,
             "#checkout-pickup-hint",
             "Takeout — pick up at the counter when ready."
           )

    view |> element("button.menu-basket-checkout", "Enter your details") |> render_click()
    assert has_element?(view, "#menu-checkout-summary", "Please enter your name.")
  end

  test "/menu keeps product-first chrome and CoffeeSpot footer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    refute has_element?(view, ".menu-qr-menu-bridge")
    assert has_element?(view, "#menu-qr-sticky")
    assert has_element?(view, "#menu-qr-chrome.menu-qr-top")
    assert has_element?(view, "#menu-qr-search-toggle")
    assert has_element?(view, "#menu-craving.menu-craving--sticky")
    assert has_element?(view, "#menu-craving-context", "Categories")
    assert has_element?(view, "#menu-qr-chrome")
    assert has_element?(view, ".menu-qr-chrome-brand", "CoffeeSpot")
    refute has_element?(view, "#menu-craving-chooser")
    refute has_element?(view, ".brune-menu-tabs-line")
    assert has_element?(view, "#menu-search.menu-qr-search-inline")
    refute has_element?(view, "#menu-search.is-open")
    assert has_element?(view, ".brune-student-promo")
    assert has_element?(view, ".brune-hours-strip")
    assert has_element?(view, "#brune-hours-strip-label", "Hours")
    assert has_element?(view, ".brune-hours-strip-line", "Sun–Wed · 11:00 AM – 11:00 PM")
    assert has_element?(view, ".brune-hours-strip-line", "Thu · 11:00 AM – 12:00 AM")
    assert has_element?(view, ".brune-hours-strip-line", "Fri–Sat · 11:00 AM – 2:00 AM")
    assert has_element?(view, ".brune-hours-strip-line--note", "Holiday hours on Instagram")
    assert has_element?(view, ".brune-mega-footer--secondary")
    assert has_element?(view, ".brune-mega-brand", "CoffeeSpot Marikina")
    assert has_element?(view, ".menu-footer-owned-label", "Owned and Operated by:")
    assert has_element?(view, ".menu-footer-owned-name", "Elilai Kafe")
    assert has_element?(view, "#menu-footer-instagram")
    assert has_element?(view, "#menu-footer-facebook")
    assert has_element?(view, "#menu-footer-tiktok")

    assert view
           |> element("#menu-footer-instagram")
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.attribute("href")
           |> List.first() == CoffeeSpot.instagram_url()

    refute has_element?(view, ".brune-mega-label", "Hours")
    refute has_element?(view, ".brune-mega-label", "Contact")
    refute has_element?(view, ".brune-mega-label", "Location")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-top-nav")
    refute has_element?(view, ".brune-menu-hero")
    refute has_element?(view, ".site-instagram-menu")
    refute has_element?(view, ~s([data-image-slot="menu-hero"]))
  end

  test "/menu floating bag discoverability", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    view = enter_menu_browse(view)

    refute has_element?(view, "#menu-floating-bag")

    view = add_to_order(view, "Espresso")
    assert has_element?(view, "#menu-floating-bag")
    assert has_element?(view, ".menu-floating-bag-count", "1")
    assert has_element?(view, ".menu-floating-bag-total", "₱75")
    assert has_element?(view, ".menu-floating-bag-cta", "View order")
    refute has_element?(view, ".menu-floating-bag-label")

    view |> element("#menu-floating-bag") |> render_click()
    assert has_element?(view, "#menu-basket")
    assert has_element?(view, ".menu-basket-panel--fullscreen")
    refute has_element?(view, "#menu-floating-bag")

    view |> element("button[aria-label='Back to menu']") |> render_click()
    Process.sleep(300)
    assert has_element?(view, "#menu-floating-bag")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    refute has_element?(view, "#menu-floating-bag")

    view |> element("button.menu-buy-now", "Add to your order") |> render_click()
    assert has_element?(view, "#menu-floating-bag")
    assert has_element?(view, ".menu-floating-bag-count", "2")
    assert has_element?(view, ".menu-floating-bag-total", "₱195")
  end

  test "/menu floating bag coexists with My Orders FAB", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Pat", fulfillment: :pickup, payment_method: :counter}
      )

    render_hook(view, "restore_my_orders", %{"numbers" => [order.number]})

    view = add_to_order(view, "Espresso")

    assert has_element?(view, "#menu-floating-bag")
    assert has_element?(view, "#menu-qr-customer-nav")
    assert has_element?(view, "#menu-qr-my-orders", "Orders")
    assert has_element?(view, "#menu-qr-rewards", "Rewards")
  end

  test "/menu floating bag is a single open_basket control", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")

    html = view |> element("#menu-floating-bag") |> render()
    assert html =~ ~s(phx-click="open_basket")
    assert html =~ "button"
    assert html =~ "menu-floating-bag-cta"
    assert html =~ "View order"
  end

  test "/menu?stage=craving restores craving chooser on mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=craving")

    assert has_element?(view, "#menu-craving-chooser")
    refute has_element?(view, "#menu-landing")
  end

  test "/menu?stage=visit restores visit panel on mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=visit")

    assert has_element?(view, "#menu-visit")
    assert has_element?(view, ".menu-qr-visit-title", "Visit CoffeeSpot")
    refute has_element?(view, "#menu-landing")
  end

  test "/menu?stage=menu&category=HOT restores menu browse on mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    assert has_element?(view, "#menu-items")
    assert has_element?(view, "#category-HOT")
    assert has_element?(view, "#menu-craving-chip-HOT.is-active", "Hot coffee")
    refute has_element?(view, "#menu-landing")
  end

  test "/menu?stage=menu&filter=matcha restores matcha filter on mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&filter=matcha")

    assert has_element?(view, "#menu-craving-chip-matcha.is-active", "Matcha")
    refute has_element?(view, "#menu-landing")
  end

  test "/menu?table=12&stage=menu&category=HOT preserves dine-in on mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?table=12&stage=menu&category=HOT")

    assert has_element?(view, "#menu-items")

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "button.menu-checkout-option.is-active", "Dine-in")
    refute has_element?(view, "#checkout-table")
  end

  test "/menu bag shows one quantity stepper per line", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    html =
      view
      |> element("#menu-basket")
      |> render()

    assert html
           |> Floki.parse_fragment!()
           |> Floki.find(".menu-basket-line .menu-qty")
           |> length() == 1
  end

  test "/menu item count uses total quantity for one product qty 2", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view = add_to_order(view, "Espresso")

    assert has_element?(view, ".brune-bag-count", "2")

    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, ".menu-basket-total-meta", "2 items total")
    assert has_element?(view, ".menu-basket-line-name", "Espresso")
    html = view |> element("#menu-basket") |> render()
    assert html |> Floki.parse_fragment!() |> Floki.find(".menu-basket-line") |> length() == 1
    assert has_element?(view, ".menu-basket-line .menu-qty span", "2")
  end

  test "/menu item count matches two distinct product lines", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    view |> element("button.menu-buy-now", "Add to your order") |> render_click()

    assert has_element?(view, ".brune-bag-count", "2")

    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, ".menu-basket-total-meta", "2 items total")
    assert has_element?(view, ".menu-basket-line-name", "Espresso")
    assert has_element?(view, ".menu-basket-line-name", "Americano")

    html = view |> element("#menu-basket") |> render()
    assert html |> Floki.parse_fragment!() |> Floki.find(".menu-basket-line") |> length() == 2
  end

  test "/menu restores a sanitized cart from client storage payload", %{
    conn: conn,
    espresso: espresso
  } do
    espresso = Repo.preload(espresso, :product_prices)
    price = List.first(espresso.product_prices)

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    render_hook(view, "restore_cart", %{
      "cart" => [
        %{
          "key" => "#{espresso.id}:#{price.id}",
          "product_id" => espresso.id,
          "name" => espresso.name,
          "size" => price.size,
          "price" => Decimal.to_string(price.price),
          "quantity" => 2,
          "image" => "/images/coffeespot/gen-hot-espresso.png"
        }
      ]
    })

    assert has_element?(view, ".brune-bag-count", "2")
    assert has_element?(view, "#menu-page[data-cart]")

    view |> element("button.brune-icon-bag") |> render_click()
    assert has_element?(view, ".menu-basket-total-meta", "2 items total")
    assert has_element?(view, ".menu-basket-line-name", "Espresso")
    assert has_element?(view, ".menu-basket-line .menu-qty span", "2")
  end

  test "/menu ignores malformed restored cart payloads", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    render_hook(view, "restore_cart", %{"cart" => "not-a-list"})
    refute has_element?(view, ".brune-bag-count")

    render_hook(view, "restore_cart", %{
      "cart" => [
        %{"product_id" => "nope", "quantity" => 1, "price" => "x", "name" => ""},
        %{"product_id" => 9_999_999, "quantity" => 1, "price" => "10", "name" => "Ghost"}
      ]
    })

    refute has_element?(view, ".brune-bag-count")
    assert has_element?(view, "button.brune-icon-bag[aria-label='Your order, 0 items']")
  end

  test "/menu plus opens detail sheet for all products", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    assert has_element?(view, "button.brune-menu-add--icon[aria-label='Add Espresso'] .hero-plus")

    assert has_element?(
             view,
             "button.brune-menu-add--icon[aria-label='Add Americano'] .hero-plus"
           )

    refute has_element?(view, "button.brune-menu-add--icon", "+ Add")
    refute has_element?(view, "button.brune-menu-add--icon", "Add")

    view |> element("button[aria-label='Add Espresso']") |> render_click()

    assert has_element?(view, "#menu-detail")
    assert has_element?(view, "#menu-detail-title", "Espresso")
    assert has_element?(view, ".menu-buy-hero .menu-buy-photo")
    assert has_element?(view, "button.menu-buy-now", "Add to your order")
    refute has_element?(view, ".menu-size-pill")

    view |> element("button.menu-buy-now", "Add to your order") |> render_click()
    assert has_element?(view, ".brune-bag-count", "1")
    assert has_element?(view, "#menu-qr-bag.is-bag-confirm")
    assert has_element?(view, ".menu-qr-bag-plus", "+1")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    assert has_element?(view, "#menu-detail")
    assert has_element?(view, ".menu-size-pill", "8oz")
  end

  test "/menu product detail shows price before quantity and omits empty order link", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view |> element("button[aria-label='Add Americano']") |> render_click()

    assert has_element?(view, "#menu-detail.menu-buy-layer--sheet")
    assert has_element?(view, ".menu-buy-panel--sheet")
    assert has_element?(view, ".menu-buy-backdrop")
    assert has_element?(view, ".menu-buy-handle")
    assert has_element?(view, ".menu-buy-hero .menu-buy-photo")
    assert has_element?(view, ".menu-detail-heading")
    assert has_element?(view, ".menu-detail-options")
    assert has_element?(view, ".menu-buy-bar--detail button.menu-buy-now", "Add to your order")

    html = view |> element("#menu-detail") |> render()
    name_pos = :binary.match(html, "menu-detail-name") |> elem(0)
    price_pos = :binary.match(html, "menu-detail-price") |> elem(0)
    desc_pos = :binary.match(html, "menu-detail-description") |> elem(0)
    qty_pos = :binary.match(html, "menu-detail-qty-row") |> elem(0)
    cta_pos = :binary.match(html, "menu-buy-bar--detail") |> elem(0)

    assert name_pos < price_pos
    assert price_pos < desc_pos
    assert desc_pos < qty_pos
    assert qty_pos < cta_pos

    refute has_element?(view, ".menu-buy-basket-link")
    refute html =~ "View Your Order"
    refute html =~ "Place order"
    assert has_element?(view, "button.menu-buy-hero-back[aria-label='Back to menu']")
    assert has_element?(view, ".menu-buy-hero-back .hero-arrow-left")
  end

  test "/menu product detail omits basket link even when cart has items", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")

    view |> element("button[aria-label='Add Americano']") |> render_click()
    assert has_element?(view, "#menu-detail.menu-buy-layer--sheet")
    refute has_element?(view, ".menu-buy-basket-link")
    refute has_element?(view, "#menu-detail button", "Place order")
    refute has_element?(view, "#menu-detail .menu-basket-checkout")

    view |> element("button[aria-label='Back to menu']") |> render_click()
    Process.sleep(300)
    assert has_element?(view, "#menu-floating-bag")
  end

  test "/menu Your Order keeps back control on the left", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    assert has_element?(view, "button.menu-basket-close[aria-label='Back to menu']")
    assert has_element?(view, ".menu-basket-close .hero-arrow-left")
  end

  defp enter_menu_browse(view) do
    view |> element("#menu-cta-view-menu") |> render_click()
    view
  end

  defp add_to_order(view, product_name) do
    view
    |> element("button[aria-label='Add #{product_name}']")
    |> render_click()

    view
    |> element("button.menu-buy-now", "Add to your order")
    |> render_click()

    view
  end

  defp prepare_gcash_checkout(view, customer_name) do
    set_payments_mode!("paymongo")
    view = enter_menu_browse(view)

    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: customer_name
    })
    |> render_change()

    view |> element("button.menu-checkout-option", "GCash") |> render_click()
    view
  end

  defp orders_named(name) do
    Enum.filter(Repo.all(Espreso.Orders.Order), &(&1.customer_name == name))
  end

  defp earn_ledger_count(order_id) when is_integer(order_id) do
    import Ecto.Query

    Repo.aggregate(
      from(e in Espreso.Loyalty.LedgerEntry,
        where: e.order_id == ^order_id and e.kind == "earn"
      ),
      :count,
      :id
    )
  end

  test "/menu loyalty phone Counter order earns after Mark Paid and Rewards shows 1 point", %{
    conn: conn
  } do
    cost = Espreso.Loyalty.redeem_cost()
    phone = "09175559901"
    customer_name = "QR Earn Guest"

    set_payments_mode!("qrph_manual")
    {:ok, view, _html} = live(conn, ~p"/menu")
    view = enter_menu_browse(view)

    # ₱75 × 3 = ₱225 ≥ ₱200 earn threshold
    view = add_to_order(view, "Espresso")
    view = add_to_order(view, "Espresso")
    view = add_to_order(view, "Espresso")
    view |> element("button.brune-icon-bag") |> render_click()

    view
    |> form("#menu-checkout-form", %{
      customer_name: customer_name,
      loyalty_phone: phone
    })
    |> render_change()

    view |> element("#checkout-pay-counter") |> render_click()

    {:ok, _order_view, _html} =
      view
      |> element("button.menu-basket-checkout", "Place order")
      |> render_click()
      |> follow_redirect(conn)

    [order] = orders_named(customer_name)
    assert order.source == "customer"
    assert order.payment_method == "counter"
    assert order.payment_status == "unpaid"
    assert is_integer(order.customer_id)
    assert Decimal.compare(order.total, Decimal.new("200")) != :lt

    customer = Repo.get!(Espreso.Customers.Customer, order.customer_id)
    assert customer.phone_e164 == "+639175559901"
    assert customer.points_balance == 0
    assert customer.spend_remainder_centavos == 0
    assert earn_ledger_count(order.id) == 0

    {:ok, rewards_view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    render_hook(rewards_view, "restore_my_orders", %{"numbers" => [order.number]})
    rewards_view |> element("#menu-qr-rewards") |> render_click()
    assert has_element?(rewards_view, "#menu-my-orders-rewards-balance", "0")
    assert has_element?(rewards_view, "#menu-my-orders-rewards-ratio", "0 / #{cost}")
    refute has_element?(rewards_view, "#menu-my-orders-rewards-unlocked")

    assert {:ok, :transitioned, paid} =
             Orders.mark_paid_with_transition(order, paid_via: "cash")

    assert paid.payment_status == "paid"
    assert paid.customer_id == order.customer_id

    customer = Repo.get!(Espreso.Customers.Customer, order.customer_id)
    assert customer.points_balance == 1
    assert earn_ledger_count(paid.id) == 1
    refute Espreso.Loyalty.earn_pending?(paid)

    {:ok, rewards_view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    render_hook(rewards_view, "restore_my_orders", %{"numbers" => [paid.number]})
    rewards_view |> element("#menu-qr-rewards") |> render_click()

    assert has_element?(rewards_view, "#menu-my-orders-rewards-balance", "1")
    assert has_element?(rewards_view, "#menu-my-orders-rewards-ratio", "1 / #{cost}")
    refute has_element?(rewards_view, "#menu-my-orders-rewards-unlocked")
  end

  test "/menu My Orders Rewards stays empty for anonymous-only orders", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Anon", fulfillment: :pickup, payment_method: :counter}
      )

    assert is_nil(order.customer_id)

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    render_hook(view, "restore_my_orders", %{"numbers" => [order.number]})
    view |> element("#menu-qr-rewards") |> render_click()
    assert has_element?(view, "#menu-my-orders-rewards-note", "loyalty phone")
    refute has_element?(view, "#menu-my-orders-rewards-balance")
    refute has_element?(view, "#menu-my-orders-rewards-ratio")
    refute has_element?(view, "#menu-my-orders-rewards-unlocked")
    refute render(view) =~ "0 Points"
  end

  test "/menu My Orders Rewards shows balance and progress below threshold", %{conn: conn} do
    cost = Espreso.Loyalty.redeem_cost()
    balance = 3
    more = max(cost - balance, 0)
    earn_pesos = div(Espreso.Loyalty.point_threshold_centavos(), 100)

    {:ok, customer} =
      Espreso.Customers.find_or_create_by_phone("09177770001", %{name: "Reward Guest"})

    customer =
      customer
      |> Ecto.Changeset.change(%{points_balance: balance})
      |> Repo.update!()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Reward Guest",
          fulfillment: :pickup,
          payment_method: :counter,
          customer_id: customer.id
        }
      )

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    render_hook(view, "restore_my_orders", %{"numbers" => [order.number]})
    view |> element("#menu-qr-rewards") |> render_click()

    html = render(view)
    assert has_element?(view, "#menu-my-orders-rewards-balance", "#{balance}")
    assert has_element?(view, "#menu-my-orders-rewards-balance", "Points")
    assert has_element?(view, "#menu-my-orders-rewards-ratio", "#{balance} / #{cost}")
    assert has_element?(view, "#menu-my-orders-rewards-progress", "#{more} more")
    assert has_element?(view, "#menu-my-orders-rewards-earn", "₱#{earn_pesos}")
    refute has_element?(view, "#menu-my-orders-rewards-unlocked")
    refute html =~ customer.phone_e164
    refute html =~ "Reward Guest"
    refute has_element?(view, "button", "Redeem")
  end

  test "/menu My Orders Rewards shows zero-point progress without unlocked state", %{conn: conn} do
    cost = Espreso.Loyalty.redeem_cost()

    {:ok, customer} =
      Espreso.Customers.find_or_create_by_phone("09177770007", %{name: "Zero Guest"})

    customer =
      customer
      |> Ecto.Changeset.change(%{points_balance: 0})
      |> Repo.update!()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Zero Guest",
          fulfillment: :pickup,
          payment_method: :counter,
          customer_id: customer.id
        }
      )

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    render_hook(view, "restore_my_orders", %{"numbers" => [order.number]})
    view |> element("#menu-qr-rewards") |> render_click()

    assert has_element?(view, "#menu-my-orders-rewards-balance", "0")
    assert has_element?(view, "#menu-my-orders-rewards-balance", "Points")
    assert has_element?(view, "#menu-my-orders-rewards-ratio", "0 / #{cost}")
    assert has_element?(view, "#menu-my-orders-rewards-progress", "#{cost} more")
    refute has_element?(view, "#menu-my-orders-rewards-unlocked")
    refute has_element?(view, "#menu-my-orders-rewards-status", "Reward Unlocked")

    progress =
      view
      |> element("#menu-my-orders-rewards-progress")
      |> render()

    assert progress =~ ~r/#{cost} more points? to unlock your free coffee/
    refute progress =~ ~r/\b0 more points?\b/
  end

  test "/menu My Orders Rewards shows counter-only unlocked state without redeem control", %{
    conn: conn
  } do
    {:ok, customer} =
      Espreso.Customers.find_or_create_by_phone("09177770002", %{name: "Eligible Guest"})

    customer =
      customer
      |> Ecto.Changeset.change(%{points_balance: Espreso.Loyalty.redeem_cost()})
      |> Repo.update!()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Eligible Guest",
          fulfillment: :pickup,
          payment_method: :counter,
          customer_id: customer.id
        }
      )

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    render_hook(view, "restore_my_orders", %{"numbers" => [order.number]})
    assert has_element?(view, "#menu-qr-rewards.menu-qr-rewards--available")
    assert has_element?(view, ".menu-qr-rewards-badge")

    view |> element("#menu-qr-rewards") |> render_click()

    html = render(view)
    assert has_element?(view, "#menu-my-orders-rewards-status", "Reward Unlocked")
    assert has_element?(view, "#menu-my-orders-rewards-reward", "Hot or Cold")
    assert has_element?(view, "#menu-my-orders-rewards-hint", "at the counter")
    refute has_element?(view, "#menu-my-orders-rewards-progress")
    refute has_element?(view, "#menu-my-orders-redeem")
    refute html =~ "phx-click=\"redeem"
    refute html =~ "Redeem reward"
    refute has_element?(view, "button", "Redeem")
  end

  test "/menu My Orders Rewards hides balances when multiple customers are present", %{conn: conn} do
    {:ok, a} = Espreso.Customers.find_or_create_by_phone("09177770003", %{name: "Guest A"})
    {:ok, b} = Espreso.Customers.find_or_create_by_phone("09177770004", %{name: "Guest B"})

    a = a |> Ecto.Changeset.change(%{points_balance: 12}) |> Repo.update!()
    b = b |> Ecto.Changeset.change(%{points_balance: 8}) |> Repo.update!()

    {:ok, order_a} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Guest A",
          fulfillment: :pickup,
          payment_method: :counter,
          customer_id: a.id
        }
      )

    {:ok, order_b} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Guest B",
          fulfillment: :pickup,
          payment_method: :counter,
          customer_id: b.id
        }
      )

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    render_hook(view, "restore_my_orders", %{
      "numbers" => [order_a.number, order_b.number]
    })

    view |> element("#menu-qr-my-orders") |> render_click()
    assert has_element?(view, "#menu-my-order-#{order_a.number}")
    assert has_element?(view, "#menu-my-order-#{order_b.number}")

    view |> element("button.menu-my-orders-close") |> render_click()
    view |> element("#menu-qr-rewards") |> render_click()
    assert has_element?(view, "#menu-my-orders-rewards-note", "unavailable")
    refute has_element?(view, "#menu-my-orders-rewards-balance")
    refute render(view) =~ "+63"
  end

  test "/menu My Orders Rewards resolves one customer even with an anonymous order present", %{
    conn: conn
  } do
    {:ok, customer} =
      Espreso.Customers.find_or_create_by_phone("09177770005", %{name: "Only One"})

    customer =
      customer
      |> Ecto.Changeset.change(%{points_balance: 5})
      |> Repo.update!()

    {:ok, linked} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Only One",
          fulfillment: :pickup,
          payment_method: :counter,
          customer_id: customer.id
        }
      )

    {:ok, anonymous} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Walk-in", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")

    render_hook(view, "restore_my_orders", %{
      "numbers" => [linked.number, anonymous.number]
    })

    view |> element("#menu-qr-rewards") |> render_click()

    assert has_element?(view, "#menu-my-orders-rewards-balance", "5")
    refute has_element?(view, "#menu-my-orders-rewards-note", "unavailable")
  end

  test "/menu My Orders Rewards activity only includes listed orders", %{conn: conn} do
    {:ok, customer} =
      Espreso.Customers.find_or_create_by_phone("09177770006", %{name: "Activity"})

    {:ok, listed} =
      Orders.create_order(
        [%{name: "Item", size: nil, quantity: 1, price: Decimal.new("200")}],
        %{
          customer_name: "Activity",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          customer_id: customer.id,
          skip_authoritative_prices: true
        }
      )

    {:ok, other} =
      Orders.create_order(
        [%{name: "Item", size: nil, quantity: 1, price: Decimal.new("200")}],
        %{
          customer_name: "Activity",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          customer_id: customer.id,
          skip_authoritative_prices: true
        }
      )

    {:ok, view, _html} = live(conn, ~p"/menu?stage=menu&category=HOT")
    render_hook(view, "restore_my_orders", %{"numbers" => [listed.number]})
    view |> element("#menu-qr-rewards") |> render_click()

    html = render(view)
    assert has_element?(view, "#menu-my-orders-rewards-activity")
    assert html =~ listed.number
    refute html =~ other.number
  end

  defp set_payments_mode!(mode) do
    attrs =
      case mode do
        "qrph_manual" ->
          %{
            payments_mode: mode,
            gcash_qrph_path: "/images/coffeespot/gcash-qrph.png",
            maya_qrph_path: nil
          }

        _ ->
          %{payments_mode: mode}
      end

    Espreso.BusinessSettings.get()
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
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

defmodule EspresoWeb.MenuLiveTest.FailingCheckoutClient do
  @moduledoc false
  @behaviour Espreso.PayMongo.Client

  @impl true
  def create_checkout_session(_order, _lines, _opts) do
    {:error, :checkout_unavailable}
  end
end

defmodule EspresoWeb.MenuLiveTest.FixedSessionClient do
  @moduledoc false
  @behaviour Espreso.PayMongo.Client

  @impl true
  def create_checkout_session(_order, _lines, opts) do
    {:ok,
     %{
       id: "cs_menu_attach_taken",
       checkout_url:
         Keyword.get(opts, :checkout_url, "https://checkout.paymongo.test/cs_menu_attach_taken")
     }}
  end
end

defmodule EspresoWeb.StaffPosLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Repo
  alias EspresoWeb.StaffPosLive

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.pos@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager.pos@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Staff",
        email: "staff.pos@test.local",
        password: "password123",
        role: "barista"
      })

    hot = insert_category!("HOT")
    cold = insert_category!("COLD")

    espresso = insert_product!(hot, "Espresso", true, [{nil, "75"}])
    americano = insert_product!(hot, "Americano", true, [{"8oz", "110"}, {"12oz", "120"}])
    _unavailable = insert_product!(hot, "Hidden Mocha", false, [{nil, "160"}])
    iced = insert_product!(cold, "Iced Latte", true, [{nil, "150"}])

    %{
      owner: owner,
      manager: manager,
      barista: barista,
      espresso: espresso,
      americano: americano,
      iced: iced
    }
  end

  test "authorized staff can open POS; guests cannot", %{conn: conn, barista: barista} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/pos")

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    assert has_element?(view, ".staff-shell-title", "POS")
    assert has_element?(view, "#pos-catalog")
    assert has_element?(view, "#pos-ticket")
    assert has_element?(view, "#staff-pos-rail")
    assert has_element?(view, "#staff-nav-pos.is-active")
    assert has_element?(view, "#staff-pos-rail-more > #staff-nav-more", "More")
    assert has_element?(view, "#staff-pos-rail-more .staff-pos-rail-more-panel")
    assert has_element?(view, "#staff-pos-rail-more #staff-nav-logout", "Log out")
    assert has_element?(view, "#staff-pos-rail-footer")
    refute has_element?(view, "#staff-nav-dashboard")
    refute render(view) =~ "Coming soon"
  end

  test "manager and owner can open POS", %{conn: conn, manager: manager, owner: owner} do
    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/pos")
    assert has_element?(manager_view, "#pos-place-order")
    assert has_element?(manager_view, "#staff-pos-rail-more #staff-nav-dashboard", "Dashboard")

    assert has_element?(
             manager_view,
             "#staff-pos-rail-more #staff-nav-availability",
             "Availability"
           )

    assert has_element?(manager_view, "#staff-pos-rail-more #staff-nav-reports", "Reports")
    refute has_element?(manager_view, "#staff-nav-staff")
    refute has_element?(manager_view, "#staff-nav-settings")

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/pos")
    assert has_element?(owner_view, "#pos-place-order")
    assert has_element?(owner_view, "#staff-pos-rail-more #staff-nav-staff", "Staff")
    assert has_element?(owner_view, "#staff-pos-rail-more #staff-nav-settings", "Settings")
  end

  test "POS shows available products and hides unavailable", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-product-#{espresso.id}", "Espresso")
    assert html =~ "Espresso"
    refute html =~ "Hidden Mocha"
    assert has_element?(view, "#pos-category-HOT", "Hot coffee")
    assert has_element?(view, "#pos-category-COLD", "Iced coffee")
    assert has_element?(view, "#pos-catalog-title", "Categories")
    refute has_element?(view, "#pos-category-ALL")
    refute render(view) =~ ">All</span>"
    refute has_element?(view, "#pos-notes-toggle")
    assert has_element?(view, "#pos-ticket.is-empty")
  end

  test "category selection switches product list", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    iced: iced
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-product-#{espresso.id}")
    refute has_element?(view, "#pos-product-#{iced.id}")

    view |> element("#pos-category-COLD") |> render_click()

    assert has_element?(view, "#pos-product-#{iced.id}", "Iced Latte")
    refute has_element?(view, "#pos-product-#{espresso.id}")
  end

  test "add, increase, decrease, and remove cart lines", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-product-#{espresso.id}", "Regular")
    assert has_element?(view, "#pos-product-#{espresso.id} .staff-pos-size-chips", "Regular")
    refute has_element?(view, "#pos-product-#{espresso.id} .staff-pos-product-sizes--empty")
    refute has_element?(view, "#pos-product-#{espresso.id} .staff-pos-product-desc")
    refute has_element?(view, "#pos-card-qty-#{espresso.id}")
    assert has_element?(view, "#pos-product-#{espresso.id}[aria-label='Add Espresso']")

    view |> element("#pos-product-#{espresso.id}") |> render_click()

    assert has_element?(view, "#pos-product-#{espresso.id}[aria-label='Added Espresso']")
    assert has_element?(view, "#pos-product-#{espresso.id}.is-added")
    assert has_element?(view, "#pos-cart-lines", "Espresso")
    assert has_element?(view, "#pos-total", "₱75")

    key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element(~s(button[phx-click="inc"][phx-value-key="#{key}"])) |> render_click()
    assert has_element?(view, "#pos-line-#{key}", "2")
    assert has_element?(view, "#pos-total", "₱150")

    view |> element(~s(button[phx-click="dec"][phx-value-key="#{key}"])) |> render_click()
    assert has_element?(view, "#pos-total", "₱75")

    view |> element(~s(button[phx-click="remove"][phx-value-key="#{key}"])) |> render_click()
    assert has_element?(view, "#pos-cart-empty")
  end

  test "quantity-one decrement removes a line and Undo restores it", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element(~s(button[phx-click="dec"][phx-value-key="#{key}"])) |> render_click()

    assert has_element?(view, "#pos-cart-empty")
    assert has_element?(view, "#pos-cart-undo", "Item removed")

    view |> element("#pos-cart-undo-action") |> render_click()

    assert has_element?(view, "#pos-line-#{key}", "1")
    refute has_element?(view, "#pos-cart-undo")
  end

  test "remove Undo restores exact variant, quantity, and price", %{
    conn: conn,
    barista: barista,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    key = "#{americano.id}-#{price_12.id}"

    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element(~s(button[phx-click="remove"][phx-value-key="#{key}"])) |> render_click()

    view |> element("#pos-cart-undo-action") |> render_click()

    assert has_element?(view, "#pos-line-#{key}", "12oz")
    assert has_element?(view, "#pos-line-#{key}", "2")
    assert has_element?(view, "#pos-line-#{key}", "₱240")
  end

  test "a second removal replaces the previous Undo snapshot", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"
    key_8 = "#{americano.id}-#{price_8.id}"
    key_12 = "#{americano.id}-#{price_12.id}"

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-size-#{price_8.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()

    remove_line(view, espresso_key)
    remove_line(view, key_8)
    view |> element("#pos-cart-undo-action") |> render_click()

    refute has_element?(view, "#pos-line-#{espresso_key}")
    assert has_element?(view, "#pos-line-#{key_8}")
    assert has_element?(view, "#pos-line-#{key_12}")
  end

  test "adding a product invalidates a pending removal Undo", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    remove_line(view, espresso_key)
    assert has_element?(view, "#pos-cart-undo")

    view |> element("#pos-product-#{americano.id}") |> render_click()

    refute has_element?(view, "#pos-cart-undo")
    refute has_element?(view, "#pos-line-#{espresso_key}")
  end

  test "removal Undo expires", %{conn: conn, barista: barista, espresso: espresso} do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    remove_line(view, key)
    assert has_element?(view, "#pos-cart-undo")

    Process.sleep(4_100)
    refute has_element?(view, "#pos-cart-undo")

    view |> render_click("undo_cart", %{})
    refute has_element?(view, "#pos-line-#{key}")
  end

  test "Clear Ticket resets and Undo restores the complete draft", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    americano_key = "#{americano.id}-#{price_12.id}"

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-fulfillment-dine-in") |> render_click()
    view |> element("#pos-pay-gcash") |> render_click()

    view
    |> element("#pos-customer-name")
    |> render_change(%{"customer_name" => "Maria"})

    view |> element("#pos-notes-toggle") |> render_click()

    view
    |> element("#pos-notes")
    |> render_change(%{"notes" => "Less ice"})

    view |> element("#pos-clear-ticket") |> render_click()

    assert has_element?(view, "#pos-cart-empty")
    assert has_element?(view, ~s(#pos-customer-name[value="Walk-in"]))
    assert has_element?(view, "#pos-fulfillment-pickup.is-active")
    assert has_element?(view, "#pos-pay-cash.is-active")
    assert has_element?(view, "#pos-cart-undo", "Ticket cleared")
    refute has_element?(view, "#pos-clear-ticket")
    refute has_element?(view, "#pos-notes-toggle")

    view |> element("#pos-cart-undo-action") |> render_click()

    assert has_element?(view, "#pos-line-#{espresso_key}", "2")
    assert has_element?(view, "#pos-line-#{americano_key}", "12oz")
    assert has_element?(view, ~s(#pos-customer-name[value="Maria"]))
    assert has_element?(view, "#pos-notes", "Less ice")
    assert has_element?(view, "#pos-fulfillment-dine-in.is-active")
    assert has_element?(view, "#pos-pay-gcash.is-active")
    assert has_element?(view, "#pos-size-#{price_12.id}.is-active")
    assert has_element?(view, "#pos-clear-ticket")
  end

  test "successful Process Order invalidates pending Undo", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    remove_line(view, espresso_key)
    assert has_element?(view, "#pos-cart-undo")

    submit_order(view)

    refute has_element?(view, "#pos-cart-undo")
    view |> render_click("undo_cart", %{})
    assert has_element?(view, "#pos-cart-empty")
  end

  test "multi-price product selects size on card then add to cart", %{
    conn: conn,
    barista: barista,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-product-#{americano.id}", "Americano")
    assert has_element?(view, "#pos-product-#{americano.id} .staff-pos-size-chips")
    refute has_element?(view, "#pos-size-picker")

    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    view |> element("#pos-size-#{price_8.id}") |> render_click()
    assert has_element?(view, "#pos-product-#{americano.id} .staff-pos-product-price", "₱110")

    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    view |> element("#pos-size-#{price_12.id}") |> render_click()

    assert has_element?(view, "#pos-product-#{americano.id} .staff-pos-product-price", "₱120")

    view |> element("#pos-product-#{americano.id}") |> render_click()

    assert has_element?(view, "#pos-cart-lines", "Americano")
    assert has_element?(view, "#pos-cart-lines", "12oz")
    assert has_element?(view, "#pos-total", "₱120")
  end

  test "cart variant correction replaces in place and preserves ticket state", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    key_8 = "#{americano.id}-#{price_8.id}"
    key_12 = "#{americano.id}-#{price_12.id}"
    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-fulfillment-dine-in") |> render_click()
    view |> element("#pos-pay-gcash") |> render_click()

    view
    |> element("#pos-customer-name")
    |> render_change(%{"customer_name" => "Maria"})

    view |> element("#pos-notes-toggle") |> render_click()
    view |> element("#pos-notes") |> render_change(%{"notes" => "Less ice"})

    open_variant_editor(view, key_12)

    assert has_element?(
             view,
             "#pos-cart-variant-#{key_12}-#{price_8.id}[aria-pressed='false']",
             "8oz · ₱110"
           )

    change_variant(view, key_12, price_8.id)

    refute has_element?(view, "#pos-line-#{key_12}")
    assert has_element?(view, "#pos-line-#{key_8} .staff-pos-qty", "2")
    assert has_element?(view, "#pos-line-#{key_8}", "8oz")
    assert has_element?(view, "#pos-line-#{key_8}", "₱220")
    assert has_element?(view, "#pos-line-#{espresso_key}")
    assert has_element?(view, "#pos-total", "₱295")
    assert has_element?(view, ~s(#pos-customer-name[value="Maria"]))
    assert has_element?(view, "#pos-notes", "Less ice")
    assert has_element?(view, "#pos-fulfillment-dine-in.is-active")
    assert has_element?(view, "#pos-pay-gcash.is-active")
    assert has_element?(view, "#pos-size-#{price_8.id}.is-active")
    assert has_element?(view, "#pos-cart-undo", "Size changed")
  end

  test "cart variant correction merges into destination at its existing position", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    key_8 = "#{americano.id}-#{price_8.id}"
    key_12 = "#{americano.id}-#{price_12.id}"
    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-size-#{price_8.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()

    open_variant_editor(view, key_12)
    change_variant(view, key_12, price_8.id)

    refute has_element?(view, "#pos-line-#{key_12}")
    assert has_element?(view, "#pos-line-#{key_8} .staff-pos-qty", "3")
    assert has_element?(view, "#pos-total", "₱405")
    assert has_element?(view, "#pos-cart-lines > li:first-child#pos-line-#{espresso_key}")
    assert has_element?(view, "#pos-cart-lines > li:last-child#pos-line-#{key_8}")
  end

  test "same cart variant closes chooser without replacing existing Undo", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    americano_key = "#{americano.id}-#{price_8.id}"
    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element("#pos-size-#{price_8.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    remove_line(view, espresso_key)

    open_variant_editor(view, americano_key)
    change_variant(view, americano_key, price_8.id)

    assert has_element?(view, "#pos-line-#{americano_key}")
    refute has_element?(view, "#pos-cart-variant-chooser-#{americano_key}")
    assert has_element?(view, "#pos-cart-undo", "Item removed")
  end

  test "single-price lines are static and invalid variant events safely no-op", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    key_8 = "#{americano.id}-#{price_8.id}"
    espresso_price = hd(espresso.product_prices)

    view |> element("#pos-size-#{price_8.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()

    assert has_element?(
             view,
             "#pos-line-#{espresso.id}-#{espresso_price.id} .staff-pos-cart-size"
           )

    refute has_element?(view, "#pos-cart-variant-trigger-#{espresso.id}-#{espresso_price.id}")

    original = render(view)

    for params <- [
          %{"key" => key_8},
          %{"key" => key_8, "price-id" => "not-an-id"},
          %{"key" => key_8, "price-id" => "999999999"},
          %{"key" => key_8, "price-id" => to_string(espresso_price.id)},
          %{"key" => "unknown-line", "price-id" => to_string(price_8.id)}
        ] do
      view |> render_click("change_cart_variant", params)
      assert render(view) == original
    end
  end

  test "same-size prices remain distinct by price id and ambiguous duplicates are suppressed", %{
    conn: conn,
    barista: barista
  } do
    hot = Repo.get_by!(Category, name: "HOT")

    duplicate_label =
      insert_product!(hot, "Duplicate Label", true, [{"Large", "100"}, {"Large", "130"}])

    ambiguous = insert_product!(hot, "Ambiguous", true, [{"Same", "90"}, {"Same", "90"}])
    [first, second] = duplicate_label.product_prices
    [ambiguous_first | _] = ambiguous.product_prices

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-size-#{first.id}") |> render_click()
    view |> element("#pos-product-#{duplicate_label.id}") |> render_click()
    source_key = "#{duplicate_label.id}-#{first.id}"
    target_key = "#{duplicate_label.id}-#{second.id}"
    open_variant_editor(view, source_key)

    assert has_element?(view, "#pos-cart-variant-#{source_key}-#{first.id}", "Large · ₱100")
    assert has_element?(view, "#pos-cart-variant-#{source_key}-#{second.id}", "Large · ₱130")

    change_variant(view, source_key, second.id)

    refute has_element?(view, "#pos-line-#{source_key}")
    assert has_element?(view, "#pos-line-#{target_key}", "₱130")

    view |> element("#pos-size-#{ambiguous_first.id}") |> render_click()
    view |> element("#pos-product-#{ambiguous.id}") |> render_click()

    refute has_element?(
             view,
             "#pos-cart-variant-trigger-#{ambiguous.id}-#{ambiguous_first.id}"
           )
  end

  test "variant Undo restores split lines and card selection", %{
    conn: conn,
    barista: barista,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    key_8 = "#{americano.id}-#{price_8.id}"
    key_12 = "#{americano.id}-#{price_12.id}"

    view |> element("#pos-size-#{price_8.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()

    open_variant_editor(view, key_12)
    change_variant(view, key_12, price_8.id)
    view |> element("#pos-cart-undo-action") |> render_click()

    assert has_element?(view, "#pos-line-#{key_8} .staff-pos-qty", "2")
    assert has_element?(view, "#pos-line-#{key_12} .staff-pos-qty", "1")
    assert has_element?(view, "#pos-size-#{price_12.id}.is-active")
    refute has_element?(view, "#pos-cart-undo")
  end

  test "removal and Clear Ticket restore a corrected variant exactly", %{
    conn: conn,
    barista: barista,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    key_8 = "#{americano.id}-#{price_8.id}"
    key_12 = "#{americano.id}-#{price_12.id}"

    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    open_variant_editor(view, key_12)
    change_variant(view, key_12, price_8.id)

    remove_line(view, key_8)
    view |> element("#pos-cart-undo-action") |> render_click()
    assert has_element?(view, "#pos-line-#{key_8} .staff-pos-qty", "2")
    assert has_element?(view, "#pos-line-#{key_8}", "₱220")

    view |> element("#pos-clear-ticket") |> render_click()
    view |> element("#pos-cart-undo-action") |> render_click()

    assert has_element?(view, "#pos-line-#{key_8} .staff-pos-qty", "2")
    assert has_element?(view, "#pos-size-#{price_8.id}.is-active")
    refute has_element?(view, "#pos-cart-variant-chooser-#{key_8}")
  end

  test "corrected variant is submitted and editor and Undo reset", %{
    conn: conn,
    barista: barista,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    key_8 = "#{americano.id}-#{price_8.id}"
    key_12 = "#{americano.id}-#{price_12.id}"

    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    open_variant_editor(view, key_12)
    change_variant(view, key_12, price_8.id)
    submit_order(view)

    [order] = Orders.list_active_orders()
    [item] = order.items
    assert item.size == "8oz"
    assert item.quantity == 2
    assert Decimal.equal?(item.unit_price, Decimal.new("110"))
    assert Decimal.equal?(order.total, Decimal.new("220"))
    assert has_element?(view, "#pos-cart-empty")
    refute has_element?(view, "#pos-cart-undo")
    refute has_element?(view, "#pos-cart-variant-chooser-#{key_8}")
  end

  test "malformed duplicate source or destination lines safely no-op", %{
    americano: americano
  } do
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    source = cart_line(americano, price_12, 1)
    destination = cart_line(americano, price_8, 2)
    categories = [%{name: "HOT", products: [americano]}]

    duplicate_source = [source, source, destination]

    source_socket =
      place_order_socket(%{
        categories: categories,
        cart: duplicate_source,
        card_sizes: %{americano.id => price_12.id}
      })

    assert {:noreply, unchanged_source} =
             StaffPosLive.handle_event(
               "change_cart_variant",
               %{"key" => source.key, "price-id" => to_string(price_8.id)},
               source_socket
             )

    assert unchanged_source.assigns.cart == duplicate_source

    duplicate_destination = [source, destination, destination]

    destination_socket =
      place_order_socket(%{
        categories: categories,
        cart: duplicate_destination,
        card_sizes: %{americano.id => price_12.id}
      })

    assert {:noreply, unchanged_destination} =
             StaffPosLive.handle_event(
               "change_cart_variant",
               %{"key" => source.key, "price-id" => to_string(price_8.id)},
               destination_socket
             )

    assert unchanged_destination.assigns.cart == duplicate_destination
  end

  test "empty cart cannot be submitted", %{conn: conn, barista: barista} do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-place-order[disabled]")
    refute has_element?(view, "#pos-clear-ticket")
    refute has_element?(view, "#pos-confirmation")

    view |> render_click("place_order", %{})

    assert has_element?(
             view,
             "#pos-ticket .staff-pos-ticket-footer #pos-submission-error[role='alert']",
             "Add at least one item"
           )
  end

  test "catalog selection errors remain global", %{conn: conn, barista: barista} do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> render_click("add_to_cart", %{"product-id" => "-1"})

    assert has_element?(view, "#pos-error", "Product is unavailable.")
    refute has_element?(view, "#pos-submission-error")
  end

  test "placing order creates POS order with items, total, source, and confirmation", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-product-#{espresso.id}") |> render_click()

    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()

    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view
    |> element(~s(button[phx-click="inc"][phx-value-key="#{espresso_key}"]))
    |> render_click()

    submit_order(view)

    assert has_element?(
             view,
             ~s(#pos-place-flash[role="status"][aria-live="polite"][aria-atomic="true"])
           )

    assert has_element?(view, "#pos-place-flash", "Paid at counter")
    assert has_element?(view, "#pos-place-flash", "Printing disabled")
    assert has_element?(view, ~s(#pos-place-flash a[href="/orders"]), "View Orders")
    assert has_element?(view, "#pos-cart-empty")
    assert has_element?(view, "#pos-place-order[disabled]")
    refute has_element?(view, "#pos-retry-print")
    refute has_element?(view, "#pos-confirmation")

    html = render(view)

    [order] = Orders.list_active_orders()
    assert order.number =~ Orders.order_number_pattern()
    assert html =~ order.number
    assert order.source == "pos"
    assert order.customer_name == "Walk-in"
    assert order.fulfillment == "pickup"
    assert order.payment_method == "counter"
    assert order.payment_status == "paid"
    assert order.paid_via == "cash"
    assert order.status == "preparing"
    assert Decimal.equal?(order.total, Decimal.new("270"))
    assert length(order.items) == 2

    names = Enum.map(order.items, & &1.name) |> Enum.sort()
    assert names == ["Americano", "Espresso"]

    view |> element("#pos-place-flash-dismiss") |> render_click()

    assert has_element?(view, "#pos-cart-empty")
    assert has_element?(view, "#pos-pay-cash.is-active", "Cash")
    refute has_element?(view, "#pos-place-flash")
  end

  test "success flash only clears for its active token", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    first_token = live_assigns(view).place_flash_token
    assert is_reference(first_token)

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    second_token = live_assigns(view).place_flash_token
    assert is_reference(second_token)
    refute second_token == first_token

    send(view.pid, {:clear_place_flash, first_token})
    assert has_element?(view, "#pos-place-flash")

    send(view.pid, {:clear_place_flash, second_token})
    refute has_element?(view, "#pos-place-flash")
    assert live_assigns(view).place_flash_token == nil
  end

  test "success dismissal invalidates its token and adding a product clears success", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    dismissed_token = live_assigns(view).place_flash_token
    view |> element("#pos-place-flash-dismiss") |> render_click()

    refute has_element?(view, "#pos-place-flash")
    assert live_assigns(view).place_flash_token == nil
    assert live_assigns(view).place_flash_timer == nil

    send(view.pid, {:clear_place_flash, dismissed_token})
    refute has_element?(view, "#pos-place-flash")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)
    assert has_element?(view, "#pos-place-flash")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    refute has_element?(view, "#pos-place-flash")
    assert live_assigns(view).place_flash_token == nil
  end

  test "success flash timer expires normally", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    assert has_element?(view, "#pos-place-flash")
    Process.sleep(4_100)
    refute has_element?(view, "#pos-place-flash")
  end

  test "Cash Process opens an accessible tender modal without creating an order", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    view |> element("#pos-size-#{price_8.id}") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()

    view |> form("#pos-order-form") |> render_submit()

    assert Orders.list_active_orders() == []
    assert has_element?(view, ~s(#cash-tender-modal [role="dialog"][aria-modal="true"]))
    assert has_element?(view, "#cash-tender-modal-title", "Cash Received")
    assert has_element?(view, "#pos-cash-total", "₱185")

    assert has_element?(
             view,
             ~s(#pos-cash-tendered[type="text"][inputmode="decimal"][autocomplete="off"])
           )

    assert has_element?(view, "#pos-cash-exact[data-dismiss-keyboard]", "Exact")
    refute has_element?(view, "#pos-cash-preset-100")

    assert has_element?(
             view,
             ~s(#pos-cash-preset-200[data-dismiss-keyboard][aria-label*="₱200"])
           )

    assert has_element?(view, "#pos-cash-preset-500[data-dismiss-keyboard]")
    assert has_element?(view, "#pos-cash-preset-1000[data-dismiss-keyboard]")

    assert has_element?(
             view,
             "#pos-confirm-cash[disabled][data-dismiss-keyboard]",
             "Confirm Payment"
           )
  end

  test "cancelling Cash Received preserves the ticket and clears tender state", %{
    conn: conn,
    barista: barista,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-fulfillment-dine-in") |> render_click()
    view |> element("#pos-notes-toggle") |> render_click()

    view
    |> form("#pos-order-form", %{"customer_name" => "Maria", "notes" => "Less ice"})
    |> render_submit()

    token = live_assigns(view).cash_tender_token

    view
    |> form("#pos-cash-tender-form", %{
      "cash_tender_token" => token,
      "cash_tendered" => "200"
    })
    |> render_change()

    view |> render_click("cancel_cash_tender", %{})

    refute has_element?(view, "#cash-tender-modal")
    assert Orders.list_active_orders() == []
    assert has_element?(view, "#pos-cart-lines", "Americano")
    assert has_element?(view, ~s(#pos-customer-name[value="Maria"]))
    assert has_element?(view, "#pos-notes", "Less ice")
    assert has_element?(view, "#pos-fulfillment-dine-in.is-active")
    assert has_element?(view, "#pos-pay-cash.is-active")
    assert live_assigns(view).cash_tendered == ""
    assert live_assigns(view).cash_tender_error == nil
    assert live_assigns(view).cash_tender_token == nil

    view |> form("#pos-order-form") |> render_submit()
    assert has_element?(view, ~s(#pos-cash-tendered[value=""]))
    refute live_assigns(view).cash_tender_token == token
  end

  test "Cash tender calculates exact, change, shortfall, and replacing presets", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    view |> element("#pos-size-#{price_8.id}") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> form("#pos-order-form") |> render_submit()

    token = live_assigns(view).cash_tender_token

    view
    |> form("#pos-cash-tender-form", %{
      "cash_tender_token" => token,
      "cash_tendered" => "100"
    })
    |> render_change()

    assert has_element?(view, "#pos-cash-tender-feedback.is-short", "Still needed")
    assert has_element?(view, "#pos-cash-tender-feedback", "₱85")
    assert has_element?(view, "#pos-confirm-cash[disabled]")

    view |> element("#pos-cash-preset-200") |> render_click()
    assert has_element?(view, ~s(#pos-cash-tendered[value="200.00"]))
    assert has_element?(view, "#pos-cash-tender-feedback", "Change")
    assert has_element?(view, "#pos-cash-tender-feedback", "₱15")
    refute has_element?(view, "#pos-confirm-cash[disabled]")
    assert Orders.list_active_orders() == []

    view |> element("#pos-cash-preset-500") |> render_click()
    assert has_element?(view, ~s(#pos-cash-tendered[value="500.00"]))
    assert has_element?(view, "#pos-cash-tender-feedback", "₱315")

    view |> element("#pos-cash-preset-1000") |> render_click()
    assert has_element?(view, ~s(#pos-cash-tendered[value="1000.00"]))
    assert has_element?(view, "#pos-cash-tender-feedback", "₱815")

    view |> element("#pos-cash-exact") |> render_click()
    assert has_element?(view, ~s(#pos-cash-tendered[value="185.00"]))
    assert has_element?(view, "#pos-cash-tender-feedback", "Exact cash")
    assert has_element?(view, "#pos-cash-tender-feedback", "₱0")
    assert Orders.list_active_orders() == []
  end

  test "invalid or insufficient Cash confirmation never creates an order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> form("#pos-order-form") |> render_submit()
    token = live_assigns(view).cash_tender_token

    for amount <- ["", "abc", "-1", "0", "75.001", "50"] do
      view
      |> form("#pos-cash-tender-form", %{
        "cash_tender_token" => token,
        "cash_tendered" => amount
      })
      |> render_submit()

      assert Orders.list_active_orders() == []
      assert has_element?(view, "#cash-tender-modal")
    end

    view
    |> form("#pos-cash-tender-form", %{
      "cash_tender_token" => token,
      "cash_tendered" => "1,000.00"
    })
    |> render_change()

    assert has_element?(view, "#pos-cash-tender-feedback", "₱925")
    refute has_element?(view, "#pos-confirm-cash[disabled]")
  end

  test "valid Cash confirmation creates one paid order with authoritative fields and change", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_8 = Enum.find(americano.product_prices, &(&1.size == "8oz"))
    view |> element("#pos-size-#{price_8.id}") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    view |> element("#pos-notes-toggle") |> render_click()

    view
    |> form("#pos-order-form", %{"customer_name" => "Pedro", "notes" => "No sugar"})
    |> render_submit()

    token = live_assigns(view).cash_tender_token

    view
    |> form("#pos-cash-tender-form", %{
      "cash_tender_token" => token,
      "cash_tendered" => "200"
    })
    |> render_submit()

    assert has_element?(view, "#pos-place-flash", "Cash received ₱200")
    assert has_element?(view, "#pos-place-flash", "Change ₱15")
    refute has_element?(view, "#cash-tender-modal")

    [order] = Orders.list_active_orders()
    assert order.customer_name == "Pedro"
    assert order.notes == "No sugar"
    assert order.payment_method == "counter"
    assert order.payment_status == "paid"
    assert order.paid_via == "cash"
    assert order.source == "pos"
    assert order.status == "preparing"
    assert Decimal.equal?(order.total, Decimal.new("185"))
    assert %DateTime{} = order.settled_at
    assert order.settled_by_user_id == barista.id
    assert order.settlement_source == "pos"
    assert order.settlement_time_estimated == false
    assert Decimal.equal?(order.cash_tendered, Decimal.new("200"))
    assert Decimal.equal?(order.change_due, Decimal.new("15"))

    assert live_assigns(view).cash_tendered == ""
    assert live_assigns(view).cash_tender_open? == false
    assert has_element?(view, "#pos-pay-cash.is-active")
  end

  test "stale and repeated Cash confirmations create exactly one order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> form("#pos-order-form") |> render_submit()
    token = live_assigns(view).cash_tender_token

    view
    |> render_click("confirm_cash_tender", %{
      "cash_tender_token" => "stale-token",
      "cash_tendered" => "100"
    })

    assert Orders.list_active_orders() == []
    assert has_element?(view, "#cash-tender-modal")

    params = %{"cash_tender_token" => token, "cash_tendered" => "100"}
    view |> render_click("confirm_cash_tender", params)
    view |> render_click("confirm_cash_tender", params)

    assert length(Orders.list_active_orders()) == 1
    refute has_element?(view, "#cash-tender-modal")
    refute has_element?(view, "#pos-submission-error")
  end

  test "unchanged authoritative price still creates one Cash order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()

    submit_order(view)

    assert [order] = Orders.list_active_orders()
    assert Decimal.equal?(order.total, Decimal.new("75"))
    assert [%{unit_price: unit_price}] = order.items
    assert Decimal.equal?(unit_price, Decimal.new("75"))
  end

  test "price changed after mount but before add rejects the stale Cash ticket", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    update_price!(hd(espresso.product_prices), "90")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    assert_stale_price_rejected(view, "Espresso", 1)
    assert has_element?(view, "#pos-total", "₱75")
    assert has_element?(view, "#pos-product-#{espresso.id}", "₱90")
  end

  test "price changed after add but before opening Cash tender rejects final confirmation", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    update_price!(hd(espresso.product_prices), "90")

    view |> form("#pos-order-form") |> render_submit()
    assert has_element?(view, "#pos-cash-total", "₱75")
    view |> element("#pos-cash-exact") |> render_click()
    view |> form("#pos-cash-tender-form") |> render_submit()

    assert_stale_price_rejected(view, "Espresso", 1)
  end

  test "price changed while Cash tender is open rejects final confirmation", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> form("#pos-order-form") |> render_submit()
    assert has_element?(view, "#pos-cash-total", "₱75")

    update_price!(hd(espresso.product_prices), "90")
    view |> element("#pos-cash-exact") |> render_click()
    view |> form("#pos-cash-tender-form") |> render_submit()

    assert_stale_price_rejected(view, "Espresso", 1)
  end

  test "price changed before GCash confirmation creates no paid order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-pay-gcash") |> render_click()
    update_price!(hd(espresso.product_prices), "90")

    view |> form("#pos-order-form") |> render_submit()

    assert_stale_price_rejected(view, "Espresso", 1)
    assert has_element?(view, "#pos-pay-gcash.is-active")
  end

  test "one stale line rejects an entire multi-product order atomically", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    americano_line = Enum.find(live_assigns(view).cart, &(&1.product_id == americano.id))
    update_price!(Repo.get!(ProductPrice, americano_line.price_id), "135")

    submit_order(view)

    assert_stale_price_rejected(view, "Espresso", 2)
    assert has_element?(view, "#pos-cart-lines", "Americano")
  end

  test "selected variant validates its exact product price row", %{
    conn: conn,
    barista: barista,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()
    update_price!(price_12, "135")

    submit_order(view)

    assert_stale_price_rejected(view, "Americano", 1)
    assert has_element?(view, "#pos-cart-lines", "12oz")
    assert has_element?(view, "#pos-total", "₱120")
  end

  test "Cash modal blocks ticket mutation and GCash bypasses tender", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> form("#pos-order-form") |> render_submit()

    view |> element("#pos-product-#{americano.id}") |> render_click()
    assert length(live_assigns(view).cart) == 1
    assert has_element?(view, "#pos-cart-lines", "Espresso")
    refute has_element?(view, "#pos-cart-lines", "Americano")

    view |> render_click("cancel_cash_tender", %{})
    view |> element("#pos-pay-gcash") |> render_click()

    assert has_element?(view, "#pos-gcash-confirmation-cue")
    assert has_element?(view, "#pos-place-order", "Confirm GCash & Process")
    submit_order(view)

    refute has_element?(view, "#cash-tender-modal")
    refute has_element?(view, "#pos-place-flash", "Cash received")

    [order] = Orders.list_active_orders()
    assert order.payment_method == "counter"
    assert order.payment_status == "paid"
    assert order.paid_via == "gcash"
    assert order.status == "preparing"
  end

  test "POS defaults to paid and can place paid counter order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-staff", "Staff")
    assert has_element?(view, ".staff-pos-section-label", "Payment method")
    assert has_element?(view, "#pos-pay-cash.is-active", "Cash")
    assert has_element?(view, "#pos-place-order", "Process Cash Order")
    refute has_element?(view, "#pos-gcash-confirmation-cue")
    refute has_element?(view, "#pos-pay-later")
    refute has_element?(view, "#pos-pay-maya")
    refute has_element?(view, "#pos-cash-helper")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    assert has_element?(view, "#pos-place-flash", "Paid at counter")
    assert has_element?(view, "#pos-cart-empty")

    [order] = Orders.list_active_orders()
    assert order.source == "pos"
    assert order.payment_method == "counter"
    assert order.payment_status == "paid"
    assert order.paid_via == "cash"
    assert order.status == "preparing"
    assert has_element?(view, "#pos-pay-cash.is-active", "Cash")
    assert has_element?(view, "#pos-place-order", "Process Cash Order")
  end

  test "POS GCash acknowledgement remains a single paid-order submission", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-fulfillment-dine-in") |> render_click()
    refute has_element?(view, "#pos-table-number")
    assert has_element?(view, "#pos-fulfillment-pickup", "Takeout")

    view
    |> element("#pos-customer-name")
    |> render_change(%{"customer_name" => "Maria"})

    view |> element("#pos-pay-gcash") |> render_click()

    assert has_element?(view, "#pos-pay-gcash.is-active", "GCash")

    assert has_element?(
             view,
             "#pos-gcash-confirmation-cue",
             "Confirm payment was received before processing."
           )

    assert has_element?(view, "#pos-place-order", "Confirm GCash & Process")
    assert Orders.list_active_orders() == []

    submit_order(view)

    assert has_element?(view, "#pos-place-flash")
    assert has_element?(view, ~s(#pos-customer-name[value="Walk-in"]))
    assert has_element?(view, "#pos-pay-cash.is-active", "Cash")
    assert has_element?(view, "#pos-place-order", "Process Cash Order")
    refute has_element?(view, "#pos-gcash-confirmation-cue")

    [order] = Orders.list_active_orders()
    assert order.customer_name == "Maria"
    assert order.fulfillment == "dine_in"
    assert order.table_number in [nil, ""]
    assert order.payment_method == "counter"
    assert order.payment_status == "paid"
    assert order.paid_via == "gcash"
    assert order.status == "preparing"
  end

  test "switching from GCash back to Cash removes acknowledgement cue", %{
    conn: conn,
    barista: barista
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-pay-gcash") |> render_click()
    assert has_element?(view, "#pos-gcash-confirmation-cue")
    assert has_element?(view, "#pos-place-order", "Confirm GCash & Process")

    view |> element("#pos-pay-cash") |> render_click()
    assert has_element?(view, "#pos-pay-cash.is-active", "Cash")
    assert has_element?(view, "#pos-place-order", "Process Cash Order")
    refute has_element?(view, "#pos-gcash-confirmation-cue")
    assert Orders.list_active_orders() == []
  end

  test "POS cash payment confirms tender before placing paid order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    assert has_element?(view, "#pos-pay-cash.is-active", "Cash")
    refute has_element?(view, "#pos-cash-tendered")

    submit_order(view)
    assert has_element?(view, "#pos-place-flash", "Paid at counter")

    [order] = Orders.list_active_orders()
    assert order.payment_status == "paid"
    assert order.paid_via == "cash"
    assert order.status == "preparing"
  end

  test "Place Order creates exactly one order; repeated place_order while placing is ignored", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()

    submit_order(view)
    # Cart cleared — second place with empty cart is a no-op create.
    view |> render_click("place_order", %{})

    assert length(Orders.list_active_orders()) == 1
    assert has_element?(view, "#pos-place-flash")
    assert has_element?(view, "#pos-cart-empty")
    refute has_element?(view, "#pos-submission-error")
  end

  test "repeated place_order is ignored while placing_order? is already true", %{
    espresso: espresso
  } do
    price = hd(espresso.product_prices)

    cart = [
      %{
        key: "#{espresso.id}-#{price.id}",
        name: espresso.name,
        size: price.size,
        quantity: 1,
        price: price.price
      }
    ]

    socket =
      place_order_socket(%{
        placing_order?: true,
        cart: cart,
        customer_name: "Walk-in",
        payment_choice: :unpaid
      })

    assert {:noreply, next} = StaffPosLive.handle_event("place_order", %{}, socket)
    assert next.assigns.placing_order? == true
    assert next.assigns.cart == cart
    assert Orders.list_active_orders() == []
  end

  test "placing_order? resets after successful creation", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    assert has_element?(view, "#pos-place-flash")
    assert has_element?(view, "#pos-cart-empty")

    view |> element("#pos-product-#{espresso.id}") |> render_click()

    refute has_element?(view, "#pos-place-order[disabled]")
    submit_order(view)

    assert length(Orders.list_active_orders()) == 2
    assert has_element?(view, "#pos-place-flash")
  end

  test "placing_order? resets after create_order error", %{espresso: espresso} do
    price = hd(espresso.product_prices)

    cart = [
      %{
        key: "#{espresso.id}-#{price.id}",
        product_id: espresso.id,
        name: espresso.name,
        size: price.size,
        quantity: 1,
        price: price.price
      }
    ]

    socket =
      place_order_socket(%{
        placing_order?: false,
        cart: cart,
        # Too short for Order.changeset customer_name validation
        customer_name: "A",
        payment_choice: :unpaid
      })

    assert {:noreply, next} = StaffPosLive.handle_event("place_order", %{}, socket)
    assert next.assigns.placing_order? == false
    assert next.assigns.submission_error == "Enter a customer name (at least 2 characters)."
    assert next.assigns.cart == cart
    assert Orders.list_active_orders() == []
  end

  test "POS saves custom customer name and notes on placed order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view
    |> element("#pos-customer-name")
    |> render_change(%{"customer_name" => "Maria"})

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    refute has_element?(view, "#pos-ticket.is-empty")
    assert has_element?(view, "#pos-notes-toggle")

    view |> element("#pos-notes-toggle") |> render_click()

    view
    |> element("#pos-notes")
    |> render_change(%{"notes" => "Less ice"})

    submit_order(view)

    assert has_element?(view, "#pos-place-flash", "Maria")
    assert has_element?(view, ~s(#pos-customer-name[value="Walk-in"]))

    [order] = Orders.list_active_orders()
    assert order.customer_name == "Maria"
    assert order.notes == "Less ice"
  end

  test "Process Order submits the latest customer name without waiting for debounce", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()

    submit_order(view, %{"customer_name" => "Maria"})

    [order] = Orders.list_active_orders()
    assert order.customer_name == "Maria"
    assert has_element?(view, ~s(#pos-customer-name[value="Walk-in"]))
  end

  test "Process Order submits the latest notes without waiting for debounce", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-notes-toggle") |> render_click()

    submit_order(view, %{"customer_name" => "Walk-in", "notes" => "No sugar"})

    [order] = Orders.list_active_orders()
    assert order.notes == "No sugar"
  end

  test "empty notes are not stored on the order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    [order] = Orders.list_active_orders()
    assert order.notes == nil
  end

  test "short customer name shows validation error before placing", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view
    |> element("#pos-customer-name")
    |> render_change(%{"customer_name" => "A"})

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    assert has_element?(
             view,
             "#pos-ticket .staff-pos-ticket-footer #pos-submission-error[role='alert']",
             "Enter a customer name"
           )

    refute has_element?(view, "#pos-confirmation")
    assert Orders.list_active_orders() == []

    view |> render_click("new_order", %{})
    refute has_element?(view, "#pos-submission-error")
  end

  test "unavailable product at place shows error, keeps cart, and resets placing_order?", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()

    espresso
    |> Product.changeset(%{available: false})
    |> Repo.update!()

    submit_order(view)

    assert has_element?(
             view,
             "#pos-ticket .staff-pos-ticket-footer #pos-submission-error[role='alert']",
             "Espresso is no longer available"
           )

    assert has_element?(view, "#pos-cart-lines", "Espresso")
    assert has_element?(view, "#pos-place-order")
    refute has_element?(view, "#cash-tender-modal")
    refute has_element?(view, "#pos-confirmation")
    assert Orders.list_active_orders() == []

    Repo.get!(Product, espresso.id)
    |> Product.changeset(%{available: true})
    |> Repo.update!()

    submit_order(view)

    assert has_element?(view, "#pos-place-flash")
    refute has_element?(view, "#pos-submission-error")
    assert length(Orders.list_active_orders()) == 1
  end

  test "product taps do not dismiss print-failure recovery", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    previous_printer_config = Application.get_env(:espreso, Espreso.Printer)

    Application.put_env(
      :espreso,
      Espreso.Printer,
      enabled: true,
      host: "127.0.0.1",
      port: 1,
      timeout_ms: 50
    )

    on_exit(fn ->
      if previous_printer_config do
        Application.put_env(:espreso, Espreso.Printer, previous_printer_config)
      else
        Application.delete_env(:espreso, Espreso.Printer)
      end
    end)

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    view |> element("#pos-size-#{price_12.id}") |> render_click()
    view |> element("#pos-fulfillment-dine-in") |> render_click()

    view
    |> element("#pos-customer-name")
    |> render_change(%{"customer_name" => "Maria"})

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-notes-toggle") |> render_click()

    view
    |> element("#pos-notes")
    |> render_change(%{"notes" => "Less ice"})

    submit_order(view)

    [saved_order] = Orders.list_active_orders()
    assert has_element?(view, "#pos-confirmation", saved_order.number)
    assert has_element?(view, "#pos-confirmation.is-error", "Print failed · order saved")
    assert has_element?(view, "#pos-print-note.is-error", "Order saved · print failed")
    assert has_element?(view, "#pos-retry-print", "Retry print")
    refute has_element?(view, "#cash-tender-modal")
    assert Decimal.equal?(live_assigns(view).last_cash_change.tendered, Decimal.new("75"))
    assert Decimal.equal?(live_assigns(view).last_cash_change.change, Decimal.new("0"))
    refute has_element?(view, "#pos-clear-ticket")
    refute has_element?(view, "#pos-cart-undo")

    view |> element("#pos-product-#{espresso.id}") |> render_click()

    view
    |> render_click("change_cart_variant", %{
      "key" => "stale-line",
      "price-id" => "123"
    })

    assert has_element?(view, "#pos-confirmation", saved_order.number)
    assert has_element?(view, "#pos-retry-print", "Retry print")
    assert has_element?(view, "#pos-new-order", "New Order")
    refute has_element?(view, "[id^='pos-cart-variant-trigger-']")
    assert length(Orders.list_active_orders()) == 1

    view |> element("#pos-retry-print") |> render_click()
    assert has_element?(view, "#pos-confirmation.is-error", "Print failed · order saved")
    assert has_element?(view, "#pos-print-note.is-error", "Print failed")
    assert has_element?(view, "#pos-retry-print", "Retry print")

    view |> element("#pos-new-order") |> render_click()

    refute has_element?(view, "#pos-confirmation")
    refute has_element?(view, "#pos-retry-print")
    refute has_element?(view, "#pos-print-note")
    refute has_element?(view, "#pos-place-flash")
    refute has_element?(view, "#pos-error")
    refute has_element?(view, "#pos-submission-error")
    refute has_element?(view, "#pos-cart-undo")
    assert has_element?(view, "#pos-cart-empty")
    assert has_element?(view, ~s(#pos-customer-name[value="Walk-in"]))
    assert has_element?(view, "#pos-fulfillment-pickup.is-active")
    assert has_element?(view, "#pos-pay-cash.is-active")
    assert has_element?(view, "#pos-place-order", "Process Cash Order")
    assert live_assigns(view).notes == ""
    assert live_assigns(view).card_sizes == %{}
    assert live_assigns(view).variant_editor_key == nil
    assert live_assigns(view).cash_tender_open? == false
    assert live_assigns(view).cash_tendered == ""
    assert live_assigns(view).cash_tender_error == nil
    assert live_assigns(view).cash_tender_token == nil
    assert live_assigns(view).last_cash_change == nil
    assert length(Orders.list_active_orders()) == 1
  end

  test "successful receipt retry shows recovered state and keeps recovery exits", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    restore_printer_config_on_exit()

    Application.put_env(
      :espreso,
      Espreso.Printer,
      enabled: true,
      host: "127.0.0.1",
      port: 1,
      timeout_ms: 50
    )

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    assert has_element?(view, "#pos-confirmation.is-error")
    assert has_element?(view, "#pos-retry-print")
    retry_token = live_assigns(view).print_retry_token
    assert is_binary(retry_token)
    assert has_element?(view, ~s(#pos-retry-print[phx-value-token="#{retry_token}"]))

    {port, printer_task} = start_test_printer!(2)

    Application.put_env(
      :espreso,
      Espreso.Printer,
      enabled: true,
      host: "127.0.0.1",
      port: port,
      timeout_ms: 1_000
    )

    view |> element("#pos-retry-print") |> render_click()
    assert [receipt_bytes, drawer_bytes] = Task.await(printer_task, 2_000)
    assert receipt_bytes != drawer_bytes
    assert drawer_bytes == <<0x1B, 0x70, 0x00, 0x19, 0xFA>>

    assert has_element?(view, "#pos-confirmation.is-success", "Print complete · order saved")
    assert has_element?(view, "#pos-print-note", "Receipt printed · kaha opened.")
    refute has_element?(view, "#pos-print-note.is-error")
    refute has_element?(view, "#pos-retry-print")
    assert live_assigns(view).print_retry_token == nil

    view |> render_click("reprint_receipt", %{"token" => retry_token})

    assert has_element?(view, "#pos-confirmation.is-success", "Print complete · order saved")
    assert live_assigns(view).print_retry_token == nil
    assert has_element?(view, "#pos-new-order", "New Order")
    assert has_element?(view, ~s(#pos-confirmation a[href="/orders"]), "View Orders")

    view |> element("#pos-new-order") |> render_click()
    refute has_element?(view, "#pos-confirmation")
    assert has_element?(view, "#pos-cart-empty")
    assert has_element?(view, "#pos-pay-cash.is-active")
    assert length(Orders.list_active_orders()) == 1
  end

  test "failed Retry rotates its token and only the fresh token can print", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    restore_printer_config_on_exit()
    set_test_printer_port(1)

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    first_token = live_assigns(view).print_retry_token
    view |> render_click("reprint_receipt", %{"token" => first_token})

    second_token = live_assigns(view).print_retry_token
    assert is_binary(second_token)
    refute second_token == first_token
    assert has_element?(view, "#pos-retry-print")

    {port, printer_task} = start_test_printer!(2)
    set_test_printer_port(port)

    view |> render_click("reprint_receipt", %{"token" => first_token})
    assert live_assigns(view).print_retry_token == second_token

    view |> render_click("reprint_receipt", %{"token" => second_token})
    assert [receipt_bytes, drawer_bytes] = Task.await(printer_task, 2_000)
    assert receipt_bytes != drawer_bytes
    assert drawer_bytes == <<0x1B, 0x70, 0x00, 0x19, 0xFA>>
    assert live_assigns(view).print_retry_token == nil
    assert has_element?(view, "#pos-confirmation.is-success")
  end

  test "New Order invalidates an old Retry token and a later failure gets a fresh token", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    restore_printer_config_on_exit()
    set_test_printer_port(1)

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    old_token = live_assigns(view).print_retry_token
    view |> element("#pos-new-order") |> render_click()
    assert live_assigns(view).print_retry_token == nil

    {port, printer_task} = start_test_printer!(2)
    set_test_printer_port(port)
    view |> render_click("reprint_receipt", %{"token" => old_token})

    set_test_printer_port(1)
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    new_token = live_assigns(view).print_retry_token
    assert is_binary(new_token)
    refute new_token == old_token

    set_test_printer_port(port)
    view |> render_click("reprint_receipt", %{"token" => new_token})

    assert [_receipt_bytes, <<0x1B, 0x70, 0x00, 0x19, 0xFA>>] =
             Task.await(printer_task, 2_000)

    assert has_element?(view, "#pos-confirmation.is-success")
  end

  test "GCash Retry token permits one receipt and rejects its duplicate", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    restore_printer_config_on_exit()
    set_test_printer_port(1)

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-pay-gcash") |> render_click()
    view |> form("#pos-order-form") |> render_submit()

    retry_token = live_assigns(view).print_retry_token
    assert is_binary(retry_token)
    assert has_element?(view, "#pos-retry-print")

    {port, printer_task} = start_test_printer!(1)
    set_test_printer_port(port)
    view |> render_click("reprint_receipt", %{"token" => retry_token})

    assert [receipt_bytes] = Task.await(printer_task, 2_000)
    refute receipt_bytes == <<0x1B, 0x70, 0x00, 0x19, 0xFA>>
    assert has_element?(view, "#pos-confirmation.is-success")
    assert live_assigns(view).print_retry_token == nil

    view |> render_click("reprint_receipt", %{"token" => retry_token})
    assert has_element?(view, "#pos-confirmation.is-success")
    assert live_assigns(view).print_retry_token == nil
  end

  test "Kitchen and Kaha actions use result-appropriate note styling", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    restore_printer_config_on_exit()

    Application.put_env(
      :espreso,
      Espreso.Printer,
      enabled: true,
      host: "127.0.0.1",
      port: 1,
      timeout_ms: 50
    )

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    submit_order(view)

    {kitchen_port, kitchen_task} = start_test_printer!(1)
    set_test_printer_port(kitchen_port)
    view |> element("#pos-print-kitchen") |> render_click()
    Task.await(kitchen_task, 2_000)

    assert has_element?(view, "#pos-print-note", "Kitchen ticket printed.")
    refute has_element?(view, "#pos-print-note.is-error")

    {drawer_port, drawer_task} = start_test_printer!(1)
    set_test_printer_port(drawer_port)
    view |> element("#pos-open-kaha") |> render_click()
    Task.await(drawer_task, 2_000)

    assert has_element?(view, "#pos-print-note", "Kaha opened.")
    refute has_element?(view, "#pos-print-note.is-error")

    set_test_printer_port(1)
    view |> element("#pos-print-kitchen") |> render_click()
    assert has_element?(view, "#pos-print-note.is-error", "Kitchen print failed")
    assert has_element?(view, "#pos-retry-print")
  end

  test "staff home hub links barista to Orders and POS", %{
    conn: conn,
    barista: barista
  } do
    {:ok, home, html} = live(log_in(conn, barista), ~p"/staff")
    assert html =~ "ELIlai Kafe"
    assert html =~ "Welcome back"
    assert has_element?(home, "#staff-home-orders", "Orders")
    assert has_element?(home, "#staff-home-pos", "POS")
    assert has_element?(home, "#staff-home-unpaid", "Unpaid")
    assert has_element?(home, "#staff-notif-toggle")
    assert has_element?(home, "#staff-home-today-barista")

    {:ok, view, html} = live(log_in(conn, barista), ~p"/orders")
    assert has_element?(view, "#staff-nav-pos", "POS")
    refute html =~ "Coming next"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp submit_order(view, params \\ %{}) do
    result =
      view
      |> form("#pos-order-form", params)
      |> render_submit()

    if has_element?(view, "#cash-tender-modal") do
      view |> element("#pos-cash-exact") |> render_click()
      view |> form("#pos-cash-tender-form") |> render_submit()
    else
      result
    end
  end

  defp remove_line(view, key) do
    view
    |> element(~s(button[phx-click="remove"][phx-value-key="#{key}"]))
    |> render_click()
  end

  defp open_variant_editor(view, key) do
    view
    |> element("#pos-cart-variant-trigger-#{key}")
    |> render_click()
  end

  defp change_variant(view, key, price_id) do
    view
    |> element("#pos-cart-variant-#{key}-#{price_id}")
    |> render_click()
  end

  defp live_assigns(view) do
    view.pid
    |> :sys.get_state()
    |> Map.fetch!(:socket)
    |> Map.fetch!(:assigns)
  end

  defp update_price!(product_price, amount) do
    product_price
    |> ProductPrice.changeset(%{price: Decimal.new(amount)})
    |> Repo.update!()
  end

  defp assert_stale_price_rejected(view, cart_text, expected_lines) do
    assert Orders.list_active_orders() == []
    assert Repo.aggregate(Espreso.Orders.Order, :count, :id) == 0
    assert Repo.aggregate(Espreso.Orders.OrderItem, :count, :id) == 0
    assert length(live_assigns(view).cart) == expected_lines
    assert has_element?(view, "#pos-cart-lines", cart_text)

    assert has_element?(
             view,
             "#pos-ticket .staff-pos-ticket-footer #pos-submission-error[role='alert']",
             "Price changed — please review your ticket."
           )

    refute has_element?(view, "#cash-tender-modal")
  end

  defp restore_printer_config_on_exit do
    previous = Application.get_env(:espreso, Espreso.Printer)

    on_exit(fn ->
      if previous do
        Application.put_env(:espreso, Espreso.Printer, previous)
      else
        Application.delete_env(:espreso, Espreso.Printer)
      end
    end)
  end

  defp set_test_printer_port(port) do
    Application.put_env(
      :espreso,
      Espreso.Printer,
      enabled: true,
      host: "127.0.0.1",
      port: port,
      timeout_ms: 1_000
    )
  end

  defp start_test_printer!(connection_count) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_address, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        bytes =
          Enum.map(1..connection_count, fn _ ->
            {:ok, socket} = :gen_tcp.accept(listener, 1_500)
            {:ok, bytes} = :gen_tcp.recv(socket, 0, 1_500)
            :gen_tcp.close(socket)
            bytes
          end)

        :gen_tcp.close(listener)
        bytes
      end)

    {port, task}
  end

  defp cart_line(product, price, quantity) do
    %{
      key: "#{product.id}-#{price.id}",
      product_id: product.id,
      price_id: price.id,
      name: product.name,
      size: price.size,
      price: price.price,
      quantity: quantity,
      image: "/images/test.png"
    }
  end

  defp place_order_socket(assigns) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(
      Map.merge(
        %{
          categories: [],
          selected_category: nil,
          size_picker: nil,
          last_order: nil,
          print_note: nil,
          error: nil,
          submission_error: nil,
          notes: "",
          fulfillment: :pickup,
          table_number: "",
          paid_via: "cash",
          cash_tendered: "",
          cash_tender_open?: false,
          cash_tender_error: nil,
          cash_tender_token: nil,
          last_cash_change: nil,
          print_failed?: false,
          print_retry_token: nil,
          print_note_error?: false,
          place_flash: nil,
          place_flash_token: nil,
          place_flash_timer: nil,
          notes_open?: false,
          payment_choice: :unpaid,
          placing_order?: false,
          cart_undo: nil,
          cart_undo_timer: nil,
          card_sizes: %{},
          variant_editor_key: nil,
          customer_name: "Walk-in",
          cart: [],
          current_user: %{name: "Staff"}
        },
        assigns
      )
    )
  end

  defp insert_category!(name) do
    %Category{} |> Category.changeset(%{name: name}) |> Repo.insert!()
  end

  defp insert_product!(category, name, available, prices) do
    product =
      %Product{}
      |> Product.changeset(%{name: name, category_id: category.id, available: available})
      |> Repo.insert!()

    prices =
      Enum.map(prices, fn {size, price} ->
        %ProductPrice{}
        |> ProductPrice.changeset(%{
          product_id: product.id,
          size: size,
          price: Decimal.new(price)
        })
        |> Repo.insert!()
      end)

    %{product | product_prices: prices}
  end

  test "POS search filters products and Cash order label is present", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-category-HOT.is-active", "Hot coffee")
    assert has_element?(view, "#pos-catalog-title", "Categories")
    assert has_element?(view, "#pos-place-order", "Process Cash Order")
    assert has_element?(view, "#pos-search-input")
    assert has_element?(view, "#pos-product-#{espresso.id}")
    assert has_element?(view, "#pos-product-#{americano.id}")

    view
    |> form("#pos-search", %{q: "Amer"})
    |> render_change()

    assert has_element?(view, "#pos-product-#{americano.id}")
    refute has_element?(view, "#pos-product-#{espresso.id}")

    view |> element("#pos-search-clear") |> render_click()
    assert has_element?(view, "#pos-product-#{espresso.id}")
  end
end

defmodule EspresoWeb.AdminAvailabilityLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Repo

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.adminavail@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager.adminavail@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Staff",
        email: "staff.adminavail@test.local",
        password: "password123",
        role: "barista"
      })

    hot = insert_category!("HOT")
    espresso = insert_product!(hot, "Espresso", true, [{nil, "75"}])
    secret = insert_product!(hot, "Secret Blend", false, [{nil, "999"}])

    %{owner: owner, manager: manager, barista: barista, espresso: espresso, secret: secret}
  end

  test "manager and owner can access availability board", %{
    conn: conn,
    manager: manager,
    owner: owner,
    secret: secret
  } do
    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/admin/availability")
    assert has_element?(manager_view, ".staff-shell-title", "Availability")
    assert has_element?(manager_view, "#availability-product-#{secret.id}", "Secret Blend")
    assert has_element?(manager_view, "#availability-product-#{secret.id}", "Unavailable")

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/admin/availability")
    assert has_element?(owner_view, "#availability-product-#{secret.id}")
  end

  test "barista is redirected", %{conn: conn, barista: barista} do
    assert {:error, {:redirect, %{to: "/staff"}}} =
             live(log_in(conn, barista), ~p"/admin/availability")
  end

  test "toggle changes product availability state", %{
    conn: conn,
    manager: manager,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, manager), ~p"/admin/availability")

    assert has_element?(view, "#availability-product-#{espresso.id}", "Available")

    view |> element("#availability-toggle-#{espresso.id}") |> render_click()

    assert has_element?(view, "#availability-product-#{espresso.id}", "Unavailable")
    assert has_element?(view, "#availability-flash")
    refute Repo.get!(Product, espresso.id).available

    view |> element("#availability-toggle-#{espresso.id}") |> render_click()

    assert has_element?(view, "#availability-product-#{espresso.id}", "Available")
    assert Repo.get!(Product, espresso.id).available

    hot_menu = Menu.list_menu() |> Enum.find(&(&1.name == "HOT"))
    assert Enum.any?(hot_menu.products, &(&1.id == espresso.id))
  end

  test "manager can add a HOT item from the availability board", %{
    conn: conn,
    manager: manager
  } do
    {:ok, view, _html} = live(log_in(conn, manager), ~p"/admin/availability")

    assert has_element?(view, "#availability-add-item", "Add item")
    view |> element("#availability-add-item") |> render_click()
    assert has_element?(view, "#availability-add-form")

    view
    |> form("#availability-add-form",
      item: %{
        category: "HOT",
        name: "Barako",
        hot_price_mode: "sizes",
        price_8oz: "155",
        price_12oz: "165"
      }
    )
    |> render_submit()

    assert has_element?(view, "#availability-flash", "Barako added to the menu.")
    refute has_element?(view, "#availability-add-form")
    assert has_element?(view, ".staff-availability-name", "Barako")

    hot_menu = Menu.list_menu() |> Enum.find(&(&1.name == "HOT"))
    assert Enum.any?(hot_menu.products, &(&1.name == "Barako"))
  end

  test "owner can add a FOOD item to a group", %{conn: conn, owner: owner} do
    insert_category!("FOOD")

    {:ok, view, _html} = live(log_in(conn, owner), ~p"/admin/availability")
    view |> element("#availability-add-item") |> render_click()

    view
    |> form("#availability-add-form", item: %{category: "FOOD"})
    |> render_change()

    view
    |> form("#availability-add-form",
      item: %{
        category: "FOOD",
        name: "Chicken Teriyaki",
        menu_group: "Rice Meal",
        price: "189"
      }
    )
    |> render_submit()

    assert has_element?(view, "#availability-flash", "Chicken Teriyaki added to the menu.")

    food_menu = Menu.list_menu() |> Enum.find(&(&1.name == "FOOD"))
    rice = Enum.find(food_menu.groups, &(&1.name == "Rice Meal"))
    assert Enum.any?(rice.products, &(&1.name == "Chicken Teriyaki"))
  end

  test "manager can change a product photo from the availability board", %{
    conn: conn,
    manager: manager,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, manager), ~p"/admin/availability")
    view |> element("#availability-photo-#{espresso.id}") |> render_click()
    assert has_element?(view, "#availability-photo-form")

    upload =
      file_input(view, "#availability-photo-form", :photo, [
        %{name: "cup.png", content: tiny_png(), type: "image/png"}
      ])

    render_upload(upload, "cup.png")
    view |> form("#availability-photo-form") |> render_submit()

    assert has_element?(view, "#availability-flash", "Photo saved")
    assert Repo.get!(Product, espresso.id).has_custom_photo
    assert Menu.get_product_photo(espresso.id).content_type == "image/png"
  end

  test "add item can include a photo", %{conn: conn, manager: manager} do
    {:ok, view, _html} = live(log_in(conn, manager), ~p"/admin/availability")
    view |> element("#availability-add-item") |> render_click()

    upload =
      file_input(view, "#availability-add-form", :photo, [
        %{name: "barako.png", content: tiny_png(), type: "image/png"}
      ])

    render_upload(upload, "barako.png")

    view
    |> form("#availability-add-form",
      item: %{
        category: "HOT",
        name: "Barako Photo",
        hot_price_mode: "sizes",
        price_8oz: "90",
        price_12oz: "100"
      }
    )
    |> render_submit()

    assert has_element?(view, "#availability-flash", "Barako Photo added to the menu.")
    product = Repo.get_by!(Product, name: "Barako Photo")
    assert product.has_custom_photo
    assert Menu.product_image("HOT", product) =~ "/media/products/#{product.id}"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
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
      |> ProductPrice.changeset(%{
        product_id: product.id,
        size: size,
        price: Decimal.new(price)
      })
      |> Repo.insert!()
    end)

    product
  end

  defp tiny_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
  end
end

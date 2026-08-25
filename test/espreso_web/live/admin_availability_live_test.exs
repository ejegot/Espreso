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
    assert {:error, {:redirect, %{to: "/orders"}}} =
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
end

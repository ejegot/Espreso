defmodule EspresoWeb.ProductPhotoControllerTest do
  use EspresoWeb.ConnCase

  alias Espreso.Accounts
  alias Espreso.Menu
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Repo

  test "serves an attached product photo", %{conn: conn} do
    hot = insert_category!("HOT")
    product = insert_product!(hot, "Barako", true, [{nil, "90"}])
    {:ok, manager} = register_manager()
    png = tiny_png()

    assert {:ok, _} = Menu.put_product_photo_as(manager, product.id, png, "image/png")

    conn = get(conn, ~p"/media/products/#{product.id}")
    assert response(conn, 200) == png
    assert get_resp_header(conn, "content-type") |> List.first() =~ "image/png"
  end

  test "returns 404 when the product has no custom photo", %{conn: conn} do
    hot = insert_category!("HOT")
    product = insert_product!(hot, "Espresso", true, [{nil, "75"}])

    conn = get(conn, ~p"/media/products/#{product.id}")
    assert response(conn, 404)
  end

  defp register_manager do
    Accounts.register_user(%{
      name: "Manager",
      email: "manager.photoctl@test.local",
      password: "password123",
      role: "manager"
    })
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

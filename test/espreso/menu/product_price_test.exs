defmodule Espreso.Menu.ProductPriceTest do
  use Espreso.DataCase, async: true

  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Repo

  describe "changeset/2" do
    setup do
      {:ok, category} =
        %Category{}
        |> Category.changeset(%{name: "HOT"})
        |> Repo.insert()

      {:ok, product} =
        %Product{}
        |> Product.changeset(%{name: "Americano", category_id: category.id})
        |> Repo.insert()

      %{product: product}
    end

    test "is valid with required fields", %{product: product} do
      changeset =
        ProductPrice.changeset(%ProductPrice{}, %{
          product_id: product.id,
          price: "110",
          size: "8oz"
        })

      assert changeset.valid?
    end

    test "requires a product_id" do
      changeset = ProductPrice.changeset(%ProductPrice{}, %{price: "75"})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).product_id
    end

    test "requires a price", %{product: product} do
      changeset =
        ProductPrice.changeset(%ProductPrice{}, %{
          product_id: product.id,
          size: "8oz"
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).price
    end

    test "allows size to be optional", %{product: product} do
      changeset =
        ProductPrice.changeset(%ProductPrice{}, %{
          product_id: product.id,
          price: "75"
        })

      assert changeset.valid?
      assert get_change(changeset, :size) == nil
    end

    test "does not allow a negative price", %{product: product} do
      changeset =
        ProductPrice.changeset(%ProductPrice{}, %{
          product_id: product.id,
          price: "-1"
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).price
    end

    test "belongs to a product", %{product: product} do
      assert {:ok, product_price} =
               %ProductPrice{}
               |> ProductPrice.changeset(%{
                 product_id: product.id,
                 price: "110",
                 size: "8oz"
               })
               |> Repo.insert()

      product_price = Repo.preload(product_price, :product)

      assert product_price.product.id == product.id
      assert product_price.product.name == "Americano"
    end
  end
end

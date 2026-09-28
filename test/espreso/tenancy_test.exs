defmodule Espreso.TenancyTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.BusinessSettings
  alias Espreso.Menu
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo
  alias Espreso.Tenancy

  test "CoffeeSpot Lilac is the default tenant and branch" do
    %{tenant: tenant, branch: branch} = Tenancy.ensure_coffeespot_lilac!()

    assert tenant.slug == "coffeespot"
    assert tenant.guest_brand_name == "CoffeeSpot"
    assert branch.slug == "lilac"
    assert branch.main
    assert branch.tenant_id == tenant.id
    assert Tenancy.default_tenant_id() == tenant.id
    assert Tenancy.default_branch_id() == branch.id
  end

  test "new staff and settings attach to Lilac" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Lilac Owner",
        email: "lilac-owner-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "owner"
      })

    setting = BusinessSettings.get()

    assert user.tenant_id == Tenancy.default_tenant_id()
    assert user.branch_id == Tenancy.default_branch_id()
    assert setting.branch_id == Tenancy.default_branch_id()
    assert setting.business_name == "CoffeeSpot"
  end

  test "list queries stay on Lilac when another tenant has data" do
    %{tenant: other_tenant, branch: other_branch} = insert_other_shop!()

    {:ok, _lilac_order} =
      Orders.create_order(
        [order_line()],
        %{customer_name: "Lilac Guest", fulfillment: "pickup", payment_method: "counter"}
      )

    other_order =
      %Order{}
      |> Order.changeset(%{
        number: "ZZOTHER",
        customer_name: "Other Café",
        fulfillment: "pickup",
        status: "received",
        payment_method: "counter",
        payment_status: "unpaid",
        source: "pos",
        total: Decimal.new("99"),
        tenant_id: other_tenant.id,
        branch_id: other_branch.id
      })
      |> Repo.insert!()

    numbers = Enum.map(Orders.list_active_orders(), & &1.number)

    assert other_order.number not in numbers
    assert Enum.any?(numbers, &(&1 != other_order.number))
  end

  test "menu categories from another branch are hidden" do
    %{tenant: tenant, branch: branch} = insert_other_shop!()

    %Category{}
    |> Category.changeset(%{
      name: "OTHERHOT",
      tenant_id: tenant.id,
      branch_id: branch.id
    })
    |> Repo.insert!()

    refute Enum.any?(Menu.list_products_for_availability(), &(&1.name == "OTHERHOT"))
  end

  defp insert_other_shop! do
    tenant =
      Tenancy.insert_tenant!(%{
        name: "Other Café",
        slug: "other-cafe-#{System.unique_integer([:positive])}",
        guest_brand_name: "Other Café"
      })

    branch =
      Tenancy.insert_branch!(tenant, %{
        name: "Main",
        slug: "main",
        code: "oth#{System.unique_integer([:positive])}",
        main: true
      })

    %{tenant: tenant, branch: branch}
  end

  defp order_line do
    category =
      case Repo.get_by(Category, name: "HOT", branch_id: Tenancy.default_branch_id()) do
        %Category{} = existing ->
          existing

        nil ->
          %Category{}
          |> Category.changeset(%{name: "HOT"})
          |> Repo.insert!()
      end

    product =
      %Product{}
      |> Product.changeset(%{
        name: "Tenancy Espresso #{System.unique_integer([:positive])}",
        category_id: category.id,
        available: true
      })
      |> Repo.insert!()

    price =
      %ProductPrice{}
      |> ProductPrice.changeset(%{
        product_id: product.id,
        size: "8oz",
        price: Decimal.new("120")
      })
      |> Repo.insert!()

    %{
      name: product.name,
      size: "8oz",
      quantity: 1,
      price: price.price,
      product_id: product.id,
      price_id: price.id
    }
  end
end

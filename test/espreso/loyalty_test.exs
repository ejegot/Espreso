defmodule Espreso.LoyaltyTest do
  use Espreso.DataCase, async: true

  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Customers
  alias Espreso.Loyalty
  alias Espreso.Loyalty.LedgerEntry
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Repo

  setup do
    {:ok, customer} = Customers.find_or_create_by_phone("09172220001", %{name: "Loyal"})

    hot = insert_category!("HOT")
    cold = insert_category!("COLD")
    frappe = insert_category!("FRAPPE")

    americano = insert_product!(hot, "Americano", [{"8oz", "110"}, {"12oz", "120"}])
    iced = insert_product!(cold, "Iced Latte", [{"16oz", "180"}])
    frappe_drink = insert_product!(frappe, "Mocha Frappe", [{"16oz", "180"}])

    {:ok, staff} =
      Accounts.register_user(%{
        name: "Loyalty Staff",
        email: "loyalty.staff-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    %{
      customer: customer,
      staff: staff,
      americano: americano,
      iced: iced,
      frappe_drink: frappe_drink
    }
  end

  describe "earning" do
    test "₱150 then ₱100 accumulates remainder and awards 1 point", %{customer: customer} do
      {:ok, first} = create_paid_customer_order(customer, "150")
      assert {:ok, {:already_earned, _}} = Loyalty.earn_for_paid_order(first)

      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 0
      assert customer.spend_remainder_centavos == 15_000

      {:ok, _second} = create_paid_customer_order(customer, "100")
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 1
      assert customer.spend_remainder_centavos == 5_000
    end

    test "₱200 awards 1 point with zero remainder", %{customer: customer} do
      {:ok, _} = create_paid_customer_order(customer, "200")
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 1
      assert customer.spend_remainder_centavos == 0
    end

    test "₱400 awards 2 points", %{customer: customer} do
      {:ok, _} = create_paid_customer_order(customer, "400")
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 2
      assert customer.spend_remainder_centavos == 0
    end

    test "food and frappe purchases qualify for earning", %{customer: customer} do
      food_cat = insert_category!("FOOD")
      food = insert_product!(food_cat, "Muffin", [{nil, "200"}])

      {:ok, _} =
        Orders.create_order(
          [
            %{
              name: food.name,
              size: nil,
              quantity: 1,
              price: Decimal.new("200")
            }
          ],
          %{
            customer_name: "Loyal",
            fulfillment: :pickup,
            payment_method: :counter,
            payment_status: :paid,
            paid_via: "cash",
            source: :pos,
            customer_id: customer.id,
            skip_authoritative_prices: true
          }
        )

      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 1
    end

    test "loyalty-free amount excluded; upgrade amount included", %{
      customer: customer,
      americano: americano
    } do
      # Simulate redemption order: pay ₱10 upgrade, free base ₱110
      {:ok, order} =
        Orders.create_order(
          [
            %{
              name: americano.name,
              size: "12oz",
              quantity: 1,
              price: Decimal.new("10")
            }
          ],
          %{
            customer_name: "Loyal",
            fulfillment: :pickup,
            payment_method: :counter,
            payment_status: :paid,
            paid_via: "cash",
            source: :pos,
            customer_id: customer.id,
            loyalty_free_amount_centavos: 11_000,
            skip_authoritative_prices: true
          }
        )

      assert order.loyalty_free_amount_centavos == 11_000
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 0
      assert customer.spend_remainder_centavos == 1_000
    end

    test "unpaid and cancelled unpaid earn nothing; complete alone does not earn", %{
      customer: customer
    } do
      {:ok, unpaid} =
        Orders.create_order(
          [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("200")}],
          %{
            customer_name: "Loyal",
            fulfillment: :pickup,
            payment_method: :counter,
            source: :customer,
            customer_id: customer.id
          }
        )

      assert unpaid.payment_status == "unpaid"
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 0
      assert customer.spend_remainder_centavos == 0

      assert {:ok, cancelled} = Orders.cancel_order(unpaid)
      assert cancelled.status == "cancelled"
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 0

      {:ok, to_complete} = create_paid_customer_order(customer, "50")
      before = Repo.get!(Espreso.Customers.Customer, customer.id)

      assert {:ok, preparing} = Orders.update_status(to_complete, "preparing")
      assert {:ok, ready} = Orders.update_status(preparing, "ready")
      assert {:ok, _} = Orders.complete_order(ready)

      after_complete = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert after_complete.points_balance == before.points_balance
      assert after_complete.spend_remainder_centavos == before.spend_remainder_centavos
    end

    test "apply_paid transition earns once; already_paid does not", %{customer: customer} do
      {:ok, unpaid} =
        Orders.create_order(
          [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("200")}],
          %{
            customer_name: "Loyal",
            fulfillment: :pickup,
            payment_method: :counter,
            source: :customer,
            customer_id: customer.id
          }
        )

      assert {:ok, :transitioned, paid} =
               Orders.mark_paid_with_transition(unpaid, paid_via: "cash")

      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 1

      assert {:ok, :already_paid, _} =
               Orders.mark_paid_with_transition(paid, paid_via: "cash")

      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 1

      earns =
        LedgerEntry
        |> where([e], e.order_id == ^paid.id and e.kind == "earn")
        |> Repo.all()

      assert length(earns) == 1
    end

    test "PayMongo-style mark_paid_from_paymongo is idempotent for loyalty", %{customer: customer} do
      {:ok, unpaid} =
        Orders.create_order(
          [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("200")}],
          %{
            customer_name: "Loyal",
            fulfillment: :pickup,
            payment_method: :online,
            payment_intent: :gcash,
            source: :customer,
            customer_id: customer.id
          }
        )

      assert {:ok, _} = Orders.mark_paid_from_paymongo(unpaid.number)
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 1

      assert {:ok, _} = Orders.mark_paid_from_paymongo(unpaid.number)
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 1
    end

    test "anonymous orders stay customer_id nil and never earn" do
      {:ok, order} =
        Orders.create_order(
          [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("200")}],
          %{
            customer_name: "Walk-in",
            fulfillment: :pickup,
            payment_method: :counter,
            payment_status: :paid,
            paid_via: "cash",
            source: :pos,
            skip_authoritative_prices: true
          }
        )

      assert is_nil(order.customer_id)
      assert {:ok, :no_customer} = Loyalty.earn_for_paid_order(order)
      assert Repo.aggregate(LedgerEntry, :count, :id) == 0
    end
  end

  describe "redemption" do
    test "requires 10 points; deducts exactly 10; leaves remainder", %{
      customer: customer,
      americano: americano,
      staff: staff
    } do
      assert {:error, :insufficient_points} =
               Loyalty.redeem_at_pos(customer.id, price_id(americano, "8oz"), redeem_attrs(staff))

      set_points!(customer, 10)

      assert {:ok, %{order: order, customer: updated}} =
               Loyalty.redeem_at_pos(customer.id, price_id(americano, "8oz"), redeem_attrs(staff))

      assert updated.points_balance == 0
      assert order.loyalty_free_amount_centavos == 11_000
      assert Decimal.equal?(order.total, Decimal.new("0"))
      assert order.customer_id == customer.id
      assert order.source == "pos"

      set_points!(updated, 20)

      assert {:ok, %{customer: after_one}} =
               Loyalty.redeem_at_pos(customer.id, price_id(americano, "8oz"), redeem_attrs(staff))

      assert after_one.points_balance == 10
    end

    test "HOT and COLD allowed; FRAPPE rejected", %{
      customer: customer,
      americano: americano,
      iced: iced,
      frappe_drink: frappe_drink,
      staff: staff
    } do
      set_points!(customer, 30)

      assert {:ok, _} =
               Loyalty.redeem_at_pos(customer.id, price_id(americano, "8oz"), redeem_attrs(staff))

      assert {:ok, _} =
               Loyalty.redeem_at_pos(customer.id, price_id(iced, "16oz"), redeem_attrs(staff))

      assert {:error, :ineligible_product} =
               Loyalty.redeem_at_pos(
                 customer.id,
                 price_id(frappe_drink, "16oz"),
                 redeem_attrs(staff)
               )
    end

    test "upgrade charge qualifies toward future earning", %{
      customer: customer,
      americano: americano,
      staff: staff
    } do
      set_points!(customer, 10)

      assert {:ok, %{order: order, quote: quote}} =
               Loyalty.redeem_at_pos(
                 customer.id,
                 price_id(americano, "12oz"),
                 redeem_attrs(staff)
               )

      assert Decimal.equal?(quote.base_price, Decimal.new("110"))
      assert Decimal.equal?(quote.upgrade_amount, Decimal.new("10"))
      assert Decimal.equal?(order.total, Decimal.new("10"))
      assert order.loyalty_free_amount_centavos == 11_000

      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      # 10 points spent; upgrade ₱10 qualifies → remainder 1000
      assert customer.points_balance == 0
      assert customer.spend_remainder_centavos == 1_000
    end

    test "failed redemption does not consume points", %{
      customer: customer,
      staff: staff
    } do
      set_points!(customer, 10)

      assert {:error, :ineligible_product} =
               Loyalty.redeem_at_pos(customer.id, -1, redeem_attrs(staff))

      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 10
    end
  end

  describe "quote_reward/1" do
    test "computes base and upgrade from catalog sizes", %{americano: americano} do
      assert {:ok, quote} = Loyalty.quote_reward(price_id(americano, "12oz"))
      assert Decimal.equal?(quote.base_price, Decimal.new("110"))
      assert Decimal.equal?(quote.upgrade_amount, Decimal.new("10"))
      assert quote.loyalty_free_amount_centavos == 11_000
    end
  end

  defp create_paid_customer_order(customer, amount) do
    Orders.create_order(
      [%{name: "Item", size: nil, quantity: 1, price: Decimal.new(amount)}],
      %{
        customer_name: customer.name || "Loyal",
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :paid,
        paid_via: "cash",
        source: :pos,
        customer_id: customer.id,
        skip_authoritative_prices: true
      }
    )
  end

  defp redeem_attrs(staff) do
    %{
      customer_name: "Loyal",
      fulfillment: :pickup,
      payment_method: :counter,
      payment_status: :paid,
      paid_via: "cash",
      source: :pos,
      settled_by_user_id: staff.id,
      settlement_source: :pos
    }
  end

  defp set_points!(customer, points) do
    customer
    |> Ecto.Changeset.change(%{points_balance: points})
    |> Repo.update!()
  end

  defp price_id(product, size) do
    product = Repo.preload(product, :product_prices)

    product.product_prices
    |> Enum.find(&(to_string(&1.size) == to_string(size)))
    |> Map.fetch!(:id)
  end

  defp insert_category!(name) do
    case Repo.get_by(Category, name: name) do
      %Category{} = category ->
        category

      nil ->
        %Category{}
        |> Category.changeset(%{name: name})
        |> Repo.insert!()
    end
  end

  defp insert_product!(category, name, prices) do
    product =
      %Product{}
      |> Product.changeset(%{
        name: "#{name}-#{System.unique_integer([:positive])}",
        category_id: category.id,
        available: true
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

    Repo.preload(product, :product_prices)
  end
end

defmodule Espreso.LoyaltyEarnHardeningTest do
  use Espreso.DataCase, async: false

  import Ecto.Query

  alias Espreso.Customers
  alias Espreso.Loyalty
  alias Espreso.Loyalty.EarnReconciler
  alias Espreso.Loyalty.LedgerEntry
  alias Espreso.Orders
  alias Espreso.Repo

  setup do
    Application.delete_env(:espreso, :loyalty_earn_barrier)

    on_exit(fn ->
      Application.delete_env(:espreso, :loyalty_earn_barrier)
    end)

    unique =
      System.unique_integer([:positive])
      |> rem(10_000_000)
      |> Integer.to_string()
      |> String.pad_leading(7, "0")

    {:ok, customer} =
      Customers.find_or_create_by_phone("0917#{unique}", %{name: "Hardening"})

    %{customer: customer}
  end

  test "paid transition earns once", %{customer: customer} do
    {:ok, unpaid} = create_unpaid(customer, "200")

    assert {:ok, :transitioned, paid} =
             Orders.mark_paid_with_transition(unpaid, paid_via: "cash")

    assert paid.payment_status == "paid"
    customer = Repo.get!(Espreso.Customers.Customer, customer.id)
    assert customer.points_balance == 1
    assert earn_count(paid.id) == 1
  end

  test "loyalty failure after pay leaves order paid and earn pending", %{customer: customer} do
    {:ok, unpaid} = create_unpaid(customer, "200")

    Application.put_env(:espreso, :loyalty_earn_barrier, fn -> {:error, :forced_failure} end)

    assert {:ok, :transitioned, paid} =
             Orders.mark_paid_with_transition(unpaid, paid_via: "cash")

    assert paid.payment_status == "paid"
    assert paid.settled_at
    assert Loyalty.earn_pending?(paid)
    assert earn_count(paid.id) == 0

    customer = Repo.get!(Espreso.Customers.Customer, customer.id)
    assert customer.points_balance == 0
    assert customer.spend_remainder_centavos == 0
  end

  test "retry after loyalty failure awards exactly once", %{customer: customer} do
    {:ok, unpaid} = create_unpaid(customer, "200")

    Application.put_env(:espreso, :loyalty_earn_barrier, fn -> {:error, :forced_failure} end)

    assert {:ok, :transitioned, paid} =
             Orders.mark_paid_with_transition(unpaid, paid_via: "cash")

    assert Loyalty.earn_pending?(paid)

    Application.delete_env(:espreso, :loyalty_earn_barrier)

    assert {:ok, result} = Loyalty.ensure_earn_for_paid_order(Repo.get!(Orders.Order, paid.id))

    assert match?(%{points: 1}, result) or match?({:already_earned, %{points_balance: 1}}, result)

    customer = Repo.get!(Espreso.Customers.Customer, customer.id)
    assert customer.points_balance == 1
    assert customer.spend_remainder_centavos == 0
    assert earn_count(paid.id) == 1
    refute Loyalty.earn_pending?(Repo.get!(Orders.Order, paid.id))
  end

  test "duplicate retry and already_paid do not double-award", %{customer: customer} do
    {:ok, unpaid} = create_unpaid(customer, "200")

    Application.put_env(:espreso, :loyalty_earn_barrier, fn -> {:error, :forced_failure} end)

    assert {:ok, :transitioned, paid} =
             Orders.mark_paid_with_transition(unpaid, paid_via: "cash")

    Application.delete_env(:espreso, :loyalty_earn_barrier)

    assert {:ok, :already_paid, _} =
             Orders.mark_paid_with_transition(paid, paid_via: "cash")

    assert earn_count(paid.id) == 1

    customer = Repo.get!(Espreso.Customers.Customer, customer.id)
    assert customer.points_balance == 1

    assert {:ok, {:already_earned, _}} =
             Loyalty.ensure_earn_for_paid_order(Repo.get!(Orders.Order, paid.id))

    assert earn_count(paid.id) == 1
    assert Repo.get!(Espreso.Customers.Customer, customer.id).points_balance == 1
  end

  test "staff mark_paid_with_transition already-paid path retries loyalty without reconciler", %{
    customer: customer
  } do
    # Create paid without earning so pending work exists without a failed-earn nudge race.
    assert {:ok, order} =
             Orders.create_order(
               [%{name: "Item", size: nil, quantity: 1, price: Decimal.new("200")}],
               %{
                 customer_name: "Hardening",
                 fulfillment: :pickup,
                 payment_method: :counter,
                 payment_status: :paid,
                 paid_via: "cash",
                 source: :pos,
                 customer_id: customer.id,
                 skip_authoritative_prices: true,
                 skip_loyalty_earn: true
               }
             )

    assert order.payment_status == "paid"
    assert Loyalty.earn_pending?(order)
    assert earn_count(order.id) == 0
    assert Repo.get!(Espreso.Customers.Customer, customer.id).points_balance == 0

    assert {:ok, :already_paid, paid} =
             Orders.mark_paid_with_transition(order, paid_via: "cash")

    assert paid.payment_status == "paid"
    assert earn_count(order.id) == 1

    customer = Repo.get!(Espreso.Customers.Customer, customer.id)
    assert customer.points_balance == 1
    assert customer.spend_remainder_centavos == 0
    refute Loyalty.earn_pending?(Repo.get!(Orders.Order, order.id))

    assert {:ok, :already_paid, _} =
             Orders.mark_paid_with_transition(order, paid_via: "cash")

    assert earn_count(order.id) == 1
    assert Repo.get!(Espreso.Customers.Customer, customer.id).points_balance == 1
  end

  test "PayMongo duplicate callback keeps payment and loyalty idempotent", %{customer: customer} do
    {:ok, unpaid} =
      Orders.create_order(
        [%{name: "Item", size: nil, quantity: 1, price: Decimal.new("200")}],
        %{
          customer_name: "Hardening",
          fulfillment: :pickup,
          payment_method: :online,
          payment_intent: :gcash,
          source: :customer,
          customer_id: customer.id
        }
      )

    Application.put_env(:espreso, :loyalty_earn_barrier, fn -> {:error, :forced_failure} end)
    assert {:ok, paid} = Orders.mark_paid_from_paymongo(unpaid.number)
    assert paid.payment_status == "paid"
    assert earn_count(paid.id) == 0

    Application.delete_env(:espreso, :loyalty_earn_barrier)
    assert {:ok, again} = Orders.mark_paid_from_paymongo(unpaid.number)
    assert again.payment_status == "paid"
    assert earn_count(again.id) == 1
    assert Repo.get!(Espreso.Customers.Customer, customer.id).points_balance == 1

    assert {:ok, _} = Orders.mark_paid_from_paymongo(unpaid.number)
    assert earn_count(again.id) == 1
  end

  test "POS create-paid failure leaves paid order and reconciler recovers", %{customer: customer} do
    Application.put_env(:espreso, :loyalty_earn_barrier, fn -> {:error, :forced_failure} end)

    assert {:ok, order} =
             Orders.create_order(
               [%{name: "Item", size: nil, quantity: 1, price: Decimal.new("200")}],
               %{
                 customer_name: "Hardening",
                 fulfillment: :pickup,
                 payment_method: :counter,
                 payment_status: :paid,
                 paid_via: "cash",
                 source: :pos,
                 customer_id: customer.id,
                 skip_authoritative_prices: true
               }
             )

    assert order.payment_status == "paid"
    assert Loyalty.earn_pending?(order)
    assert earn_count(order.id) == 0

    Application.delete_env(:espreso, :loyalty_earn_barrier)
    assert {:ok, results} = EarnReconciler.reconcile_now()

    assert Enum.any?(results, fn
             {id, {:ok, _}} -> id == order.id
             _ -> false
           end)

    assert earn_count(order.id) == 1
    assert Repo.get!(Espreso.Customers.Customer, customer.id).points_balance == 1
  end

  test "anonymous paid orders never create pending loyalty work" do
    assert {:ok, order} =
             Orders.create_order(
               [%{name: "Item", size: nil, quantity: 1, price: Decimal.new("200")}],
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

    refute Loyalty.earn_pending?(order)
    assert Loyalty.list_pending_earn_orders() == []
    assert earn_count(order.id) == 0
  end

  defp create_unpaid(customer, amount) do
    Orders.create_order(
      [%{name: "Item", size: nil, quantity: 1, price: Decimal.new(amount)}],
      %{
        customer_name: customer.name || "Hardening",
        fulfillment: :pickup,
        payment_method: :counter,
        source: :customer,
        customer_id: customer.id
      }
    )
  end

  defp earn_count(order_id) do
    LedgerEntry
    |> where([e], e.order_id == ^order_id and e.kind == "earn")
    |> Repo.aggregate(:count, :id)
  end
end

defmodule Espreso.OrdersPubSubTest do
  use Espreso.DataCase, async: false

  alias Espreso.Orders

  defp lines do
    [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]
  end

  defp attrs(extra \\ %{}) do
    Map.merge(
      %{
        customer_name: "PubSub",
        fulfillment: :pickup,
        payment_method: :counter
      },
      extra
    )
  end

  test "create_order broadcasts order_changed on the orders topic" do
    :ok = Orders.subscribe()

    assert {:ok, order} = Orders.create_order(lines(), attrs())
    assert_receive {:order_changed, %{id: id, number: number}}
    assert id == order.id
    assert number == order.number
  end

  test "update_status broadcasts order_changed" do
    {:ok, order} = Orders.create_order(lines(), attrs(%{customer_name: "Status Broadcast"}))
    :ok = Orders.subscribe()

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert_receive {:order_changed, %{id: id, status: "preparing"}}
    assert id == preparing.id
  end

  test "mark_paid broadcasts order_changed when payment changes" do
    {:ok, order} = Orders.create_order(lines(), attrs(%{customer_name: "Pay Broadcast"}))
    :ok = Orders.subscribe()

    assert {:ok, paid} = Orders.mark_paid(order)
    assert_receive {:order_changed, %{id: id, payment_status: "paid"}}
    assert id == paid.id
  end

  test "mark_paid does not broadcast when already paid" do
    {:ok, order} = Orders.create_order(lines(), attrs(%{customer_name: "Pay Idempotent"}))
    assert {:ok, paid} = Orders.mark_paid(order)

    :ok = Orders.subscribe()
    assert {:ok, ^paid} = Orders.mark_paid(paid)
    refute_receive {:order_changed, _}, 50
  end

  test "cancel_order broadcasts order_changed" do
    {:ok, order} = Orders.create_order(lines(), attrs(%{customer_name: "Cancel Broadcast"}))
    :ok = Orders.subscribe()

    assert {:ok, cancelled} = Orders.cancel_order(order)
    assert_receive {:order_changed, %{id: id, status: "cancelled"}}
    assert id == cancelled.id
  end

  test "complete_order broadcasts order_changed when status changes" do
    {:ok, order} = Orders.create_order(lines(), attrs(%{customer_name: "Complete Broadcast"}))
    {:ok, ready} = Orders.update_status(order, "ready")
    :ok = Orders.subscribe()

    assert {:ok, completed} = Orders.complete_order(ready)
    assert_receive {:order_changed, %{id: id, status: "completed"}}
    assert id == completed.id
  end

  test "complete_order does not broadcast when already completed" do
    {:ok, order} = Orders.create_order(lines(), attrs(%{customer_name: "Complete Idempotent"}))
    {:ok, ready} = Orders.update_status(order, "ready")
    assert {:ok, completed} = Orders.complete_order(ready)

    :ok = Orders.subscribe()
    assert {:ok, ^completed} = Orders.complete_order(completed)
    refute_receive {:order_changed, _}, 50
  end

  test "order-specific subscribe receives changes for that order only" do
    {:ok, watched} = Orders.create_order(lines(), attrs(%{customer_name: "Watched"}))
    {:ok, other} = Orders.create_order(lines(), attrs(%{customer_name: "Other"}))

    :ok = Orders.subscribe(watched)
    other_id = other.id

    assert {:ok, _} = Orders.update_status(other, "preparing")
    refute_receive {:order_changed, %{id: ^other_id}}, 50

    assert {:ok, _} = Orders.update_status(watched, "preparing")
    assert_receive {:order_changed, %{id: id, status: "preparing"}}
    assert id == watched.id
  end
end

defmodule Espreso.OrdersPaymentRaceTest do
  use Espreso.DataCase, async: false

  alias Espreso.Orders
  alias Espreso.Orders.{Order, PaymentReconciliation}
  alias Espreso.PayMongo
  alias Espreso.Repo

  setup do
    on_exit(fn ->
      Application.delete_env(:espreso, :orders_apply_paid_barrier)
      Application.delete_env(:espreso, :orders_cancel_barrier)
    end)

    :ok
  end

  test "abandon wins race held at payment update: cancelled, unpaid, reconciliation" do
    order = online_order!("cs_race_abandon_wins")
    parent = self()

    Application.put_env(:espreso, :orders_apply_paid_barrier, fn ->
      send(parent, {:apply_paid_barrier, self()})

      receive do
        :continue_apply_paid -> :ok
      end
    end)

    task =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())

        payload =
          webhook_payload(order.number,
            amount: 10_000,
            session_data: %{"id" => "cs_race_abandon_wins"}
          )
          |> Jason.decode!()

        PayMongo.handle_webhook_event(payload)
      end)

    assert_receive {:apply_paid_barrier, task_pid}
    assert {:ok, abandoned} = Orders.abandon_online_payment(order)
    assert abandoned.status == "cancelled"
    send(task_pid, :continue_apply_paid)

    assert {:error, :order_cancelled} = Task.await(task)

    order = Repo.get!(Order, order.id)
    assert order.status == "cancelled"
    assert order.payment_status == "unpaid"

    assert [%PaymentReconciliation{} = record] = Repo.all(PaymentReconciliation)
    assert record.paymongo_checkout_session_id == "cs_race_abandon_wins"
    assert record.amount_centavos == 10_000
  end

  test "payment wins race: abandon fails because order is already paid" do
    order = online_order!("cs_race_pay_wins")

    payload =
      webhook_payload(order.number,
        amount: 10_000,
        session_data: %{"id" => "cs_race_pay_wins"}
      )
      |> Jason.decode!()

    assert :ok = PayMongo.handle_webhook_event(payload)

    order = Repo.get!(Order, order.id)
    assert order.status == "received"
    assert order.payment_status == "paid"

    assert {:error, :paid} = Orders.abandon_online_payment(order)
    assert Repo.aggregate(PaymentReconciliation, :count, :id) == 0
  end

  test "duplicate paid webhook remains idempotent" do
    order = online_order!("cs_race_dup_paid")

    payload =
      webhook_payload(order.number,
        amount: 10_000,
        session_data: %{"id" => "cs_race_dup_paid"}
      )
      |> Jason.decode!()

    assert :ok = PayMongo.handle_webhook_event(payload)
    assert :ok = PayMongo.handle_webhook_event(payload)

    order = Repo.get!(Order, order.id)
    assert order.payment_status == "paid"
    assert Repo.aggregate(PaymentReconciliation, :count, :id) == 0
  end

  defp online_order!(session_id) do
    {:ok, order} =
      Orders.create_order(
        [line("Latte", "100.00")],
        %{customer_name: "Race", fulfillment: :pickup, payment_method: :online}
      )

    {:ok, order} = Orders.attach_paymongo_session(order, session_id)
    order
  end

  defp webhook_payload(reference_number, opts) do
    amount = Keyword.get(opts, :amount, 10_000)
    session_data = Keyword.get(opts, :session_data, %{})

    default_session = %{
      "id" => "cs_test_default",
      "type" => "checkout_session",
      "attributes" => %{
        "reference_number" => reference_number,
        "payments" => [
          %{
            "id" => "pay_test_race",
            "attributes" => %{
              "amount" => amount,
              "status" => "paid",
              "currency" => "PHP"
            }
          }
        ]
      }
    }

    session = Map.merge(default_session, session_data)

    Jason.encode!(%{
      "data" => %{
        "id" => "evt_race_1",
        "type" => "event",
        "attributes" => %{
          "type" => "checkout_session.payment.paid",
          "livemode" => false,
          "data" => session
        }
      }
    })
  end

  defp line(name, pesos) do
    %{
      name: name,
      size: "12oz",
      quantity: 1,
      price: Decimal.new(pesos)
    }
  end
end

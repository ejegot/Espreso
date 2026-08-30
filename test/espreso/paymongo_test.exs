defmodule Espreso.PayMongoTest do
  use Espreso.DataCase, async: true

  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.PayMongo
  alias Espreso.Repo

  describe "verify_webhook_signature/2" do
    test "accepts a valid test-mode signature" do
      payload = webhook_payload("CS-TEST01")
      signature = PayMongo.sign_for_test(payload)

      assert :ok = PayMongo.verify_webhook_signature(payload, signature)
    end

    test "rejects an invalid signature" do
      payload = webhook_payload("CS-TEST01")

      assert {:error, :invalid_signature} =
               PayMongo.verify_webhook_signature(payload, "t=1,te=bad,li=")
    end
  end

  describe "verify_webhook_livemode/1" do
    test "accepts matching test livemode" do
      payload =
        webhook_payload("CS-TEST01")
        |> Jason.decode!()

      assert :ok = PayMongo.verify_webhook_livemode(payload)
      assert {:ok, false} = PayMongo.expected_livemode()
    end

    test "rejects mismatched livemode" do
      payload =
        webhook_payload("CS-TEST01", livemode: true)
        |> Jason.decode!()

      assert {:error, :livemode_mismatch} = PayMongo.verify_webhook_livemode(payload)
    end

    test "rejects missing livemode" do
      payload = %{
        "data" => %{
          "attributes" => %{
            "type" => "checkout_session.payment.paid",
            "data" => %{}
          }
        }
      }

      assert {:error, :missing_livemode} = PayMongo.verify_webhook_livemode(payload)
    end
  end

  describe "handle_webhook_event/1" do
    test "marks the referenced order paid" do
      {:ok, order} =
        Orders.create_order(
          [line("Espresso", 120)],
          %{customer_name: "Ana", fulfillment: :pickup, payment_method: :online}
        )

      assert order.payment_status == "unpaid"

      payload =
        webhook_payload(order.number,
          session_data: %{
            "id" => "cs_test_123",
            "attributes" => %{"reference_number" => order.number}
          }
        )
        |> Jason.decode!()

      assert :ok = PayMongo.handle_webhook_event(payload)

      order = Repo.get!(Order, order.id)
      assert order.payment_status == "paid"
    end

    test "ignores unrelated event types" do
      payload = %{
        "data" => %{
          "attributes" => %{
            "type" => "payment.failed",
            "data" => %{}
          }
        }
      }

      assert :ok = PayMongo.handle_webhook_event(payload)
    end
  end

  defp webhook_payload(reference_number, opts \\ []) do
    livemode = Keyword.get(opts, :livemode, false)

    session_data = Keyword.get(opts, :session_data, %{})

    session =
      Map.merge(
        %{
          "id" => "cs_test_default",
          "type" => "checkout_session",
          "attributes" => %{"reference_number" => reference_number}
        },
        session_data
      )

    Jason.encode!(%{
      "data" => %{
        "id" => "evt_test_1",
        "type" => "event",
        "attributes" => %{
          "type" => "checkout_session.payment.paid",
          "livemode" => livemode,
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

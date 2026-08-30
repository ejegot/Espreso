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

  describe "pesos_to_centavos/1" do
    test "converts exact peso Decimals to integer centavos without float math" do
      assert {:ok, 10_000} = PayMongo.pesos_to_centavos(Decimal.new("100.00"))
      assert {:ok, 1_250} = PayMongo.pesos_to_centavos(Decimal.new("12.50"))
      assert {:ok, 99} = PayMongo.pesos_to_centavos(Decimal.new("0.99"))
    end

    test "rejects totals that are not an exact number of centavos" do
      assert {:error, :invalid_order_total} =
               PayMongo.pesos_to_centavos(Decimal.new("10.001"))
    end
  end

  describe "create_checkout_session/3" do
    test "creates a session when line-item centavos exactly match order.total" do
      lines = [
        %{name: "Latte", size: "12oz", quantity: 2, price: Decimal.new("12.50")},
        %{name: "Cookie", size: nil, quantity: 1, price: Decimal.new("75.00")}
      ]

      {:ok, order} =
        Orders.create_order(lines, %{
          customer_name: "Mia",
          fulfillment: :pickup,
          payment_method: :online
        })

      assert {:ok, 10_000} = PayMongo.pesos_to_centavos(order.total)
      assert {:ok, line_items} = PayMongo.build_checkout_line_items(lines)

      assert Enum.find(line_items, &(&1.name == "Latte (12oz)")) ==
               %{name: "Latte (12oz)", amount: 1_250, currency: "PHP", quantity: 2}

      assert Enum.find(line_items, &(&1.name == "Cookie")) ==
               %{name: "Cookie", amount: 7_500, currency: "PHP", quantity: 1}

      assert 1_250 * 2 + 7_500 == 10_000

      assert {:ok, %{id: session_id, checkout_url: checkout_url}} =
               PayMongo.create_checkout_session(order, lines,
                 channel: :gcash,
                 success_url: "https://example.test/success",
                 cancel_url: "https://example.test/cancel"
               )

      assert is_binary(session_id)
      assert is_binary(checkout_url)
      assert is_nil(Repo.get!(Order, order.id).paymongo_checkout_session_id)
    end

    test "rejects mismatched line totals before calling PayMongo" do
      lines = [
        %{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100.00")}
      ]

      {:ok, order} =
        Orders.create_order(lines, %{
          customer_name: "Mia",
          fulfillment: :pickup,
          payment_method: :online
        })

      mismatched = [
        %{name: "Latte", size: nil, quantity: 1, price: Decimal.new("99.00")}
      ]

      assert {:ok, _} =
               PayMongo.create_checkout_session(order, lines,
                 channel: :gcash,
                 success_url: "https://example.test/success",
                 cancel_url: "https://example.test/cancel"
               )

      assert {:error, :checkout_amount_mismatch} =
               PayMongo.create_checkout_session(order, mismatched,
                 channel: :gcash,
                 success_url: "https://example.test/success",
                 cancel_url: "https://example.test/cancel"
               )

      assert is_nil(Repo.get!(Order, order.id).paymongo_checkout_session_id)
    end

    test "rejects sub-centavo Decimal unit prices without rounding into a gateway amount" do
      lines = [
        %{name: "Weird", size: nil, quantity: 1, price: Decimal.new("10.001")}
      ]

      {:ok, order} =
        Orders.create_order(
          [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100.00")}],
          %{customer_name: "Mia", fulfillment: :pickup, payment_method: :online}
        )

      assert {:error, :invalid_line_amount} = PayMongo.build_checkout_line_items(lines)

      assert {:error, :invalid_line_amount} =
               PayMongo.create_checkout_session(order, lines,
                 channel: :gcash,
                 success_url: "https://example.test/success",
                 cancel_url: "https://example.test/cancel"
               )
    end

    test "accepts exact two-decimal Decimal prices" do
      lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("120.00")}]

      {:ok, order} =
        Orders.create_order(lines, %{
          customer_name: "Ana",
          fulfillment: :pickup,
          payment_method: :online
        })

      assert {:ok, [%{amount: 12_000, quantity: 1}]} = PayMongo.build_checkout_line_items(lines)

      assert {:ok, %{id: _}} =
               PayMongo.create_checkout_session(order, lines,
                 channel: :maya,
                 success_url: "https://example.test/success",
                 cancel_url: "https://example.test/cancel"
               )
    end
  end

  describe "handle_webhook_event/1" do
    test "marks the referenced order paid when amount and session match" do
      {:ok, order} =
        Orders.create_order(
          [line("Espresso", "120.00")],
          %{customer_name: "Ana", fulfillment: :pickup, payment_method: :online}
        )

      {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_123")
      assert order.payment_status == "unpaid"

      payload =
        webhook_payload(order.number,
          amount: 12_000,
          session_data: %{
            "id" => "cs_test_123",
            "attributes" => %{
              "reference_number" => order.number,
              "payments" => [
                %{
                  "id" => "pay_test_123",
                  "attributes" => %{
                    "amount" => 12_000,
                    "status" => "paid",
                    "currency" => "PHP"
                  }
                }
              ]
            }
          }
        )
        |> Jason.decode!()

      assert :ok = PayMongo.handle_webhook_event(payload)

      order = Repo.get!(Order, order.id)
      assert order.payment_status == "paid"
      assert order.paymongo_checkout_session_id == "cs_test_123"
    end

    test "rejects session mismatch without marking paid" do
      {:ok, order} =
        Orders.create_order(
          [line("Espresso", "120.00")],
          %{customer_name: "Ana", fulfillment: :pickup, payment_method: :online}
        )

      {:ok, order} = Orders.attach_paymongo_session(order, "cs_stored")

      payload =
        webhook_payload(order.number,
          amount: 12_000,
          session_data: %{
            "id" => "cs_webhook",
            "attributes" => %{
              "reference_number" => order.number,
              "payments" => [
                %{
                  "id" => "pay_test_123",
                  "attributes" => %{
                    "amount" => 12_000,
                    "status" => "paid",
                    "currency" => "PHP"
                  }
                }
              ]
            }
          }
        )
        |> Jason.decode!()

      assert {:error, :session_mismatch} = PayMongo.handle_webhook_event(payload)
      order = Repo.get!(Order, order.id)
      assert order.payment_status == "unpaid"
      assert order.paymongo_checkout_session_id == "cs_stored"
    end

    test "rejects missing stored session without backfilling" do
      {:ok, order} =
        Orders.create_order(
          [line("Espresso", "120.00")],
          %{customer_name: "Ana", fulfillment: :pickup, payment_method: :online}
        )

      payload =
        webhook_payload(order.number,
          amount: 12_000,
          session_data: %{
            "id" => "cs_test_123",
            "attributes" => %{
              "reference_number" => order.number,
              "payments" => [
                %{
                  "id" => "pay_test_123",
                  "attributes" => %{
                    "amount" => 12_000,
                    "status" => "paid",
                    "currency" => "PHP"
                  }
                }
              ]
            }
          }
        )
        |> Jason.decode!()

      assert {:error, :missing_session} = PayMongo.handle_webhook_event(payload)
      order = Repo.get!(Order, order.id)
      assert order.payment_status == "unpaid"
      assert is_nil(order.paymongo_checkout_session_id)
    end

    test "rejects missing webhook session id" do
      {:ok, order} =
        Orders.create_order(
          [line("Espresso", "120.00")],
          %{customer_name: "Ana", fulfillment: :pickup, payment_method: :online}
        )

      {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_123")

      payload =
        webhook_payload(order.number,
          amount: 12_000,
          session_data: %{
            "attributes" => %{
              "reference_number" => order.number,
              "payments" => [
                %{
                  "id" => "pay_test_123",
                  "attributes" => %{
                    "amount" => 12_000,
                    "status" => "paid",
                    "currency" => "PHP"
                  }
                }
              ]
            }
          }
        )
        |> Jason.decode!()
        |> update_in(["data", "attributes", "data"], &Map.delete(&1, "id"))

      assert {:error, :missing_session} = PayMongo.handle_webhook_event(payload)
      order = Repo.get!(Order, order.id)
      assert order.payment_status == "unpaid"
      assert order.paymongo_checkout_session_id == "cs_test_123"
    end

    test "rejects amount mismatch without marking paid" do
      {:ok, order} =
        Orders.create_order(
          [line("Espresso", "120.00")],
          %{customer_name: "Ana", fulfillment: :pickup, payment_method: :online}
        )

      {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_123")

      payload =
        webhook_payload(order.number,
          session_data: %{
            "id" => "cs_test_123",
            "attributes" => %{
              "reference_number" => order.number,
              "payments" => [
                %{
                  "id" => "pay_test_123",
                  "attributes" => %{
                    "amount" => 11_999,
                    "status" => "paid",
                    "currency" => "PHP"
                  }
                }
              ]
            }
          }
        )
        |> Jason.decode!()

      assert {:error, :amount_mismatch} = PayMongo.handle_webhook_event(payload)
      order = Repo.get!(Order, order.id)
      assert order.payment_status == "unpaid"
      assert order.paymongo_checkout_session_id == "cs_test_123"
    end

    test "rejects cancelled orders without marking paid" do
      {:ok, order} =
        Orders.create_order(
          [line("Espresso", "120.00")],
          %{customer_name: "Ana", fulfillment: :pickup, payment_method: :online}
        )

      {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_123")

      {:ok, order} =
        order
        |> Order.cancel_changeset()
        |> Repo.update()

      payload =
        webhook_payload(order.number,
          amount: 12_000,
          session_data: %{
            "id" => "cs_test_123",
            "attributes" => %{
              "reference_number" => order.number,
              "payments" => [
                %{
                  "id" => "pay_test_123",
                  "attributes" => %{
                    "amount" => 12_000,
                    "status" => "paid",
                    "currency" => "PHP"
                  }
                }
              ]
            }
          }
        )
        |> Jason.decode!()

      assert {:error, :order_cancelled} = PayMongo.handle_webhook_event(payload)

      order = Repo.get!(Order, order.id)
      assert order.status == "cancelled"
      assert order.payment_status == "unpaid"
      assert order.paymongo_checkout_session_id == "cs_test_123"
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
    amount = Keyword.get(opts, :amount, 0)

    session_data = Keyword.get(opts, :session_data, %{})

    default_session = %{
      "id" => "cs_test_default",
      "type" => "checkout_session",
      "attributes" => %{
        "reference_number" => reference_number,
        "payments" => [
          %{
            "id" => "pay_test_default",
            "attributes" => %{
              "amount" => amount,
              "status" => "paid",
              "currency" => "PHP"
            }
          }
        ]
      }
    }

    session = deep_merge(default_session, session_data)

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

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
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

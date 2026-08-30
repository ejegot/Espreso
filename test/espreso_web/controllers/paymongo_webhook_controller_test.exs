defmodule EspresoWeb.PayMongoWebhookControllerTest do
  use EspresoWeb.ConnCase, async: true

  alias Espreso.Orders
  alias Espreso.PayMongo
  alias Espreso.Repo

  test "marks order paid on checkout_session.payment.paid", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [line("Latte", 150)],
        %{customer_name: "Mia", fulfillment: :pickup, payment_method: :online}
      )

    payload =
      Jason.encode!(%{
        "data" => %{
          "id" => "evt_live_1",
          "type" => "event",
          "attributes" => %{
            "type" => "checkout_session.payment.paid",
            "livemode" => false,
            "data" => %{
              "id" => "cs_test_webhook",
              "type" => "checkout_session",
              "attributes" => %{
                "reference_number" => order.number
              }
            }
          }
        }
      })

    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 200) == %{"received" => true}

    order = Repo.get!(Espreso.Orders.Order, order.id)
    assert order.payment_status == "paid"
  end

  test "rejects invalid signatures", %{conn: conn} do
    payload = ~s({"data":{"attributes":{"type":"checkout_session.payment.paid"}}})

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", "t=1,te=bad,li=")
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 401) == %{"error" => "invalid signature"}
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

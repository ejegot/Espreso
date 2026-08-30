defmodule EspresoWeb.PayMongoWebhookControllerTest do
  use EspresoWeb.ConnCase, async: true

  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.PayMongo
  alias Espreso.Repo

  setup do
    {:ok, order} =
      Orders.create_order(
        [line("Latte", 150)],
        %{customer_name: "Mia", fulfillment: :pickup, payment_method: :online}
      )

    payload = paid_webhook_payload(order.number)
    {:ok, order: order, payload: payload}
  end

  test "marks order paid on checkout_session.payment.paid", %{conn: conn, order: order, payload: payload} do
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 200) == %{"received" => true}

    order = Repo.get!(Order, order.id)
    assert order.payment_status == "paid"
  end

  test "rejects invalid HMAC with 401 and does not mark order paid", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", "t=1,te=bad,li=")
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 401) == %{"error" => "invalid signature"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "rejects missing signature with 401 and does not mark order paid", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 401) == %{"error" => "invalid signature"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "rejects missing timestamp with 401 and does not mark order paid", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", "te=abc123,li=")
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 401) == %{"error" => "invalid signature"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "rejects empty signature values with 401 and does not mark order paid", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", "t=1496734173,te=,li=")
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 401) == %{"error" => "invalid signature"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "accepts test livemode when app is in test mode", %{conn: conn, order: order, payload: payload} do
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 200) == %{"received" => true}
    assert Repo.get!(Order, order.id).payment_status == "paid"
  end

  test "rejects live livemode when app is in test mode", %{conn: conn, order: order} do
    payload = paid_webhook_payload(order.number, livemode: true)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 403) == %{"error" => "livemode mismatch"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "accepts live livemode when app is in live mode", %{conn: conn} do
    original = Application.get_env(:espreso, :paymongo)

    on_exit(fn -> Application.put_env(:espreso, :paymongo, original) end)

    Application.put_env(
      :espreso,
      :paymongo,
      Keyword.put(original, :secret_key, "sk_live_placeholder")
    )

    {:ok, order} =
      Orders.create_order(
        [line("Latte", 150)],
        %{customer_name: "Mia", fulfillment: :pickup, payment_method: :online}
      )

    payload = paid_webhook_payload(order.number, livemode: true)
    signature = PayMongo.sign_for_test(payload, mode: :live)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 200) == %{"received" => true}
    assert Repo.get!(Order, order.id).payment_status == "paid"
  end

  test "rejects test livemode when app is in live mode", %{conn: conn} do
    original = Application.get_env(:espreso, :paymongo)

    on_exit(fn -> Application.put_env(:espreso, :paymongo, original) end)

    Application.put_env(
      :espreso,
      :paymongo,
      Keyword.put(original, :secret_key, "sk_live_placeholder")
    )

    {:ok, order} =
      Orders.create_order(
        [line("Latte", 150)],
        %{customer_name: "Mia", fulfillment: :pickup, payment_method: :online}
      )

    payload = paid_webhook_payload(order.number, livemode: false)
    signature = PayMongo.sign_for_test(payload, mode: :live)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 403) == %{"error" => "livemode mismatch"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "rejects missing livemode with 400 and does not mark order paid", %{
    conn: conn,
    order: order
  } do
    payload = paid_webhook_payload(order.number, include_livemode?: false)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 400) == %{"error" => "missing livemode"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  defp paid_webhook_payload(reference_number, opts \\ []) do
    livemode? = Keyword.get(opts, :include_livemode?, true)
    livemode = Keyword.get(opts, :livemode, false)

    attributes =
      %{
        "type" => "checkout_session.payment.paid",
        "data" => %{
          "id" => "cs_test_webhook",
          "type" => "checkout_session",
          "attributes" => %{
            "reference_number" => reference_number
          }
        }
      }
      |> then(fn attrs ->
        if livemode?, do: Map.put(attrs, "livemode", livemode), else: attrs
      end)

    Jason.encode!(%{
      "data" => %{
        "id" => "evt_live_1",
        "type" => "event",
        "attributes" => attributes
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

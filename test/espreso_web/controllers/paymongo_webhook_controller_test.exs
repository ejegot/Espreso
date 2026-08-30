defmodule EspresoWeb.PayMongoWebhookControllerTest do
  use EspresoWeb.ConnCase, async: true

  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.PayMongo
  alias Espreso.Repo

  setup do
    {:ok, order} =
      Orders.create_order(
        [line("Latte", "100.00")],
        %{customer_name: "Mia", fulfillment: :pickup, payment_method: :online}
      )

    payload = paid_webhook_payload(order.number, amount: 10_000)
    {:ok, order: order, payload: payload}
  end

  test "marks order paid when amount and session match", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_webhook")
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 200) == %{"received" => true}

    order = Repo.get!(Order, order.id)
    assert order.payment_status == "paid"
    assert Decimal.equal?(order.total, Decimal.new("100.00"))
    assert order.paymongo_checkout_session_id == "cs_test_webhook"
  end

  test "rejects paid webhook for cancelled order and does not mark paid", %{
    conn: conn,
    order: order
  } do
    {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_webhook")

    {:ok, order} =
      order
      |> Order.cancel_changeset()
      |> Repo.update()

    assert order.status == "cancelled"
    assert order.payment_status == "unpaid"

    payload = paid_webhook_payload(order.number, amount: 10_000)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 422) == %{"error" => "order cancelled"}

    order = Repo.get!(Order, order.id)
    assert order.status == "cancelled"
    assert order.payment_status == "unpaid"
    assert order.paymongo_checkout_session_id == "cs_test_webhook"
  end

  test "rejects paid webhook after abandon_online_payment and does not mark paid", %{
    conn: conn,
    order: order
  } do
    {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_webhook")
    assert {:ok, order} = Orders.abandon_online_payment(order)
    assert order.status == "cancelled"
    assert order.payment_status == "unpaid"
    assert order.paymongo_checkout_session_id == "cs_test_webhook"

    payload = paid_webhook_payload(order.number, amount: 10_000)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 422) == %{"error" => "order cancelled"}

    order = Repo.get!(Order, order.id)
    assert order.status == "cancelled"
    assert order.payment_status == "unpaid"
    assert order.paymongo_checkout_session_id == "cs_test_webhook"
  end

  test "rejects mismatched checkout session and does not mark order paid", %{
    conn: conn,
    order: order
  } do
    {:ok, order} = Orders.attach_paymongo_session(order, "cs_stored")
    payload = paid_webhook_payload(order.number, amount: 10_000, session_id: "cs_webhook")
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 422) == %{"error" => "session mismatch"}
    order = Repo.get!(Order, order.id)
    assert order.payment_status == "unpaid"
    assert order.paymongo_checkout_session_id == "cs_stored"
  end

  test "rejects missing stored session and does not backfill", %{conn: conn, order: order} do
    payload = paid_webhook_payload(order.number, amount: 10_000)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 400) == %{"error" => "missing session"}
    order = Repo.get!(Order, order.id)
    assert order.payment_status == "unpaid"
    assert is_nil(order.paymongo_checkout_session_id)
  end

  test "rejects missing webhook session id and does not mark order paid", %{
    conn: conn,
    order: order
  } do
    {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_webhook")
    payload = paid_webhook_payload(order.number, amount: 10_000, include_session_id?: false)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 400) == %{"error" => "missing session"}
    order = Repo.get!(Order, order.id)
    assert order.payment_status == "unpaid"
    assert order.paymongo_checkout_session_id == "cs_test_webhook"
  end

  test "rejects amount one centavo too low and does not mark order paid", %{
    conn: conn,
    order: order
  } do
    payload = paid_webhook_payload(order.number, amount: 9_999)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 422) == %{"error" => "amount mismatch"}
    order = Repo.get!(Order, order.id)
    assert order.payment_status == "unpaid"
    assert is_nil(order.paymongo_checkout_session_id)
  end

  test "rejects amount one centavo too high and does not mark order paid", %{
    conn: conn,
    order: order
  } do
    payload = paid_webhook_payload(order.number, amount: 10_001)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 422) == %{"error" => "amount mismatch"}
    order = Repo.get!(Order, order.id)
    assert order.payment_status == "unpaid"
    assert is_nil(order.paymongo_checkout_session_id)
  end

  test "rejects missing amount and does not mark order paid", %{conn: conn, order: order} do
    payload = paid_webhook_payload(order.number, include_amount?: false)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 400) == %{"error" => "missing amount"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "rejects negative amount and does not mark order paid", %{conn: conn, order: order} do
    payload = paid_webhook_payload(order.number, amount: -100)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 400) == %{"error" => "invalid amount"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "rejects non-integer amount and does not mark order paid", %{conn: conn, order: order} do
    payload = paid_webhook_payload(order.number, amount: 100.5)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 400) == %{"error" => "invalid amount"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  test "converts decimal peso totals to exact centavos without float math", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [line("Cookie", "12.50")],
        %{customer_name: "Sam", fulfillment: :pickup, payment_method: :online}
      )

    assert {:ok, 1_250} = PayMongo.pesos_to_centavos(order.total)

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_webhook")
    payload = paid_webhook_payload(order.number, amount: 1_250)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 200) == %{"received" => true}
    assert Repo.get!(Order, order.id).payment_status == "paid"
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
    order = Repo.get!(Order, order.id)
    assert order.payment_status == "unpaid"
    assert is_nil(order.paymongo_checkout_session_id)
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

  test "accepts test livemode when app is in test mode", %{
    conn: conn,
    order: order,
    payload: payload
  } do
    {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_webhook")
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 200) == %{"received" => true}
    assert Repo.get!(Order, order.id).payment_status == "paid"
  end

  test "rejects live livemode when app is in test mode", %{
    conn: conn,
    order: order
  } do
    payload = paid_webhook_payload(order.number, amount: 10_000, livemode: true)
    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 403) == %{"error" => "livemode mismatch"}
    order = Repo.get!(Order, order.id)
    assert order.payment_status == "unpaid"
    assert is_nil(order.paymongo_checkout_session_id)
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
        [line("Latte", "100.00")],
        %{customer_name: "Mia", fulfillment: :pickup, payment_method: :online}
      )

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_test_webhook")
    payload = paid_webhook_payload(order.number, amount: 10_000, livemode: true)
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
        [line("Latte", "100.00")],
        %{customer_name: "Mia", fulfillment: :pickup, payment_method: :online}
      )

    payload = paid_webhook_payload(order.number, amount: 10_000, livemode: false)
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
    payload =
      paid_webhook_payload(
        order.number,
        amount: 10_000,
        include_livemode?: false
      )

    signature = PayMongo.sign_for_test(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("paymongo-signature", signature)
      |> post(~p"/webhooks/paymongo", payload)

    assert json_response(conn, 400) == %{"error" => "missing livemode"}
    assert Repo.get!(Order, order.id).payment_status == "unpaid"
  end

  defp paid_webhook_payload(reference_number, opts) do
    livemode? = Keyword.get(opts, :include_livemode?, true)
    livemode = Keyword.get(opts, :livemode, false)
    include_amount? = Keyword.get(opts, :include_amount?, true)
    include_session_id? = Keyword.get(opts, :include_session_id?, true)
    amount = Keyword.get(opts, :amount, 10_000)
    session_id = Keyword.get(opts, :session_id, "cs_test_webhook")

    session_attributes =
      %{"reference_number" => reference_number}
      |> then(fn attrs ->
        if include_amount? do
          Map.put(attrs, "payments", [
            %{
              "id" => "pay_test_1",
              "type" => "payment",
              "attributes" => %{
                "amount" => amount,
                "currency" => "PHP",
                "status" => "paid"
              }
            }
          ])
        else
          attrs
        end
      end)

    session =
      %{"type" => "checkout_session", "attributes" => session_attributes}
      |> then(fn data ->
        if include_session_id?, do: Map.put(data, "id", session_id), else: data
      end)

    attributes =
      %{
        "type" => "checkout_session.payment.paid",
        "data" => session
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

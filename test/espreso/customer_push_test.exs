defmodule Espreso.CustomerPushTest do
  use Espreso.DataCase, async: true

  alias Espreso.CustomerPush
  alias Espreso.CustomerPush.Subscription
  alias Espreso.Orders
  alias Espreso.Repo

  @lines [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

  test "subscribes a QR order and notifies preparing then ready" do
    {:ok, order} = create_customer_order("Push Guest")
    flush_push()

    assert {:ok, _subscription} = CustomerPush.subscribe(order, push_attrs())

    assert {:ok, paid} = Orders.mark_paid(order, paid_via: "cash")
    assert paid.status == "preparing"

    assert_received {Espreso.CustomerPush, payload, subscription}
    assert payload["title"] == "CoffeeSpot"
    assert payload["body"] == "We're preparing #{order.number}."
    assert payload["url"] == "/order/#{order.number}"
    assert subscription["endpoint"] == push_attrs()["endpoint"]

    assert {:ok, _ready} = Orders.update_status(paid, "ready")

    assert_received {Espreso.CustomerPush, ready_payload, _}
    assert ready_payload["body"] =~ "Ready for pick up — #{order.number}"
  end

  test "does not notify POS orders" do
    {:ok, order} =
      Orders.create_order(@lines, %{
        customer_name: "POS Guest",
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :paid,
        paid_via: "cash",
        source: :pos,
        skip_authoritative_prices: true
      })

    flush_push()

    assert {:error, :not_customer_order} = CustomerPush.subscribe(order, push_attrs())
    refute_received {Espreso.CustomerPush, _, _}
  end

  test "does not notify when there is no subscription" do
    {:ok, order} = create_customer_order("No Sub")
    flush_push()

    assert {:ok, paid} = Orders.mark_paid(order, paid_via: "cash")
    assert paid.status == "preparing"
    refute_received {Espreso.CustomerPush, _, _}
  end

  test "skips subscriptions older than four hours" do
    {:ok, order} = create_customer_order("Stale Push")
    assert {:ok, subscription} = CustomerPush.subscribe(order, push_attrs())

    stale =
      DateTime.utc_now()
      |> DateTime.add(-5 * 3600, :second)
      |> DateTime.truncate(:second)

    subscription
    |> Ecto.Changeset.change(%{inserted_at: stale, updated_at: stale})
    |> Repo.update!()

    flush_push()
    assert {:ok, _} = Orders.mark_paid(order, paid_via: "cash")
    refute_received {Espreso.CustomerPush, _, _}
  end

  test "status_changeset to the same status does not send another push" do
    {:ok, order} = create_customer_order("Once")
    assert {:ok, _} = CustomerPush.subscribe(order, push_attrs())
    assert {:ok, paid} = Orders.mark_paid(order, paid_via: "cash")
    assert_received {Espreso.CustomerPush, _, _}

    assert {:ok, again} = Orders.update_status(paid, "preparing")
    assert again.status == "preparing"
    refute_received {Espreso.CustomerPush, _, _}
  end

  test "upserts the same endpoint for an order" do
    {:ok, order} = create_customer_order("Upsert")
    attrs = push_attrs()
    assert {:ok, first} = CustomerPush.subscribe(order, attrs)

    updated = Map.put(attrs, "auth", String.duplicate("C", 16))
    assert {:ok, second} = CustomerPush.subscribe(order, updated)
    assert first.id == second.id
    assert Repo.aggregate(Subscription, :count) == 1
    assert second.auth == String.duplicate("C", 16)
  end

  test "web push encrypts and signs before the HTTP call" do
    {ua_public, _ua_private} = :crypto.generate_key(:ecdh, :prime256v1)
    {vapid_public, vapid_private} = :crypto.generate_key(:ecdh, :prime256v1)

    subscription = %{
      "endpoint" => "http://127.0.0.1:1/push",
      "keys" => %{
        "p256dh" => Base.url_encode64(ua_public, padding: false),
        "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      }
    }

    vapid = %{
      public_key: Base.url_encode64(vapid_public, padding: false),
      private_key: Base.url_encode64(vapid_private, padding: false),
      subject: "mailto:test@example.com"
    }

    result =
      Espreso.CustomerPush.WebPush.send_web_push(
        ~s({"title":"CoffeeSpot"}),
        subscription,
        vapid
      )

    assert match?({:error, _}, result)
    refute result in [{:error, :invalid_vapid}, {:error, :invalid_subscription}]
  end

  defp create_customer_order(name) do
    Orders.create_order(@lines, %{
      customer_name: name,
      fulfillment: :pickup,
      payment_method: :counter
    })
  end

  defp push_attrs do
    %{
      "endpoint" => "https://fcm.googleapis.com/fcm/send/abcdefghijklmnopqrstuvwxyz0123456789",
      "p256dh" => String.duplicate("B", 32),
      "auth" => String.duplicate("A", 16)
    }
  end

  defp flush_push do
    receive do
      {Espreso.CustomerPush, _, _} -> flush_push()
    after
      0 -> :ok
    end
  end
end

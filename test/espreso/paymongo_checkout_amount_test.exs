defmodule Espreso.PayMongoCheckoutAmountTest do
  use Espreso.DataCase, async: false

  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.PayMongo
  alias Espreso.Repo

  defmodule SpyClient do
    @moduledoc false
    @behaviour Espreso.PayMongo.Client

    @impl true
    def create_checkout_session(order, lines, opts) do
      if pid = Application.get_env(:espreso, :paymongo_test_spy) do
        send(pid, {:paymongo_called, order, lines})
      end

      Espreso.PayMongo.StubClient.create_checkout_session(order, lines, opts)
    end
  end

  setup do
    original = Application.get_env(:espreso, :paymongo)

    on_exit(fn ->
      Application.put_env(:espreso, :paymongo, original)
      Application.delete_env(:espreso, :paymongo_test_spy)
    end)

    :ok
  end

  test "checkout amount mismatch does not call the PayMongo client or attach a session" do
    lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100.00")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Mia",
        fulfillment: :pickup,
        payment_method: :online
      })

    mismatched = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("50.00")}]
    parent = self()

    Application.put_env(:espreso, :paymongo_test_spy, parent)

    Application.put_env(
      :espreso,
      :paymongo,
      Keyword.put(Application.get_env(:espreso, :paymongo), :client, SpyClient)
    )

    assert {:error, :checkout_amount_mismatch} =
             PayMongo.create_checkout_session(order, mismatched,
               channel: :gcash,
               success_url: "https://example.test/success",
               cancel_url: "https://example.test/cancel"
             )

    refute_received {:paymongo_called, _, _}
    assert is_nil(Repo.get!(Order, order.id).paymongo_checkout_session_id)
  end
end

defmodule EspresoWeb.OrderChannelTest do
  use EspresoWeb.ChannelCase, async: false

  alias Espreso.Accounts
  alias Espreso.Accounts.Token
  alias Espreso.Orders

  test "join orders:lobby with valid token and receive order_created" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Channel Staff",
        email: "channel.staff@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    {:ok, tokens} = Token.issue_token_pair(user)
    {:ok, socket} = connect(EspresoWeb.UserSocket, %{})

    assert {:ok, _reply, _joined_socket} =
             subscribe_and_join(socket, "orders:lobby", %{"token" => tokens.access_token})

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Channel Order", fulfillment: :pickup, payment_method: :counter}
      )

    assert_receive %Phoenix.Socket.Message{
                     event: "order_created",
                     payload: %{order: %{id: order_id}}
                   }

    assert order_id == order.id
  end

  test "join orders:lobby rejects invalid token" do
    {:ok, socket} = connect(EspresoWeb.UserSocket, %{})

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(socket, "orders:lobby", %{"token" => "bad.token.value"})
  end
end

defmodule EspresoWeb.OrderChannel do
  use EspresoWeb, :channel

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.Token
  alias Espreso.Orders
  alias EspresoWeb.Api.JSON

  @impl true
  def join("orders:lobby", %{"token" => token}, socket) when is_binary(token) do
    with {:ok, user} <- Token.verify_access(token),
         :ok <- Authorization.authorize(user, :orders) do
      Orders.subscribe()
      {:ok, assign(socket, :current_user, user)}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  def join("orders:lobby", _params, _socket), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_info({:order_changed, order}, socket) do
    event = order_event_name(order)
    push(socket, event, %{order: JSON.order(order)})
    {:noreply, socket}
  end

  defp order_event_name(%Orders.Order{} = order) do
    if order.inserted_at == order.updated_at, do: "order_created", else: "order_updated"
  end
end

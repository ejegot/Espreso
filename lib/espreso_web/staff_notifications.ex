defmodule EspresoWeb.StaffNotifications do
  @moduledoc """
  Helpers for pushing live order alerts into the staff shell bell.
  """

  alias Espreso.Orders.Order
  alias EspresoWeb.StaffNotificationsComponent

  @doc """
  Forward an order change into the staff notifications LiveComponent.
  """
  def push_order_change(%Order{} = order) do
    Phoenix.LiveView.send_update(StaffNotificationsComponent,
      id: "staff-notifications",
      order_changed: order
    )

    :ok
  end

  def push_order_change(_), do: :ok
end

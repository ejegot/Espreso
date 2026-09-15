defmodule EspresoWeb.PrinterClientBridge do
  @moduledoc false

  import Phoenix.LiveView, only: [push_event: 3]

  alias Espreso.PhysicalActionCoordinator
  alias Espreso.Printer

  @event "elilai-printer"

  def push_client_dispatch(socket, attrs) when is_map(attrs) do
    push_event(socket, @event, %{
      action: to_string(Map.fetch!(attrs, :action)),
      permit: Map.fetch!(attrs, :permit),
      request_id: Map.fetch!(attrs, :request_id),
      data_base64: Map.fetch!(attrs, :data_base64),
      order_id: Map.fetch!(attrs, :order_id),
      flow: to_string(Map.get(attrs, :flow, Map.fetch!(attrs, :action)))
    })
  end

  def maybe_push_mark_paid_physical(socket, order_id, permit, physical_result) do
    case physical_result do
      {:client_dispatch, phase, data_base64, request_id} when is_binary(permit) ->
        push_client_dispatch(socket, %{
          action: :mark_paid,
          permit: permit,
          request_id: request_id,
          data_base64: data_base64,
          order_id: order_id,
          flow: phase
        })

      _ ->
        socket
    end
  end

  def maybe_push_settle_physical(socket, order_id, permit, physical_result) do
    case physical_result do
      {:client_dispatch, phase, data_base64, request_id} when is_binary(permit) ->
        push_client_dispatch(socket, %{
          action: :settle_physical,
          permit: permit,
          request_id: request_id,
          data_base64: data_base64,
          order_id: order_id,
          flow: phase
        })

      _ ->
        socket
    end
  end

  def maybe_push_single_physical(socket, order_id, action, permit, result) do
    case result do
      {:client_dispatch, data_base64, request_id} when is_binary(permit) ->
        push_client_dispatch(socket, %{
          action: action,
          permit: permit,
          request_id: request_id,
          data_base64: data_base64,
          order_id: order_id,
          flow: action
        })

      _ ->
        socket
    end
  end

  def confirm_params(%{
        "order_id" => order_id,
        "action" => action,
        "permit" => permit,
        "request_id" => request_id,
        "ok" => ok
      } = params) do
    case parse_action(action) do
      {:ok, action_atom} ->
        client_result =
          if ok in [true, "true"] do
            :ok
          else
            {:error, normalize_error(Map.get(params, "error"))}
          end

        {order_id, action_atom, permit, request_id, client_result}

      :invalid ->
        :invalid
    end
  end

  def confirm_params(_), do: :invalid

  def run_confirm(order_id, action, permit, request_id, client_result, opts \\ []) do
    PhysicalActionCoordinator.confirm_client_physical(
      order_id,
      action,
      permit,
      request_id,
      client_result,
      opts
    )
  end

  def settle_physical_for_paid_order(order, paid_via, opts \\ []) when is_binary(paid_via) do
    if Printer.enabled?() do
      permits = PhysicalActionCoordinator.permits(:settle_physical, [order.id])
      permit = Map.get(permits, order.id)

      if is_binary(permit) do
        result =
          PhysicalActionCoordinator.execute_settle_physical(order.id, permit, paid_via, opts)

        {permit, result}
      else
        {nil, {:ineligible, :no_permit}}
      end
    else
      {nil, {:ok, :settle_physical, order, :disabled}}
    end
  end

  defp parse_action("receipt_reprint"), do: {:ok, :receipt_reprint}
  defp parse_action("kitchen"), do: {:ok, :kitchen}
  defp parse_action("drawer"), do: {:ok, :drawer}
  defp parse_action("mark_paid"), do: {:ok, :mark_paid}
  defp parse_action("settle_physical"), do: {:ok, :settle_physical}
  defp parse_action(_), do: :invalid

  defp normalize_error(nil), do: :printer_unreachable
  defp normalize_error(""), do: :printer_unreachable
  defp normalize_error(error) when is_binary(error), do: error
  defp normalize_error(error), do: inspect(error)
end

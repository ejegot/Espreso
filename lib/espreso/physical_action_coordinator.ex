defmodule Espreso.PhysicalActionCoordinator do
  @moduledoc """
  Single-node coordinator for protected physical printer actions.

  Reprint permits are shared across LiveViews and consumed before printer I/O.
  """

  use GenServer

  alias Espreso.Orders.Order
  alias Espreso.Printer
  alias Espreso.Repo

  @action :receipt_reprint
  @eligible_statuses ~w(received preparing ready)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def reprint_permits(order_ids, server \\ __MODULE__) when is_list(order_ids) do
    GenServer.call(server, {:reprint_permits, order_ids})
  end

  def execute_reprint(order_id, action, permit_id, opts \\ [])

  def execute_reprint(order_id, action, permit_id, opts) when is_binary(order_id) do
    case Integer.parse(order_id) do
      {parsed_id, ""} -> execute_reprint(parsed_id, action, permit_id, opts)
      _ -> {:stale, :invalid_order_id}
    end
  end

  def execute_reprint(order_id, action, permit_id, opts) when is_integer(order_id) do
    server = Keyword.get(opts, :server, __MODULE__)
    staff_name = Keyword.get(opts, :staff_name)

    GenServer.call(
      server,
      {:execute_reprint, order_id, action, permit_id, staff_name},
      :infinity
    )
  end

  def acknowledge_recovery(server \\ __MODULE__) do
    GenServer.call(server, :acknowledge_recovery)
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    restart_key = {__MODULE__, :started, name}
    recovery_required? = :persistent_term.get(restart_key, false)
    :persistent_term.put(restart_key, true)

    {:ok,
     %{
       permits: %{},
       recovery_required?: recovery_required?,
       dispatch_receipt: Keyword.get(opts, :dispatch_receipt, &Printer.dispatch_receipt/2)
     }}
  end

  @impl true
  def handle_call({:reprint_permits, _order_ids}, _from, %{recovery_required?: true} = state) do
    {:reply, %{}, state}
  end

  def handle_call({:reprint_permits, order_ids}, _from, state) do
    {permits, state} =
      order_ids
      |> Enum.uniq()
      |> Enum.reduce({%{}, state}, fn order_id, {result, current_state} ->
        {permit_id, next_state} = ensure_available_permit(current_state, order_id)
        {Map.put(result, order_id, permit_id), next_state}
      end)

    {:reply, permits, state}
  end

  def handle_call(
        {:execute_reprint, _order_id, _action, _permit_id, _staff_name},
        _from,
        %{recovery_required?: true} = state
      ) do
    {:reply, {:recovery_required, :coordinator_restarted}, state}
  end

  def handle_call(
        {:execute_reprint, order_id, action, permit_id, staff_name},
        _from,
        state
      ) do
    key = {order_id, @action}

    case claim_status(state, key, action, permit_id) do
      :claimable ->
        execute_claimed_reprint(state, key, order_id, permit_id, staff_name)

      {:duplicate, result} ->
        {:reply, {:duplicate, result}, state}

      :stale ->
        {:reply, {:stale, :invalid_permit}, state}
    end
  end

  def handle_call(:acknowledge_recovery, _from, state) do
    {:reply, :ok, %{state | recovery_required?: false, permits: %{}}}
  end

  defp execute_claimed_reprint(state, key, order_id, permit_id, staff_name) do
    state = put_in(state, [:permits, key, :state], :running)

    case eligible_order(order_id) do
      {:ok, order} ->
        result = state.dispatch_receipt.(order, staff_name: staff_name)
        complete_reprint(state, key, permit_id, result)

      {:error, reason} ->
        result = {:ineligible, reason}
        state = complete_without_next_permit(state, key, permit_id, result)
        {:reply, result, state}
    end
  end

  defp complete_reprint(state, key, permit_id, :dispatched) do
    {next_permit, state} = rotate_permit(state, key, permit_id, :dispatched)
    {:reply, {:dispatched, next_permit}, state}
  end

  defp complete_reprint(state, key, permit_id, {:definite_failure, reason}) do
    result = {:definite_failure, reason}
    {retry_permit, state} = rotate_permit(state, key, permit_id, result)
    {:reply, {:definite_failure, reason, retry_permit}, state}
  end

  defp complete_reprint(state, key, permit_id, {:uncertain, reason}) do
    result = {:uncertain, reason}
    state = complete_without_next_permit(state, key, permit_id, result)
    {:reply, result, state}
  end

  defp complete_reprint(state, key, permit_id, :disabled) do
    result = {:ineligible, :printer_disabled}
    state = complete_without_next_permit(state, key, permit_id, result)
    {:reply, result, state}
  end

  defp eligible_order(order_id) do
    case Repo.get(Order, order_id) do
      nil ->
        {:error, :order_not_found}

      %Order{payment_status: "paid", status: status} = order
      when status in @eligible_statuses ->
        if Printer.enabled?() do
          {:ok, Repo.preload(order, :items)}
        else
          {:error, :printer_disabled}
        end

      %Order{payment_status: payment_status} when payment_status != "paid" ->
        {:error, :order_not_paid}

      %Order{} ->
        {:error, :order_not_eligible}
    end
  end

  defp claim_status(_state, _key, action, _permit_id) when action != @action, do: :stale

  defp claim_status(state, key, @action, permit_id) do
    case Map.get(state.permits, key) do
      %{current: ^permit_id, state: :available} ->
        :claimable

      %{last: ^permit_id, last_result: result} ->
        {:duplicate, result}

      _ ->
        :stale
    end
  end

  defp ensure_available_permit(state, order_id) do
    key = {order_id, @action}

    case Map.get(state.permits, key) do
      %{current: permit_id, state: :available} when is_binary(permit_id) ->
        {permit_id, state}

      nil ->
        permit_id = new_permit_id()
        entry = %{current: permit_id, state: :available, last: nil, last_result: nil}
        {permit_id, put_in(state, [:permits, key], entry)}

      %{current: nil, state: :uncertain} ->
        {nil, state}

      %{current: nil} = entry ->
        permit_id = new_permit_id()
        entry = %{entry | current: permit_id, state: :available}
        {permit_id, put_in(state, [:permits, key], entry)}
    end
  end

  defp rotate_permit(state, key, used_permit, result) do
    next_permit = new_permit_id()

    entry = %{
      current: next_permit,
      state: :available,
      last: used_permit,
      last_result: result
    }

    {next_permit, put_in(state, [:permits, key], entry)}
  end

  defp complete_without_next_permit(state, key, used_permit, result) do
    entry = %{current: nil, state: result_state(result), last: used_permit, last_result: result}
    put_in(state, [:permits, key], entry)
  end

  defp result_state({:uncertain, _}), do: :uncertain
  defp result_state({:ineligible, _}), do: :ineligible

  defp new_permit_id do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end

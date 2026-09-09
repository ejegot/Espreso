defmodule Espreso.PhysicalActionCoordinator do
  @moduledoc """
  Single-node coordinator for protected physical printer actions.

  Reprint permits are shared across LiveViews and consumed before printer I/O.
  """

  use GenServer

  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Printer
  alias Espreso.Repo

  @actions [:receipt_reprint, :kitchen, :drawer, :mark_paid]
  @eligible_statuses ~w(received preparing ready)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def permits(action, order_ids, server \\ __MODULE__)
      when action in @actions and is_list(order_ids) do
    GenServer.call(server, {:permits, action, order_ids})
  end

  def reprint_permits(order_ids, server \\ __MODULE__) when is_list(order_ids) do
    permits(:receipt_reprint, order_ids, server)
  end

  def execute(order_id, action, permit_id, opts \\ [])

  def execute(order_id, action, permit_id, opts) when is_binary(order_id) do
    case Integer.parse(order_id) do
      {parsed_id, ""} -> execute(parsed_id, action, permit_id, opts)
      _ -> {:stale, :invalid_order_id}
    end
  end

  def execute(order_id, action, permit_id, opts) when is_integer(order_id) do
    server = Keyword.get(opts, :server, __MODULE__)
    staff_name = Keyword.get(opts, :staff_name)

    GenServer.call(server, {:execute, order_id, action, permit_id, staff_name}, :infinity)
  end

  def execute_reprint(order_id, action, permit_id, opts \\ []) do
    execute(order_id, action, permit_id, opts)
  end

  def execute_mark_paid(order_id, permit_id, paid_via, opts \\ [])

  def execute_mark_paid(order_id, permit_id, paid_via, opts) when is_binary(order_id) do
    case Integer.parse(order_id) do
      {parsed_id, ""} -> execute_mark_paid(parsed_id, permit_id, paid_via, opts)
      _ -> {:stale, :invalid_order_id}
    end
  end

  def execute_mark_paid(order_id, permit_id, paid_via, opts)
      when is_integer(order_id) and is_binary(paid_via) do
    server = Keyword.get(opts, :server, __MODULE__)
    staff_name = Keyword.get(opts, :staff_name)

    settlement_opts =
      Keyword.take(opts, [:settled_by_user_id, :settlement_source, :cash_tendered])

    GenServer.call(
      server,
      {:execute_mark_paid, order_id, permit_id, paid_via, staff_name, settlement_opts},
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
       dispatchers: %{
         receipt_reprint: Keyword.get(opts, :dispatch_receipt, &Printer.dispatch_receipt/2),
         kitchen: Keyword.get(opts, :dispatch_kitchen, &Printer.dispatch_kitchen/2),
         drawer:
           Keyword.get(opts, :dispatch_drawer, fn _order, _opts ->
             Printer.dispatch_drawer()
           end)
       }
     }}
  end

  @impl true
  def handle_call(
        {:permits, _action, _order_ids},
        _from,
        %{recovery_required?: true} = state
      ) do
    {:reply, %{}, state}
  end

  def handle_call({:permits, action, order_ids}, _from, state) do
    {permits, state} =
      order_ids
      |> Enum.uniq()
      |> Enum.reduce({%{}, state}, fn order_id, {result, current_state} ->
        if mark_paid_conflict?(current_state, order_id, action) do
          {Map.put(result, order_id, nil), current_state}
        else
          {permit_id, next_state} = ensure_available_permit(current_state, order_id, action)
          {Map.put(result, order_id, permit_id), next_state}
        end
      end)

    {:reply, permits, state}
  end

  def handle_call(
        {:execute, _order_id, _action, _permit_id, _staff_name},
        _from,
        %{recovery_required?: true} = state
      ) do
    {:reply, {:recovery_required, :coordinator_restarted}, state}
  end

  def handle_call(
        {:execute_mark_paid, _order_id, _permit_id, _paid_via, _staff_name, _settlement_opts},
        _from,
        %{recovery_required?: true} = state
      ) do
    {:reply, {:recovery_required, :coordinator_restarted}, state}
  end

  def handle_call(
        {:execute, order_id, action, permit_id, staff_name},
        _from,
        state
      ) do
    if mark_paid_conflict?(state, order_id, action) do
      {:reply, {:stale, :mark_paid_recovery_pending}, state}
    else
      execute_claimed_physical_action(state, order_id, action, permit_id, staff_name)
    end
  end

  def handle_call(
        {:execute_mark_paid, order_id, permit_id, paid_via, staff_name, settlement_opts},
        _from,
        state
      ) do
    key = {order_id, :mark_paid}

    case claim_status(state, key, permit_id) do
      :claimable ->
        execute_claimed_mark_paid(
          state,
          key,
          order_id,
          permit_id,
          paid_via,
          staff_name,
          settlement_opts
        )

      {:duplicate, result} ->
        {:reply, {:duplicate, result}, state}

      :stale ->
        {:reply, {:stale, :invalid_permit}, state}
    end
  end

  def handle_call(:acknowledge_recovery, _from, state) do
    {:reply, :ok, %{state | recovery_required?: false, permits: %{}}}
  end

  defp execute_claimed_physical_action(state, order_id, action, permit_id, staff_name) do
    if action in @actions and action != :mark_paid do
      key = {order_id, action}

      case claim_status(state, key, permit_id) do
        :claimable ->
          execute_claimed_action(state, key, order_id, action, permit_id, staff_name)

        {:duplicate, result} ->
          {:reply, {:duplicate, result}, state}

        :stale ->
          {:reply, {:stale, :invalid_permit}, state}
      end
    else
      {:reply, {:stale, :invalid_action}, state}
    end
  end

  defp execute_claimed_action(state, key, order_id, action, permit_id, staff_name) do
    state = put_in(state, [:permits, key, :state], :running)

    case eligible_order(order_id, action) do
      {:ok, order} ->
        result = state.dispatchers[action].(order, staff_name: staff_name)
        complete_action(state, key, permit_id, result)

      {:error, reason} ->
        result = {:ineligible, reason}
        state = complete_without_next_permit(state, key, permit_id, result)
        {:reply, result, state}
    end
  end

  defp execute_claimed_mark_paid(
         state,
         key,
         order_id,
         permit_id,
         paid_via,
         staff_name,
         settlement_opts
       ) do
    entry = Map.fetch!(state.permits, key)
    state = put_in(state, [:permits, key, :state], :running)

    case Map.get(entry, :phase, :transition) do
      :transition ->
        transition_and_dispatch(
          state,
          key,
          order_id,
          permit_id,
          paid_via,
          staff_name,
          settlement_opts
        )

      :receipt ->
        retry_mark_paid_receipt(state, key, order_id, permit_id, entry, staff_name)

      :drawer ->
        retry_mark_paid_drawer(state, key, order_id, permit_id, entry, staff_name)
    end
  end

  defp transition_and_dispatch(
         state,
         key,
         order_id,
         permit_id,
         paid_via,
         staff_name,
         settlement_opts
       ) do
    mark_paid_opts = [paid_via: paid_via] ++ settlement_opts

    case Orders.mark_paid_with_transition(%Order{id: order_id}, mark_paid_opts) do
      {:ok, :transitioned, order} ->
        order = Repo.preload(order, :items)

        dispatch_mark_paid_receipt(
          state,
          key,
          permit_id,
          order,
          order.paid_via || paid_via,
          staff_name,
          :transitioned
        )

      {:ok, :already_paid, order} ->
        result = {:ok, :already_paid, order}
        state = complete_mark_paid(state, key, permit_id, result)
        {:reply, result, state}

      {:error, reason} ->
        result = {:ineligible, reason}

        state =
          if recoverable_payment_settlement_error?(reason) do
            rotate_rejected_mark_paid_permit(state, key, permit_id, result)
          else
            complete_mark_paid(state, key, permit_id, result)
          end

        {:reply, result, state}
    end
  end

  defp retry_mark_paid_receipt(state, key, order_id, permit_id, entry, staff_name) do
    case paid_order_with_items(order_id) do
      {:ok, order} ->
        dispatch_mark_paid_receipt(
          state,
          key,
          permit_id,
          order,
          entry.paid_via,
          staff_name,
          :recovery
        )

      {:error, reason} ->
        result = {:ineligible, reason}
        state = complete_mark_paid(state, key, permit_id, result)
        {:reply, result, state}
    end
  end

  defp retry_mark_paid_drawer(state, key, order_id, permit_id, entry, staff_name) do
    case paid_cash_order(order_id, entry.paid_via) do
      {:ok, order} ->
        dispatch_mark_paid_drawer(
          state,
          key,
          permit_id,
          order,
          entry.paid_via,
          staff_name,
          :recovery,
          :drawer
        )

      {:error, reason} ->
        result = {:ineligible, reason}
        state = complete_mark_paid(state, key, permit_id, result)
        {:reply, result, state}
    end
  end

  defp dispatch_mark_paid_receipt(
         state,
         key,
         permit_id,
         order,
         paid_via,
         staff_name,
         operation
       ) do
    case state.dispatchers.receipt_reprint.(order, staff_name: staff_name) do
      :dispatched when paid_via in ["cash", "counter"] ->
        dispatch_mark_paid_drawer(
          state,
          key,
          permit_id,
          order,
          paid_via,
          staff_name,
          operation
        )

      :dispatched ->
        finish_mark_paid(
          state,
          key,
          permit_id,
          operation,
          order,
          {:dispatched, :receipt}
        )

      {:definite_failure, reason} ->
        retry_mark_paid_phase(
          state,
          key,
          permit_id,
          order,
          paid_via,
          operation,
          :receipt,
          reason
        )

      {:uncertain, reason} ->
        uncertain_mark_paid_phase(
          state,
          key,
          permit_id,
          order,
          paid_via,
          operation,
          :receipt,
          reason
        )

      :disabled ->
        retry_mark_paid_phase(
          state,
          key,
          permit_id,
          order,
          paid_via,
          operation,
          :receipt,
          :printer_disabled
        )
    end
  end

  defp dispatch_mark_paid_drawer(
         state,
         key,
         permit_id,
         order,
         paid_via,
         staff_name,
         operation,
         success_phase \\ :receipt_and_drawer
       ) do
    case state.dispatchers.drawer.(order, staff_name: staff_name) do
      :dispatched ->
        finish_mark_paid(
          state,
          key,
          permit_id,
          operation,
          order,
          {:dispatched, success_phase}
        )

      {:definite_failure, reason} ->
        retry_mark_paid_phase(
          state,
          key,
          permit_id,
          order,
          paid_via,
          operation,
          :drawer,
          reason
        )

      {:uncertain, reason} ->
        uncertain_mark_paid_phase(
          state,
          key,
          permit_id,
          order,
          paid_via,
          operation,
          :drawer,
          reason
        )

      :disabled ->
        retry_mark_paid_phase(
          state,
          key,
          permit_id,
          order,
          paid_via,
          operation,
          :drawer,
          :printer_disabled
        )
    end
  end

  defp finish_mark_paid(state, key, permit_id, operation, order, physical_result) do
    result = {:ok, operation, order, physical_result}
    state = complete_mark_paid(state, key, permit_id, result)
    {:reply, result, state}
  end

  defp retry_mark_paid_phase(
         state,
         key,
         permit_id,
         order,
         paid_via,
         operation,
         phase,
         reason
       ) do
    next_permit = new_permit_id()
    physical_result = {:definite_failure, phase, reason, next_permit}
    result = {:ok, operation, order, physical_result}

    entry = %{
      current: next_permit,
      state: :available,
      phase: phase,
      paid_via: paid_via,
      last: permit_id,
      last_result: result
    }

    {:reply, result, put_in(state, [:permits, key], entry)}
  end

  defp uncertain_mark_paid_phase(
         state,
         key,
         permit_id,
         order,
         paid_via,
         operation,
         phase,
         reason
       ) do
    physical_result = {:uncertain, phase, reason}
    result = {:ok, operation, order, physical_result}

    entry = %{
      current: nil,
      state: :uncertain,
      phase: phase,
      paid_via: paid_via,
      last: permit_id,
      last_result: result
    }

    {:reply, result, put_in(state, [:permits, key], entry)}
  end

  defp complete_mark_paid(state, key, permit_id, result) do
    entry = %{
      current: nil,
      state: :complete,
      phase: nil,
      paid_via: nil,
      last: permit_id,
      last_result: result
    }

    put_in(state, [:permits, key], entry)
  end

  defp rotate_rejected_mark_paid_permit(state, key, permit_id, result) do
    entry = %{
      current: new_permit_id(),
      state: :available,
      phase: :transition,
      paid_via: nil,
      last: permit_id,
      last_result: result
    }

    put_in(state, [:permits, key], entry)
  end

  defp recoverable_payment_settlement_error?(:invalid_paid_via), do: true
  defp recoverable_payment_settlement_error?(:paymongo_authority_required), do: true
  defp recoverable_payment_settlement_error?(:payment_channel_mismatch), do: true
  defp recoverable_payment_settlement_error?(:invalid_settlement_source), do: true
  defp recoverable_payment_settlement_error?(:invalid_settled_by_user), do: true
  defp recoverable_payment_settlement_error?(:invalid_cash_tendered), do: true
  defp recoverable_payment_settlement_error?(:cash_tender_too_low), do: true
  defp recoverable_payment_settlement_error?(:cash_metadata_not_applicable), do: true

  defp recoverable_payment_settlement_error?({
         :payment_intent_mismatch,
         _payment_intent,
         _paid_via
       }),
       do: true

  defp recoverable_payment_settlement_error?(_reason), do: false

  defp complete_action(state, key, permit_id, :dispatched) do
    {next_permit, state} = rotate_permit(state, key, permit_id, :dispatched)
    {:reply, {:dispatched, next_permit}, state}
  end

  defp complete_action(state, key, permit_id, {:definite_failure, reason}) do
    result = {:definite_failure, reason}
    {retry_permit, state} = rotate_permit(state, key, permit_id, result)
    {:reply, {:definite_failure, reason, retry_permit}, state}
  end

  defp complete_action(state, key, permit_id, {:uncertain, reason}) do
    result = {:uncertain, reason}
    state = complete_without_next_permit(state, key, permit_id, result)
    {:reply, result, state}
  end

  defp complete_action(state, key, permit_id, :disabled) do
    result = {:ineligible, :printer_disabled}
    state = complete_without_next_permit(state, key, permit_id, result)
    {:reply, result, state}
  end

  defp eligible_order(order_id, action) do
    case Repo.get(Order, order_id) do
      nil ->
        {:error, :order_not_found}

      %Order{} = order ->
        validate_eligible_order(order, action)
    end
  end

  defp validate_eligible_order(%Order{} = order, :receipt_reprint) do
    cond do
      order.payment_status != "paid" -> {:error, :order_not_paid}
      order.status not in @eligible_statuses -> {:error, :order_not_eligible}
      not Printer.enabled?() -> {:error, :printer_disabled}
      true -> {:ok, Repo.preload(order, :items)}
    end
  end

  defp validate_eligible_order(%Order{} = order, :kitchen) do
    cond do
      order.status not in @eligible_statuses -> {:error, :order_not_eligible}
      not Printer.enabled?() -> {:error, :printer_disabled}
      true -> {:ok, Repo.preload(order, :items)}
    end
  end

  defp validate_eligible_order(%Order{} = order, :drawer) do
    cond do
      order.payment_status != "paid" ->
        {:error, :order_not_paid}

      not Printer.cash_like?(order.paid_via || "counter") ->
        {:error, :payment_not_cash_like}

      order.status not in @eligible_statuses ->
        {:error, :order_not_eligible}

      not Printer.enabled?() ->
        {:error, :printer_disabled}

      true ->
        {:ok, order}
    end
  end

  defp paid_order_with_items(order_id) do
    case Repo.get(Order, order_id) do
      nil -> {:error, :order_not_found}
      %Order{payment_status: "paid"} = order -> {:ok, Repo.preload(order, :items)}
      %Order{} -> {:error, :order_not_paid}
    end
  end

  defp paid_cash_order(order_id, paid_via) do
    case Repo.get(Order, order_id) do
      nil ->
        {:error, :order_not_found}

      %Order{payment_status: status} when status != "paid" ->
        {:error, :order_not_paid}

      %Order{} = order ->
        if Printer.cash_like?(paid_via), do: {:ok, order}, else: {:error, :payment_not_cash_like}
    end
  end

  defp claim_status(state, key, permit_id) do
    case Map.get(state.permits, key) do
      %{current: ^permit_id, state: :available} ->
        :claimable

      %{last: ^permit_id, last_result: result} ->
        {:duplicate, result}

      _ ->
        :stale
    end
  end

  defp mark_paid_conflict?(state, order_id, action)
       when action in [:receipt_reprint, :drawer] do
    case Map.get(state.permits, {order_id, :mark_paid}) do
      %{state: mark_state, phase: :receipt}
      when mark_state in [:available, :running, :uncertain] ->
        action == :receipt_reprint or
          (action == :drawer and
             Printer.cash_like?(state.permits[{order_id, :mark_paid}].paid_via || "counter"))

      %{state: mark_state, phase: :drawer}
      when mark_state in [:available, :running, :uncertain] ->
        action == :drawer

      _ ->
        false
    end
  end

  defp mark_paid_conflict?(_state, _order_id, _action), do: false

  defp ensure_available_permit(state, order_id, action) do
    key = {order_id, action}

    case Map.get(state.permits, key) do
      %{current: permit_id, state: :available} when is_binary(permit_id) ->
        {permit_id, state}

      nil ->
        permit_id = new_permit_id()

        entry = %{
          current: permit_id,
          state: :available,
          phase: initial_phase(action),
          paid_via: nil,
          last: nil,
          last_result: nil
        }

        {permit_id, put_in(state, [:permits, key], entry)}

      %{current: nil, state: :uncertain} ->
        {nil, state}

      %{current: nil, state: :complete} when action == :mark_paid ->
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

  defp initial_phase(:mark_paid), do: :transition
  defp initial_phase(_action), do: nil

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

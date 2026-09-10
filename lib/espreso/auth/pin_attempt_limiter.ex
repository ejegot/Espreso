defmodule Espreso.Auth.PinAttemptLimiter do
  @moduledoc """
  In-memory PIN authentication throttling.

  Primary: per-user failure counting and cooldown.
  Secondary: soft per-IP ceiling across users.

  Controllers extract the client IP and call this module **before**
  `Accounts.verify_pin/2`. This module has no Plug/Phoenix dependency.
  """

  use GenServer

  @user_failure_limit 5
  @user_window_ms :timer.minutes(15)
  @user_cooldowns_ms [60_000, 120_000, 300_000]

  @ip_failure_limit 30
  @ip_window_ms :timer.minutes(10)
  @ip_cooldowns_ms [60_000, 120_000]

  @cleanup_interval_ms :timer.minutes(5)
  @stale_grace_ms :timer.minutes(30)

  @type user_id :: integer() | String.t()
  @type ip :: String.t() | nil
  @type check_result :: :ok | {:error, :rate_limited}

  ## Public API

  @doc false
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns `:ok` when the attempt may proceed, or `{:error, :rate_limited}`.
  """
  @spec check(user_id(), ip(), keyword()) :: check_result()
  def check(user_id, ip, opts \\ []) do
    call(opts, {:check, normalize_user_id(user_id), normalize_ip(ip), now(opts)})
  end

  @doc """
  Records a failed PIN authentication attempt (after verification failed).
  """
  @spec record_failure(user_id(), ip(), keyword()) :: :ok
  def record_failure(user_id, ip, opts \\ []) do
    call(opts, {:record_failure, normalize_user_id(user_id), normalize_ip(ip), now(opts)})
  end

  @doc """
  Clears per-user throttle state after a successful PIN login.

  Does **not** wipe the IP failure window (soft spray protection).
  """
  @spec record_success(user_id(), ip(), keyword()) :: :ok
  def record_success(user_id, ip, opts \\ []) do
    call(opts, {:record_success, normalize_user_id(user_id), normalize_ip(ip), now(opts)})
  end

  @doc """
  Clears all limiter state. Intended for tests.
  """
  @spec reset!(keyword()) :: :ok
  def reset!(opts \\ []) do
    call(opts, :reset)
  end

  ## GenServer

  @impl true
  def init(_opts) do
    table = :ets.new(:pin_attempt_limiter, [:set, :private])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:check, user_id, ip, now}, _from, state) do
    maybe_expire_user(state.table, user_id, now)
    maybe_expire_ip(state.table, ip, now)

    result =
      cond do
        user_blocked?(state.table, user_id, now) -> {:error, :rate_limited}
        ip_blocked?(state.table, ip, now) -> {:error, :rate_limited}
        true -> :ok
      end

    {:reply, result, state}
  end

  def handle_call({:record_failure, user_id, ip, now}, _from, state) do
    maybe_expire_user(state.table, user_id, now)
    maybe_expire_ip(state.table, ip, now)

    record_user_failure(state.table, user_id, now)
    record_ip_failure(state.table, ip, now)

    {:reply, :ok, state}
  end

  def handle_call({:record_success, user_id, ip, now}, _from, state) do
    :ets.delete(state.table, {:user, user_id})
    # IP window intentionally retained — successful login must not erase spray budget.
    maybe_expire_ip(state.table, ip, now)
    {:reply, :ok, state}
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_stale(state.table, System.system_time(:millisecond))
    schedule_cleanup()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Internals

  defp call(opts, message) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, message)
  end

  defp now(opts), do: Keyword.get(opts, :now, System.system_time(:millisecond))

  defp normalize_user_id(id) when is_integer(id), do: id

  defp normalize_user_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> id
    end
  end

  defp normalize_user_id(id), do: id

  defp normalize_ip(nil), do: "unknown"
  defp normalize_ip(""), do: "unknown"
  defp normalize_ip(ip) when is_binary(ip), do: ip

  defp normalize_ip(ip) when is_tuple(ip) do
    ip |> :inet.ntoa() |> to_string()
  end

  defp normalize_ip(_), do: "unknown"

  defp user_blocked?(table, user_id, now) do
    case :ets.lookup(table, {:user, user_id}) do
      [{_, %{cooldown_until: until}}] when is_integer(until) and now < until -> true
      _ -> false
    end
  end

  defp ip_blocked?(table, ip, now) do
    case :ets.lookup(table, {:ip, ip}) do
      [{_, %{cooldown_until: until}}] when is_integer(until) and now < until -> true
      _ -> false
    end
  end

  defp maybe_expire_user(table, user_id, now) do
    case :ets.lookup(table, {:user, user_id}) do
      [{key, state}] ->
        state = prune_user_state(state, now)

        if empty_user_state?(state) do
          :ets.delete(table, key)
        else
          :ets.insert(table, {key, state})
        end

      [] ->
        :ok
    end
  end

  defp maybe_expire_ip(_table, nil, _now), do: :ok

  defp maybe_expire_ip(table, ip, now) do
    case :ets.lookup(table, {:ip, ip}) do
      [{key, state}] ->
        state = prune_ip_state(state, now)

        if empty_ip_state?(state) do
          :ets.delete(table, key)
        else
          :ets.insert(table, {key, state})
        end

      [] ->
        :ok
    end
  end

  defp prune_user_state(state, now) do
    failures =
      state
      |> Map.get(:failures, [])
      |> Enum.filter(&(&1 > now - @user_window_ms))

    cooldown_until = Map.get(state, :cooldown_until, 0)
    escalation = Map.get(state, :escalation, 0)

    cooldown_until =
      if is_integer(cooldown_until) and now >= cooldown_until, do: 0, else: cooldown_until

    %{failures: failures, cooldown_until: cooldown_until, escalation: escalation}
  end

  defp prune_ip_state(state, now) do
    failures =
      state
      |> Map.get(:failures, [])
      |> Enum.filter(&(&1 > now - @ip_window_ms))

    cooldown_until = Map.get(state, :cooldown_until, 0)
    escalation = Map.get(state, :escalation, 0)

    cooldown_until =
      if is_integer(cooldown_until) and now >= cooldown_until, do: 0, else: cooldown_until

    %{failures: failures, cooldown_until: cooldown_until, escalation: escalation}
  end

  defp empty_user_state?(%{failures: [], cooldown_until: until, escalation: 0})
       when until in [0, nil],
       do: true

  defp empty_user_state?(%{failures: [], cooldown_until: until, escalation: esc})
       when until in [0, nil] and esc > 0,
       do: false

  defp empty_user_state?(_), do: false

  defp empty_ip_state?(%{failures: [], cooldown_until: until, escalation: esc})
       when until in [0, nil] and esc in [0, nil],
       do: true

  defp empty_ip_state?(_), do: false

  defp record_user_failure(table, user_id, now) do
    state =
      case :ets.lookup(table, {:user, user_id}) do
        [{_, existing}] -> prune_user_state(existing, now)
        [] -> %{failures: [], cooldown_until: 0, escalation: 0}
      end

    # Do not accumulate while already cooling down (blocked attempts never reach here
    # when controllers check first; keep defensive).
    if is_integer(state.cooldown_until) and now < state.cooldown_until do
      :ets.insert(table, {{:user, user_id}, state})
    else
      failures = state.failures ++ [now]
      escalation = state.escalation

      {failures, cooldown_until, escalation} =
        if length(failures) >= @user_failure_limit do
          duration = Enum.at(@user_cooldowns_ms, min(escalation, length(@user_cooldowns_ms) - 1))
          next_escalation = min(escalation + 1, length(@user_cooldowns_ms) - 1)
          {[], now + duration, next_escalation}
        else
          {failures, 0, escalation}
        end

      :ets.insert(
        table,
        {{:user, user_id},
         %{failures: failures, cooldown_until: cooldown_until, escalation: escalation}}
      )
    end
  end

  defp record_ip_failure(table, ip, now) do
    state =
      case :ets.lookup(table, {:ip, ip}) do
        [{_, existing}] -> prune_ip_state(existing, now)
        [] -> %{failures: [], cooldown_until: 0, escalation: 0}
      end

    if is_integer(state.cooldown_until) and now < state.cooldown_until do
      :ets.insert(table, {{:ip, ip}, state})
    else
      failures = state.failures ++ [now]
      escalation = state.escalation

      {failures, cooldown_until, escalation} =
        if length(failures) >= @ip_failure_limit do
          duration = Enum.at(@ip_cooldowns_ms, min(escalation, length(@ip_cooldowns_ms) - 1))
          next_escalation = min(escalation + 1, length(@ip_cooldowns_ms) - 1)
          {[], now + duration, next_escalation}
        else
          {failures, 0, escalation}
        end

      :ets.insert(
        table,
        {{:ip, ip}, %{failures: failures, cooldown_until: cooldown_until, escalation: escalation}}
      )
    end
  end

  defp cleanup_stale(table, now) do
    cutoff = now - @stale_grace_ms

    table
    |> :ets.tab2list()
    |> Enum.each(fn
      {{:user, _} = key, state} ->
        state = prune_user_state(state, now)

        cond do
          empty_user_state?(state) ->
            :ets.delete(table, key)

          state.cooldown_until in [0, nil] and state.failures == [] and
            state.escalation > 0 and last_activity(state) < cutoff ->
            # Drop long-idle escalation breadcrumbs.
            :ets.delete(table, key)

          true ->
            :ets.insert(table, {key, state})
        end

      {{:ip, _} = key, state} ->
        state = prune_ip_state(state, now)

        if empty_ip_state?(state) or
             (state.failures == [] and state.cooldown_until in [0, nil] and
                last_activity(state) < cutoff) do
          :ets.delete(table, key)
        else
          :ets.insert(table, {key, state})
        end

      _ ->
        :ok
    end)
  end

  defp last_activity(%{failures: [ts | _]}), do: ts
  defp last_activity(%{failures: []}), do: 0
  defp last_activity(_), do: 0

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end

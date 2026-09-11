defmodule Espreso.Loyalty.EarnReconciler do
  @moduledoc """
  Retries loyalty earning for paid customer orders that still lack an earn ledger row.

  Payment success never depends on this process. Pending work is derived durably as:
  `payment_status == paid` AND `customer_id` present AND no earn ledger entry.
  """

  use GenServer

  require Logger

  alias Espreso.Loyalty
  alias Espreso.Orders.Order
  alias Espreso.Repo

  @default_interval_ms 15_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Asks the reconciler to attempt earn for a specific paid order soon.
  """
  def nudge(order_id, server \\ __MODULE__) when is_integer(order_id) do
    GenServer.cast(server, {:nudge, order_id})
  end

  @doc """
  Synchronously reconciles pending earns (used by tests / manual recovery).
  """
  def reconcile_now(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, {:reconcile_now, opts})
  end

  @impl true
  def init(opts) do
    interval = interval_ms(opts)
    state = %{interval_ms: interval}
    if is_integer(interval), do: schedule_tick(interval)
    {:ok, state}
  end

  @impl true
  def handle_cast({:nudge, order_id}, state) do
    _ = attempt_order(order_id)
    {:noreply, state}
  end

  @impl true
  def handle_call({:reconcile_now, opts}, _from, state) do
    {:reply, reconcile_pending(opts), state}
  end

  @impl true
  def handle_info(:tick, %{interval_ms: interval} = state) do
    _ = reconcile_pending([])
    if is_integer(interval), do: schedule_tick(interval)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp reconcile_pending(opts) do
    limit = Keyword.get(opts, :limit, 50)

    results =
      Loyalty.list_pending_earn_orders(limit: limit)
      |> Enum.map(fn order ->
        {order.id, Loyalty.ensure_earn_for_paid_order(order)}
      end)

    failed =
      Enum.count(results, fn
        {_id, {:error, _}} -> true
        _ -> false
      end)

    if failed > 0 do
      Logger.warning("loyalty earn reconciler: #{failed} pending earn(s) still failing")
    end

    {:ok, results}
  end

  defp attempt_order(order_id) do
    case Repo.get(Order, order_id) do
      %Order{} = order ->
        case Loyalty.ensure_earn_for_paid_order(order) do
          {:ok, _} = ok ->
            ok

          {:error, reason} = error ->
            Logger.warning(
              "loyalty earn nudge failed order_id=#{order_id} reason=#{inspect(reason)}"
            )

            error
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp schedule_tick(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :tick, interval_ms)
  end

  defp interval_ms(opts) do
    conf = Application.get_env(:espreso, __MODULE__, [])

    cond do
      Keyword.has_key?(opts, :interval_ms) -> Keyword.get(opts, :interval_ms)
      Keyword.get(conf, :enabled, true) == false -> :disabled
      true -> Keyword.get(conf, :interval_ms, @default_interval_ms)
    end
  end
end

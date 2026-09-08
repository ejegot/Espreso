defmodule Espreso.PhysicalActionCoordinatorTest do
  use Espreso.DataCase

  alias Espreso.Orders
  alias Espreso.PhysicalActionCoordinator

  @server __MODULE__.Coordinator

  setup do
    previous = Application.get_env(:espreso, Espreso.Printer)

    Application.put_env(
      :espreso,
      Espreso.Printer,
      enabled: true,
      host: "127.0.0.1",
      port: 1,
      timeout_ms: 50
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:espreso, Espreso.Printer, previous)
      else
        Application.delete_env(:espreso, Espreso.Printer)
      end
    end)

    :ok
  end

  test "one permit executes once; duplicate, stale, wrong action, and wrong order are rejected" do
    parent = self()

    start_coordinator(fn order, _opts ->
      send(parent, {:dispatched, order.id})
      :dispatched
    end)

    order = paid_order!()

    permit =
      PhysicalActionCoordinator.reprint_permits([order.id], @server)
      |> Map.fetch!(order.id)

    assert {:dispatched, next_permit} =
             PhysicalActionCoordinator.execute_reprint(
               order.id,
               :receipt_reprint,
               permit,
               server: @server
             )

    assert is_binary(next_permit)
    refute next_permit == permit
    assert_receive {:dispatched, order_id}
    assert order_id == order.id

    assert {:duplicate, :dispatched} =
             PhysicalActionCoordinator.execute_reprint(
               order.id,
               :receipt_reprint,
               permit,
               server: @server
             )

    assert {:stale, :invalid_permit} =
             PhysicalActionCoordinator.execute_reprint(
               order.id,
               :kitchen,
               next_permit,
               server: @server
             )

    assert {:stale, :invalid_permit} =
             PhysicalActionCoordinator.execute_reprint(
               order.id + 1,
               :receipt_reprint,
               next_permit,
               server: @server
             )

    assert {:stale, :invalid_permit} =
             PhysicalActionCoordinator.execute_reprint(
               order.id,
               :receipt_reprint,
               "unknown",
               server: @server
             )

    refute_receive {:dispatched, _}
  end

  test "concurrent claims of one permit execute exactly one receipt" do
    parent = self()

    start_coordinator(fn order, _opts ->
      send(parent, {:dispatched, order.id})
      Process.sleep(50)
      :dispatched
    end)

    order = paid_order!()

    permit =
      PhysicalActionCoordinator.reprint_permits([order.id], @server)
      |> Map.fetch!(order.id)

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.async(fn ->
          PhysicalActionCoordinator.execute_reprint(
            order.id,
            :receipt_reprint,
            permit,
            server: @server
          )
        end)
      end)
      |> Task.await_many()

    assert Enum.count(results, &match?({:dispatched, _}, &1)) == 1
    assert Enum.count(results, &match?({:duplicate, :dispatched}, &1)) == 1
    assert_receive {:dispatched, order_id}
    assert order_id == order.id
    refute_receive {:dispatched, _}
  end

  test "definite failure rotates the permit while uncertain outcome blocks automatic retry" do
    order = paid_order!()

    start_coordinator(fn _order, _opts -> {:definite_failure, :econnrefused} end)

    permit =
      PhysicalActionCoordinator.reprint_permits([order.id], @server)
      |> Map.fetch!(order.id)

    assert {:definite_failure, :econnrefused, retry_permit} =
             PhysicalActionCoordinator.execute_reprint(
               order.id,
               :receipt_reprint,
               permit,
               server: @server
             )

    assert is_binary(retry_permit)
    refute retry_permit == permit

    stop_supervised!(@server)

    start_coordinator(fn _order, _opts -> {:uncertain, :closed} end)
    :ok = PhysicalActionCoordinator.acknowledge_recovery(@server)

    uncertain_permit =
      PhysicalActionCoordinator.reprint_permits([order.id], @server)
      |> Map.fetch!(order.id)

    assert {:uncertain, :closed} =
             PhysicalActionCoordinator.execute_reprint(
               order.id,
               :receipt_reprint,
               uncertain_permit,
               server: @server
             )

    assert PhysicalActionCoordinator.reprint_permits([order.id], @server) == %{
             order.id => nil
           }
  end

  test "coordinator restart invalidates permits and requires acknowledgement" do
    order = paid_order!()
    start_coordinator(fn _order, _opts -> :dispatched end)

    permit =
      PhysicalActionCoordinator.reprint_permits([order.id], @server)
      |> Map.fetch!(order.id)

    stop_supervised!(@server)
    start_coordinator(fn _order, _opts -> :dispatched end, acknowledge?: false)

    assert {:recovery_required, :coordinator_restarted} =
             PhysicalActionCoordinator.execute_reprint(
               order.id,
               :receipt_reprint,
               permit,
               server: @server
             )

    assert PhysicalActionCoordinator.reprint_permits([order.id], @server) == %{}
    assert :ok = PhysicalActionCoordinator.acknowledge_recovery(@server)

    fresh_permit =
      PhysicalActionCoordinator.reprint_permits([order.id], @server)
      |> Map.fetch!(order.id)

    refute fresh_permit == permit
  end

  defp start_coordinator(dispatch_receipt, opts \\ []) do
    start_supervised!(
      {PhysicalActionCoordinator, name: @server, dispatch_receipt: dispatch_receipt},
      id: @server
    )

    if Keyword.get(opts, :acknowledge?, true) do
      PhysicalActionCoordinator.acknowledge_recovery(@server)
    end
  end

  defp paid_order! do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Permit", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, paid} = Orders.mark_paid(order, paid_via: "cash")
    paid
  end
end

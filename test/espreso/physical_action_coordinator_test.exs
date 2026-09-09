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

  test "Kitchen and Drawer permits are action-isolated, one-use, and independently rearmed" do
    parent = self()

    start_coordinator_with(
      dispatch_kitchen: fn order, _opts ->
        send(parent, {:kitchen, order.id})
        :dispatched
      end,
      dispatch_drawer: fn order, _opts ->
        send(parent, {:drawer, order.id})
        :dispatched
      end
    )

    order = paid_order!()
    kitchen_permit = permit_for(order.id, :kitchen)
    drawer_permit = permit_for(order.id, :drawer)
    reprint_permit = permit_for(order.id, :receipt_reprint)

    assert {:stale, :invalid_permit} =
             execute(order.id, :drawer, kitchen_permit)

    assert {:stale, :invalid_permit} =
             execute(order.id, :receipt_reprint, kitchen_permit)

    assert {:stale, :invalid_permit} =
             execute(order.id, :kitchen, drawer_permit)

    assert {:stale, :invalid_permit} =
             execute(order.id, :receipt_reprint, drawer_permit)

    assert {:stale, :invalid_permit} =
             execute(order.id, :kitchen, reprint_permit)

    assert {:stale, :invalid_permit} =
             execute(order.id, :drawer, reprint_permit)

    assert {:stale, :invalid_permit} =
             execute(order.id + 1, :kitchen, kitchen_permit)

    assert {:stale, :invalid_permit} =
             execute(order.id + 1, :drawer, drawer_permit)

    assert {:stale, :invalid_permit} =
             execute(order.id, :kitchen, "unknown")

    assert {:stale, :invalid_permit} =
             execute(order.id, :drawer, "unknown")

    assert {:dispatched, next_kitchen} = execute(order.id, :kitchen, kitchen_permit)
    assert_receive {:kitchen, order_id}
    assert order_id == order.id

    assert {:duplicate, :dispatched} = execute(order.id, :kitchen, kitchen_permit)
    refute_receive {:kitchen, _}

    assert {:dispatched, next_drawer} = execute(order.id, :drawer, drawer_permit)
    assert_receive {:drawer, order_id}
    assert order_id == order.id

    assert {:duplicate, :dispatched} = execute(order.id, :drawer, drawer_permit)
    refute_receive {:drawer, _}

    refute next_kitchen == kitchen_permit
    refute next_drawer == drawer_permit
    assert permit_for(order.id, :kitchen) == next_kitchen
    assert permit_for(order.id, :drawer) == next_drawer

    assert {:dispatched, later_kitchen} = execute(order.id, :kitchen, next_kitchen)
    assert_receive {:kitchen, ^order_id}
    refute later_kitchen == next_kitchen

    assert {:dispatched, later_drawer} = execute(order.id, :drawer, next_drawer)
    assert_receive {:drawer, ^order_id}
    refute later_drawer == next_drawer
  end

  test "concurrent Kitchen and Drawer claims each dispatch once and all actions serialize" do
    parent = self()

    start_coordinator_with(
      dispatch_kitchen: fn order, _opts ->
        send(parent, {:started, :kitchen, order.id})
        Process.sleep(75)
        send(parent, {:finished, :kitchen, order.id})
        :dispatched
      end,
      dispatch_drawer: fn order, _opts ->
        send(parent, {:started, :drawer, order.id})
        :dispatched
      end
    )

    order = paid_order!()
    kitchen_permit = permit_for(order.id, :kitchen)
    drawer_permit = permit_for(order.id, :drawer)

    kitchen_tasks =
      Enum.map(1..2, fn _ ->
        Task.async(fn -> execute(order.id, :kitchen, kitchen_permit) end)
      end)

    assert_receive {:started, :kitchen, order_id}
    assert order_id == order.id

    drawer_tasks =
      Enum.map(1..2, fn _ ->
        Task.async(fn -> execute(order.id, :drawer, drawer_permit) end)
      end)

    refute_receive {:started, :drawer, _}, 25
    assert_receive {:finished, :kitchen, ^order_id}

    kitchen_results = Task.await_many(kitchen_tasks)
    drawer_results = Task.await_many(drawer_tasks)

    assert Enum.count(kitchen_results, &match?({:dispatched, _}, &1)) == 1
    assert Enum.count(kitchen_results, &match?({:duplicate, :dispatched}, &1)) == 1
    assert Enum.count(drawer_results, &match?({:dispatched, _}, &1)) == 1
    assert Enum.count(drawer_results, &match?({:duplicate, :dispatched}, &1)) == 1
    assert_receive {:started, :drawer, ^order_id}
    refute_receive {:started, _, _}
  end

  test "Kitchen and Drawer definite failures rotate permits and uncertain outcomes lock actions" do
    start_coordinator_with(
      dispatch_kitchen: fn _order, _opts -> {:definite_failure, :econnrefused} end,
      dispatch_drawer: fn _order, _opts -> {:uncertain, :closed} end
    )

    order = paid_order!()
    kitchen_permit = permit_for(order.id, :kitchen)
    drawer_permit = permit_for(order.id, :drawer)

    assert {:definite_failure, :econnrefused, kitchen_retry} =
             execute(order.id, :kitchen, kitchen_permit)

    refute kitchen_retry == kitchen_permit
    assert permit_for(order.id, :kitchen) == kitchen_retry

    assert {:duplicate, {:definite_failure, :econnrefused}} =
             execute(order.id, :kitchen, kitchen_permit)

    assert {:uncertain, :closed} = execute(order.id, :drawer, drawer_permit)

    assert PhysicalActionCoordinator.permits(:drawer, [order.id], @server) == %{
             order.id => nil
           }

    assert {:duplicate, {:uncertain, :closed}} =
             execute(order.id, :drawer, drawer_permit)
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

    permit = permit_for(order.id, :receipt_reprint)
    kitchen_permit = permit_for(order.id, :kitchen)
    drawer_permit = permit_for(order.id, :drawer)

    stop_supervised!(@server)
    start_coordinator(fn _order, _opts -> :dispatched end, acknowledge?: false)

    assert {:recovery_required, :coordinator_restarted} =
             PhysicalActionCoordinator.execute_reprint(
               order.id,
               :receipt_reprint,
               permit,
               server: @server
             )

    assert {:recovery_required, :coordinator_restarted} =
             execute(order.id, :kitchen, kitchen_permit)

    assert {:recovery_required, :coordinator_restarted} =
             execute(order.id, :drawer, drawer_permit)

    assert PhysicalActionCoordinator.reprint_permits([order.id], @server) == %{}
    assert PhysicalActionCoordinator.permits(:kitchen, [order.id], @server) == %{}
    assert PhysicalActionCoordinator.permits(:drawer, [order.id], @server) == %{}
    assert :ok = PhysicalActionCoordinator.acknowledge_recovery(@server)

    fresh_permit =
      PhysicalActionCoordinator.reprint_permits([order.id], @server)
      |> Map.fetch!(order.id)

    refute fresh_permit == permit
  end

  defp start_coordinator(dispatch_receipt, opts \\ []) do
    start_coordinator_with([dispatch_receipt: dispatch_receipt], opts)
  end

  defp start_coordinator_with(dispatch_opts, opts \\ []) do
    start_supervised!({PhysicalActionCoordinator, [name: @server] ++ dispatch_opts}, id: @server)

    if Keyword.get(opts, :acknowledge?, true) do
      PhysicalActionCoordinator.acknowledge_recovery(@server)
    end
  end

  defp permit_for(order_id, action) do
    PhysicalActionCoordinator.permits(action, [order_id], @server)
    |> Map.fetch!(order_id)
  end

  defp execute(order_id, action, permit) do
    PhysicalActionCoordinator.execute(order_id, action, permit, server: @server)
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

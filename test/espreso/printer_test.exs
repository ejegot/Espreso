defmodule Espreso.PrinterTest do
  use ExUnit.Case, async: false

  alias Espreso.Orders.Order
  alias Espreso.Orders.OrderItem
  alias Espreso.Printer
  alias Espreso.Printer.Receipt

  test "disabled by default in test config" do
    refute Printer.enabled?()
    assert Printer.after_paid(%Order{number: "CS-TEST"}, "cash") == :disabled
  end

  test "cash_like?/1" do
    assert Printer.cash_like?("cash")
    assert Printer.cash_like?("counter")
    refute Printer.cash_like?("gcash")
    refute Printer.cash_like?("maya")
  end

  test "receipt includes order number, items, and total" do
    order = %Order{
      number: "CS-ABC123",
      customer_name: "Walk-in",
      fulfillment: "pickup",
      paid_via: "cash",
      total: Decimal.new("170"),
      inserted_at: ~N[2026-09-05 12:00:00],
      items: [
        %OrderItem{
          name: "Americano",
          size: "12oz",
          quantity: 1,
          unit_price: Decimal.new("95"),
          line_total: Decimal.new("95")
        },
        %OrderItem{
          name: "Espresso",
          size: nil,
          quantity: 1,
          unit_price: Decimal.new("75"),
          line_total: Decimal.new("75")
        }
      ]
    }

    receipt = Receipt.build(order, staff_name: "Jun")

    assert receipt =~ "CS-ABC123"
    assert receipt =~ "Americano"
    assert receipt =~ "Espresso"
    assert receipt =~ "Walk-in"
    assert receipt =~ "TOTAL"
    assert receipt =~ "P95.00"
    assert receipt =~ "P170.00"
    assert receipt =~ "Employee: Jun"
    assert receipt =~ "84 Lilac St., Marikina City"
    assert receipt =~ "CoffeeSpot_Guest"
    assert receipt =~ "SPOT3333"
    assert receipt =~ "2 Hours"
    refute receipt =~ "₱"
    refute receipt =~ "?"
  end

  test "kitchen ticket is compact with items and notes" do
    order = %Order{
      number: "CS-KIT001",
      customer_name: "Jay",
      fulfillment: "dine_in",
      table_number: "5",
      notes: "Less ice",
      items: [
        %OrderItem{name: "Scarlet Berry", size: "16oz", quantity: 2}
      ]
    }

    ticket = Receipt.build_kitchen(order, staff_name: "Ana")

    assert ticket =~ "KITCHEN"
    assert ticket =~ "CS-KIT001"
    assert ticket =~ "Dine in - Table 5"
    assert ticket =~ "2x Scarlet Berry 16oz"
    assert ticket =~ "NOTE"
    assert ticket =~ "Less ice"
    assert ticket =~ "Cashier: Ana"
    refute ticket =~ "TOTAL"
    refute ticket =~ "P120"
    refute ticket =~ "Wi-Fi"
  end

  test "dispatch_receipt reports dispatched and sends receipt bytes only" do
    restore_printer_config_on_exit()
    {port, printer_task} = start_test_printer!()
    set_test_printer_port(port)

    order = %Order{
      number: "CS-DISPATCH",
      paid_via: "cash",
      total: Decimal.new("75"),
      inserted_at: ~N[2026-09-05 12:00:00],
      items: [
        %OrderItem{
          name: "Espresso",
          quantity: 1,
          unit_price: Decimal.new("75"),
          line_total: Decimal.new("75")
        }
      ]
    }

    assert Printer.dispatch_receipt(order) == :dispatched
    receipt = Task.await(printer_task, 2_000)
    refute receipt == <<0x1B, 0x70, 0x00, 0x19, 0xFA>>
  end

  test "dispatch_receipt classifies connection failure as definite" do
    restore_printer_config_on_exit()
    set_test_printer_port(1)

    assert {:definite_failure, _reason} =
             Printer.dispatch_receipt(%Order{number: "CS-CONNECT", items: []})
  end

  test "dispatch_kitchen preserves the exact Kitchen payload and contains no drawer command" do
    restore_printer_config_on_exit()
    {port, printer_task} = start_test_printer!()
    set_test_printer_port(port)

    order = %Order{
      number: "CS-KITCHEN",
      customer_name: "Jay",
      fulfillment: "pickup",
      items: [%OrderItem{name: "Espresso", quantity: 1}]
    }

    expected = Receipt.build_kitchen(order, staff_name: "Ana")

    assert Printer.dispatch_kitchen(order, staff_name: "Ana") == :dispatched
    assert Task.await(printer_task, 2_000) == expected
    assert :binary.match(expected, <<0x1B, 0x70>>) == :nomatch
  end

  test "dispatch_drawer sends exactly one pin-2 drawer kick command" do
    restore_printer_config_on_exit()
    {port, printer_task} = start_test_printer!()
    set_test_printer_port(port)

    assert Printer.dispatch_drawer() == :dispatched
    assert Task.await(printer_task, 2_000) == <<0x1B, 0x70, 0x00, 0x19, 0xFA>>
  end

  test "Kitchen and Drawer dispatch classify connection failure as definite" do
    restore_printer_config_on_exit()
    set_test_printer_port(1)

    assert {:definite_failure, _reason} =
             Printer.dispatch_kitchen(%Order{number: "CS-KITCHEN-FAIL", items: []})

    assert {:definite_failure, _reason} = Printer.dispatch_drawer()
  end

  defp restore_printer_config_on_exit do
    previous = Application.get_env(:espreso, Printer)

    on_exit(fn ->
      if previous do
        Application.put_env(:espreso, Printer, previous)
      else
        Application.delete_env(:espreso, Printer)
      end
    end)
  end

  defp set_test_printer_port(port) do
    Application.put_env(
      :espreso,
      Printer,
      enabled: true,
      host: "127.0.0.1",
      port: port,
      timeout_ms: 1_000
    )
  end

  defp start_test_printer! do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_address, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 1_500)
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 1_500)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        bytes
      end)

    {port, task}
  end
end

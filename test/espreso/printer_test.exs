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

  test "native_client transport returns client_dispatch payloads without TCP" do
    restore_printer_config_on_exit()

    Application.put_env(:espreso, Printer,
      enabled: true,
      transport: :native_client,
      host: nil,
      port: 9100
    )

    assert Printer.enabled?()
    assert Printer.native_client?()

    order = %Order{
      number: "CS-CLIENT",
      paid_via: "cash",
      total: Decimal.new("75"),
      items: []
    }

    assert {:client_dispatch, receipt} = Printer.dispatch_receipt(order)
    assert is_binary(receipt)
    assert byte_size(receipt) > 0

    assert {:client_dispatch, drawer} = Printer.dispatch_drawer()
    assert drawer == Printer.drawer_bytes()
    assert :binary.match(drawer, <<0x1B, 0x70, 0x00, 0x19, 0xFA>>) != :nomatch
    assert :binary.match(drawer, <<0x1B, 0x70, 0x01, 0x19, 0xFA>>) != :nomatch

    assert Printer.after_paid(order, "cash") == {:error, :use_client_bridge}
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
      settled_at: ~U[2026-09-05 12:00:00Z],
      cash_tendered: Decimal.new("200"),
      change_due: Decimal.new("30"),
      items: [
        %OrderItem{
          name: "Americano",
          size: "12oz",
          category: "COLD",
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
    assert receipt =~ "Americano 12oz Iced"
    assert receipt =~ "Espresso"
    assert receipt =~ "Walk-in"
    assert receipt =~ "TOTAL"
    assert receipt =~ "P95.00"
    assert receipt =~ "P170.00"
    assert receipt =~ "Tendered"
    assert receipt =~ "P200.00"
    assert receipt =~ "Change"
    assert receipt =~ "P30.00"
    refute receipt =~ "Cash"
    assert receipt =~ "9/5/26 8:00 PM"
    assert receipt =~ "Employee: Jun"
    assert receipt =~ "84 Lilac St., Marikina City"
    assert :binary.match(receipt, <<0x1D, 0x76, 0x30, 0x00>>) != :nomatch
    assert receipt =~ "CoffeeSpot_Guest"
    assert receipt =~ "SPOT3333"
    assert receipt =~ "2 Hours"
    refute receipt =~ "₱"

    text_after_mark =
      case :binary.split(receipt, "LILAC, MARIKINA") do
        [_mark, rest] -> "LILAC, MARIKINA" <> rest
        [whole] -> whole
      end

    refute text_after_mark =~ "?"
  end

  test "receipt prints subtotal and discount then due total" do
    order = %Order{
      number: "CS-DISC01",
      customer_name: "Walk-in",
      fulfillment: "pickup",
      paid_via: "cash",
      total: Decimal.new("60"),
      discount_kind: "senior",
      discount_label: "Senior 20%",
      discount_amount: Decimal.new("15"),
      inserted_at: ~N[2026-09-05 12:00:00],
      settled_at: ~U[2026-09-05 12:00:00Z],
      items: [
        %OrderItem{
          name: "Espresso",
          size: nil,
          quantity: 1,
          unit_price: Decimal.new("75"),
          line_total: Decimal.new("75")
        }
      ]
    }

    receipt = Receipt.build(order)

    assert receipt =~ "SUBTOTAL"
    assert receipt =~ "P75.00"
    assert receipt =~ "DISCOUNT Senior 20%"
    assert receipt =~ "-P15.00"
    assert receipt =~ "TOTAL"
    assert receipt =~ "P60.00"
  end

  test "day report prints drawer expected counted and variance" do
    close = %Espreso.Shifts.ShiftClose{
      shop_date: ~D[2026-09-22],
      system_total: Decimal.new("215"),
      system_count: 2,
      counted_cash: Decimal.new("80"),
      opening_cash: Decimal.new("500"),
      expected_cash: Decimal.new("575"),
      variance: Decimal.new("-495"),
      closed_at: ~U[2026-09-22 10:00:00Z],
      by_via: %{"cash" => %{"total" => "75", "count" => 1}}
    }

    report = Receipt.build_day_report(close, staff_name: "Ana")

    assert report =~ "DAY REPORT"
    assert :binary.match(report, <<0x1D, 0x76, 0x30, 0x00>>) != :nomatch
    assert report =~ "Elilai Kafe"
    assert report =~ "CASH DRAWER"
    assert report =~ "Opening cash"
    assert report =~ "P500.00"
    assert report =~ "Cash sales"
    assert report =~ "P75.00"
    refute report =~ "Cash outs"
    assert report =~ "Expected"
    assert report =~ "P575.00"
    assert report =~ "Counted"
    assert report =~ "P80.00"
    assert report =~ "Short"
    assert report =~ "SALES"
    assert report =~ "Paid"
    refute report =~ "System paid"
    refute report =~ "Refunds"
    assert report =~ "Closed by Ana"
    refute report =~ "₱"
  end

  test "day report prints cash outs and refunds when they are not zero" do
    close = %Espreso.Shifts.ShiftClose{
      shop_date: ~D[2026-09-22],
      system_total: Decimal.new("215"),
      system_count: 2,
      counted_cash: Decimal.new("520"),
      opening_cash: Decimal.new("500"),
      expected_cash: Decimal.new("550"),
      variance: Decimal.new("-30"),
      closed_at: ~U[2026-09-22 10:00:00Z],
      by_via: %{
        "cash" => %{"total" => "100", "count" => 1},
        "gcash" => %{"total" => "115", "count" => 1}
      }
    }

    report = Receipt.build_day_report(close, staff_name: "Ana", refunds: Decimal.new("40"))

    assert report =~ "Cash outs"
    assert report =~ "P50.00"
    assert report =~ "Refunds"
    assert report =~ "P40.00"
    assert report =~ "GCash"
    assert report =~ "P115.00"
  end

  test "receipt prints cash and wallet split lines" do
    order = %Order{
      number: "CS-SPLIT1",
      customer_name: "Walk-in",
      fulfillment: "pickup",
      paid_via: "cash",
      total: Decimal.new("165"),
      inserted_at: ~N[2026-09-05 12:00:00],
      settled_at: ~U[2026-09-05 12:00:00Z],
      cash_tendered: Decimal.new("100"),
      change_due: Decimal.new("0"),
      items: [],
      payment_splits: [
        %Espreso.Orders.PaymentSplit{paid_via: "cash", amount: Decimal.new("100")},
        %Espreso.Orders.PaymentSplit{paid_via: "gcash", amount: Decimal.new("65")}
      ]
    }

    receipt = Receipt.build(order)

    assert receipt =~ "Cash"
    assert receipt =~ "P100.00"
    assert receipt =~ "GCash"
    assert receipt =~ "P65.00"
    assert receipt =~ "Tendered"
  end

  test "kitchen ticket is compact with items and notes" do
    order = %Order{
      number: "CS-KIT001",
      customer_name: "Jay",
      fulfillment: "dine_in",
      table_number: "5",
      notes: "Less ice",
      items: [
        %OrderItem{name: "Scarlet Berry", size: "16oz", category: "COLD", quantity: 2}
      ]
    }

    ticket = Receipt.build_kitchen(order, staff_name: "Ana")

    assert ticket =~ "KITCHEN"
    assert :binary.match(ticket, <<0x1D, 0x76, 0x30, 0x00>>) != :nomatch
    assert ticket =~ "CS-KIT001"
    assert ticket =~ "Dine-in"
    assert ticket =~ "2x Scarlet Berry 16oz Iced"
    assert ticket =~ "NOTE"
    assert ticket =~ "Less ice"
    assert ticket =~ "Cashier: Ana"
    refute ticket =~ "TOTAL"
    refute ticket =~ "P120"
    refute ticket =~ "Wi-Fi"
  end

  test "cash receipt prints tendered once, not a second Cash line" do
    order = %Order{
      number: "CS-CASH1",
      paid_via: "cash",
      total: Decimal.new("160"),
      cash_tendered: Decimal.new("200"),
      change_due: Decimal.new("40"),
      items: []
    }

    receipt = Receipt.build(order)
    refute receipt =~ "Cash"
    assert receipt =~ "TOTAL"
    assert receipt =~ "Tendered"
    assert receipt =~ "Change"
  end

  test "Maya receipt prints Maya once" do
    order = %Order{
      number: "CS-MAYA1",
      paid_via: "maya",
      total: Decimal.new("180"),
      items: []
    }

    receipt = Receipt.build(order)
    assert receipt =~ "Maya"
    refute receipt =~ "GCash"
    refute receipt =~ "Tendered"
  end

  test "non-cash receipt prints the wallet once" do
    order = %Order{
      number: "CS-GCASH1",
      paid_via: "gcash",
      total: Decimal.new("180"),
      items: []
    }

    receipt = Receipt.build(order)
    assert receipt =~ "GCash"
    refute receipt =~ "Tendered"
    refute receipt =~ "Change"
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
    refute receipt == Printer.drawer_bytes()
    assert :binary.match(receipt, <<0x1B, 0x70>>) == :nomatch
  end

  test "dispatch_receipt can append a drawer kick after the cash receipt" do
    restore_printer_config_on_exit()
    {port, printer_task} = start_test_printer!()
    set_test_printer_port(port)

    order = %Order{
      number: "CS-CASH-KICK",
      paid_via: "cash",
      total: Decimal.new("75"),
      inserted_at: ~N[2026-09-05 12:00:00],
      items: []
    }

    assert Printer.dispatch_receipt(order, open_drawer: true) == :dispatched
    receipt = Task.await(printer_task, 2_000)
    assert receipt =~ "CS-CASH-KICK"
    {kick_at, _} = :binary.match(receipt, <<0x1B, 0x70>>)
    {cut_at, _} = :binary.match(receipt, <<0x1D, 0x56, 0x00>>)
    assert kick_at < cut_at
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

  test "dispatch_drawer sends init plus pin-2 and pin-5 kicks" do
    restore_printer_config_on_exit()
    {port, printer_task} = start_test_printer!()
    set_test_printer_port(port)

    assert Printer.dispatch_drawer() == :dispatched
    assert Task.await(printer_task, 2_000) == Printer.drawer_bytes()
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
      transport: :lan_server,
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
        bytes = recv_all(socket)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        bytes
      end)

    {port, task}
  end

  defp recv_all(socket, acc \\ <<>>) do
    case :gen_tcp.recv(socket, 0, 400) do
      {:ok, chunk} -> recv_all(socket, acc <> chunk)
      {:error, :closed} -> acc
      {:error, :timeout} -> acc
    end
  end
end

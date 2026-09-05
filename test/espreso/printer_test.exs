defmodule Espreso.PrinterTest do
  use ExUnit.Case, async: true

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
end

defmodule Espreso.CoffeeSpotTest do
  use ExUnit.Case, async: true

  alias Espreso.CoffeeSpot

  test "order_message lists lines with sizes and total" do
    lines = [
      %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")},
      %{name: "Americano", size: "12oz", quantity: 2, price: Decimal.new("120")}
    ]

    message =
      CoffeeSpot.order_message(lines, %{
        customer_name: "Juan",
        fulfillment: :dine_in,
        table_number: "7",
        notes: "less ice"
      })

    assert message =~ "Hi CoffeeSpot! New order"
    assert message =~ "Name: Juan"
    assert message =~ "Type: Dine-in · Table 7"
    assert message =~ "• 1x Espresso — ₱75"
    assert message =~ "• 2x Americano (12oz) — ₱240"
    assert message =~ "Total: ₱315"
    assert message =~ "Notes: less ice"
  end

  test "order_message supports pickup without notes" do
    lines = [
      %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}
    ]

    message =
      CoffeeSpot.order_message(lines, %{
        customer_name: "Ana",
        fulfillment: :pickup
      })

    assert message =~ "Name: Ana"
    assert message =~ "Type: Pickup at counter"
    refute message =~ "Notes:"
  end

  test "order_whatsapp_url targets CoffeeSpot phone with encoded text" do
    lines = [
      %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}
    ]

    url =
      CoffeeSpot.order_whatsapp_url(lines, %{
        customer_name: "Juan",
        fulfillment: :dine_in,
        table_number: "3"
      })

    assert String.starts_with?(url, "https://wa.me/639566728906?text=")
    assert url =~ URI.encode_www_form("Espresso")
    assert url =~ URI.encode_www_form("₱75")
    assert url =~ URI.encode_www_form("Table 3")
  end
end

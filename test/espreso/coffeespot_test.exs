defmodule Espreso.CoffeeSpotTest do
  use ExUnit.Case, async: true

  alias Espreso.CoffeeSpot

  test "order_message lists lines with sizes and total" do
    lines = [
      %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")},
      %{name: "Americano", size: "12oz", quantity: 2, price: Decimal.new("120")}
    ]

    message = CoffeeSpot.order_message(lines)

    assert message =~ "Hi CoffeeSpot! I'd like to order:"
    assert message =~ "• 1x Espresso — ₱75"
    assert message =~ "• 2x Americano (12oz) — ₱240"
    assert message =~ "Total: ₱315"
  end

  test "order_whatsapp_url targets CoffeeSpot phone with encoded text" do
    lines = [
      %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}
    ]

    url = CoffeeSpot.order_whatsapp_url(lines)

    assert String.starts_with?(url, "https://wa.me/639566728906?text=")
    assert url =~ URI.encode_www_form("Espresso")
    assert url =~ URI.encode_www_form("₱75")
  end
end

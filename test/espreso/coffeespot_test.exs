defmodule Espreso.CoffeeSpotTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.BusinessSettings
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
    assert message =~ "Type: Dine-in"
    refute message =~ "Table 7"
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
    assert message =~ "Type: Takeout"
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
    assert url =~ URI.encode_www_form("Dine-in")
    refute url =~ URI.encode_www_form("Table 3")
  end

  test "contact helpers resolve from default business settings" do
    defaults = BusinessSettings.defaults()

    assert CoffeeSpot.business_name() == defaults.business_name
    assert CoffeeSpot.address() == defaults.address
    assert CoffeeSpot.address_short() == "84 Lilac St., Concepcion Dos, Marikina City, Philippines"
    assert CoffeeSpot.phone_display() == defaults.phone
    assert CoffeeSpot.email() == defaults.email
    assert CoffeeSpot.hours_lines() == defaults.hours_lines
    assert CoffeeSpot.instagram_url() == defaults.instagram_url
    assert CoffeeSpot.facebook_url() == defaults.facebook_url
    assert CoffeeSpot.tiktok_url() == defaults.tiktok_url
    assert CoffeeSpot.email_url() == "mailto:#{defaults.email}"
  end

  test "contact helpers reflect owner updates" do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.coffeespot@test.local",
        password: "password123",
        role: "owner"
      })

    assert {:ok, _} =
             BusinessSettings.update_as(owner, %{
               "business_name" => "Lilac Spot",
               "address" => "100 Test St., Marikina City, Philippines, 1800",
               "phone" => "+639111111111",
               "email" => "desk@lilac.local",
               "hours_text" => "Open daily",
               "instagram_url" => "https://www.instagram.com/lilacspot/",
               "facebook_url" => "https://www.facebook.com/lilacspot",
               "tiktok_url" => "https://www.tiktok.com/@lilacspot"
             })

    assert CoffeeSpot.business_name() == "Lilac Spot"
    assert CoffeeSpot.phone_tel() == "+639111111111"
    assert CoffeeSpot.email() == "desk@lilac.local"
    assert CoffeeSpot.hours_lines() == ["Open daily"]
    assert CoffeeSpot.instagram_url() == "https://www.instagram.com/lilacspot/"

    url =
      CoffeeSpot.order_whatsapp_url(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "A", fulfillment: :pickup}
      )

    assert String.starts_with?(url, "https://wa.me/639111111111?text=")
    assert CoffeeSpot.order_message(
             [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
             %{}
           ) =~ "Hi Lilac Spot! New order"
  end
end

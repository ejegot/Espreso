defmodule Espreso.Orders.DiscountTest do
  use ExUnit.Case, async: true

  alias Espreso.Accounts.User
  alias Espreso.Orders.Discount

  test "percent kinds take 20% off the subtotal" do
    assert {:ok, quote} = Discount.quote(Decimal.new("75"), "senior")
    assert quote.kind == "senior"
    assert quote.label == "Senior 20%"
    assert Decimal.equal?(quote.amount, Decimal.new("15"))
    assert Decimal.equal?(quote.due, Decimal.new("60"))
  end

  test "peso discount is capped at the subtotal" do
    assert {:ok, quote} = Discount.quote(Decimal.new("75"), "peso", "100")
    assert Decimal.equal?(quote.amount, Decimal.new("75"))
    assert Decimal.equal?(quote.due, Decimal.new("0"))
  end

  test "empty peso amount is invalid" do
    assert Discount.quote(Decimal.new("75"), "peso", "") == {:error, :invalid_discount}
  end

  test "customer source ignores discount attrs" do
    assert {:ok, quote} =
             Discount.from_order_attrs(%{discount_kind: "senior"}, Decimal.new("75"), "customer")

    refute Discount.applied?(quote)
    assert Decimal.equal?(quote.due, Decimal.new("75"))
  end

  test "only manager and owner can apply peso off" do
    assert Discount.can_peso?(%User{active: true, role: "manager"})
    assert Discount.can_peso?(%User{active: true, role: "owner"})
    refute Discount.can_peso?(%User{active: true, role: "barista"})
  end
end

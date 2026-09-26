defmodule Espreso.Orders.Discount do
  @moduledoc """
  Order-level POS discounts. Line prices stay list price; `due` is what is collected.
  """

  alias Espreso.Accounts.User

  @percent Decimal.new("0.20")
  @kinds ~w(none senior pwd staff peso)
  @percent_kinds ~w(senior pwd staff)

  def kinds, do: @kinds
  def percent_kinds, do: @percent_kinds

  def can_peso?(%User{active: true, role: role}) when role in ~w(manager owner), do: true
  def can_peso?(_), do: false

  def none(subtotal) do
    subtotal = money(subtotal)

    %{
      kind: "none",
      label: nil,
      amount: Decimal.new("0"),
      subtotal: subtotal,
      due: subtotal
    }
  end

  def quote(subtotal, kind, peso \\ nil)

  def quote(subtotal, kind, _peso) when kind in @percent_kinds do
    subtotal = money(subtotal)
    amount = percent_off(subtotal)
    {:ok, pack(kind, label(kind), amount, subtotal)}
  end

  def quote(subtotal, "peso", peso) do
    subtotal = money(subtotal)

    case parse_peso(peso) do
      {:ok, off} ->
        amount = min_money(off, subtotal)
        {:ok, pack("peso", "₱ off", amount, subtotal)}

      :error ->
        {:error, :invalid_discount}
    end
  end

  def quote(subtotal, _kind, _peso), do: {:ok, none(subtotal)}

  def from_order_attrs(_attrs, subtotal, source) when source != "pos",
    do: {:ok, none(subtotal)}

  def from_order_attrs(attrs, subtotal, "pos") do
    kind = to_string(Map.get(attrs, :discount_kind) || Map.get(attrs, "discount_kind") || "none")

    peso =
      Map.get(attrs, :discount_peso) ||
        Map.get(attrs, "discount_peso") ||
        Map.get(attrs, :discount_amount) ||
        Map.get(attrs, "discount_amount")

    quote(subtotal, kind, peso)
  end

  def applied?(%{kind: kind, amount: amount})
      when kind not in [nil, "none"] and not is_nil(amount) do
    Decimal.compare(amount, 0) == :gt
  end

  def applied?(%{discount_kind: kind, discount_amount: amount})
      when kind not in [nil, "none"] and not is_nil(amount) do
    Decimal.compare(amount, 0) == :gt
  end

  def applied?(_), do: false

  def receipt_label(%{discount_label: label}) when is_binary(label) and label != "", do: label
  def receipt_label(%{discount_kind: kind}), do: label(kind)
  def receipt_label(%{label: label}) when is_binary(label) and label != "", do: label
  def receipt_label(%{kind: kind}), do: label(kind)
  def receipt_label(_), do: "Discount"

  def label("senior"), do: "Senior 20%"
  def label("pwd"), do: "PWD 20%"
  def label("staff"), do: "Staff 20%"
  def label("peso"), do: "₱ off"
  def label(_), do: nil

  defp pack(kind, label, amount, subtotal) do
    amount = money(amount)
    due = subtotal |> Decimal.sub(amount) |> Decimal.round(2)

    %{kind: kind, label: label, amount: amount, subtotal: subtotal, due: due}
  end

  defp percent_off(subtotal),
    do: subtotal |> Decimal.mult(@percent) |> Decimal.round(2)

  defp min_money(a, b) do
    if Decimal.compare(a, b) == :gt, do: b, else: a
  end

  defp money(%Decimal{} = value), do: Decimal.round(value, 2)

  defp money(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> Decimal.round(decimal, 2)
      _ -> Decimal.new("0")
    end
  end

  defp money(value) when is_integer(value), do: Decimal.round(Decimal.new(value), 2)
  defp money(_), do: Decimal.new("0")

  defp parse_peso(%Decimal{} = value) do
    if Decimal.compare(value, 0) == :gt, do: {:ok, Decimal.round(value, 2)}, else: :error
  end

  defp parse_peso(value) when is_binary(value) do
    cleaned = value |> String.trim() |> String.replace(",", "")

    case Decimal.parse(cleaned) do
      {decimal, ""} ->
        if Decimal.compare(decimal, 0) == :gt,
          do: {:ok, Decimal.round(decimal, 2)},
          else: :error

      _ ->
        :error
    end
  end

  defp parse_peso(_), do: :error
end

defmodule Espreso.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Orders.Order

  schema "order_items" do
    field :name, :string
    field :size, :string
    field :category, :string
    field :item_owner, :string
    field :quantity, :integer
    field :unit_price, :decimal
    field :line_total, :decimal
    field :item_discount_kind, :string, default: "none"
    field :item_discount_label, :string
    field :item_discount_amount, :decimal, default: Decimal.new("0")
    field :item_discount_quantity, :integer, default: 0

    belongs_to :order, Order

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :size,
      :category,
      :item_owner,
      :quantity,
      :unit_price,
      :line_total,
      :item_discount_kind,
      :item_discount_label,
      :item_discount_amount,
      :item_discount_quantity,
      :order_id
    ])
    |> update_change(:item_owner, &blank_to_nil/1)
    |> validate_length(:item_owner, max: 40)
    |> validate_required([:name, :quantity, :unit_price, :line_total])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> validate_number(:line_total, greater_than_or_equal_to: 0)
    |> validate_inclusion(:item_discount_kind, ~w(none senior pwd staff peso))
    |> validate_number(:item_discount_amount, greater_than_or_equal_to: 0)
    |> validate_number(:item_discount_quantity, greater_than_or_equal_to: 0)
    |> validate_item_discount_quantity()
    |> foreign_key_constraint(:order_id)
  end

  defp validate_item_discount_quantity(changeset) do
    quantity = get_field(changeset, :quantity)
    discounted_quantity = get_field(changeset, :item_discount_quantity) || 0

    if is_integer(quantity) and discounted_quantity > quantity do
      add_error(changeset, :item_discount_quantity, "cannot exceed item quantity")
    else
      changeset
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end

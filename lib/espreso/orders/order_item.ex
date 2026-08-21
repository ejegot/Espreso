defmodule Espreso.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Orders.Order

  schema "order_items" do
    field :name, :string
    field :size, :string
    field :quantity, :integer
    field :unit_price, :decimal
    field :line_total, :decimal

    belongs_to :order, Order

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :size, :quantity, :unit_price, :line_total, :order_id])
    |> validate_required([:name, :quantity, :unit_price, :line_total])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> validate_number(:line_total, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:order_id)
  end
end

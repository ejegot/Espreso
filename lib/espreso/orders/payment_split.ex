defmodule Espreso.Orders.PaymentSplit do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Orders.Order

  @paid_vias ~w(cash gcash maya)

  schema "order_payment_splits" do
    field :paid_via, :string
    field :amount, :decimal

    belongs_to :order, Order

    timestamps(type: :utc_datetime)
  end

  def paid_vias, do: @paid_vias

  def changeset(split, attrs) do
    split
    |> cast(attrs, [:paid_via, :amount, :order_id])
    |> validate_required([:paid_via, :amount, :order_id])
    |> validate_inclusion(:paid_via, @paid_vias)
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:order_id)
    |> unique_constraint([:order_id, :paid_via])
    |> check_constraint(:amount, name: :order_payment_splits_amount_positive)
    |> check_constraint(:paid_via, name: :order_payment_splits_paid_via)
  end
end

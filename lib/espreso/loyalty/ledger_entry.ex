defmodule Espreso.Loyalty.LedgerEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Customers.Customer
  alias Espreso.Orders.Order

  @kinds ~w(earn redeem)

  schema "loyalty_ledger_entries" do
    field :kind, :string
    field :points, :integer
    field :qualifying_amount_centavos, :integer
    field :metadata, :map, default: %{}

    belongs_to :customer, Customer
    belongs_to :order, Order

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def earn_changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :kind,
      :points,
      :qualifying_amount_centavos,
      :metadata,
      :customer_id,
      :order_id
    ])
    |> put_change(:kind, "earn")
    |> validate_required([:kind, :points, :qualifying_amount_centavos, :customer_id, :order_id])
    |> validate_number(:points, greater_than_or_equal_to: 0)
    |> validate_number(:qualifying_amount_centavos, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:order_id)
    |> unique_constraint(:order_id, name: :loyalty_ledger_entries_one_earn_per_order)
  end

  def redeem_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:kind, :points, :metadata, :customer_id, :order_id])
    |> put_change(:kind, "redeem")
    |> put_change(:points, -10)
    |> validate_required([:kind, :points, :customer_id, :order_id])
    |> validate_number(:points, less_than: 0)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:order_id)
  end
end

defmodule Espreso.Orders.PaymentReconciliation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Orders.Order

  schema "paymongo_payment_reconciliations" do
    field :order_number, :string
    field :paymongo_checkout_session_id, :string
    field :paymongo_payment_id, :string
    field :paymongo_webhook_event_id, :string
    field :amount_centavos, :integer
    field :currency, :string

    belongs_to :order, Order

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(reconciliation, attrs) do
    reconciliation
    |> cast(attrs, [
      :order_id,
      :order_number,
      :paymongo_checkout_session_id,
      :paymongo_payment_id,
      :paymongo_webhook_event_id,
      :amount_centavos,
      :currency
    ])
    |> validate_required([
      :order_id,
      :order_number,
      :paymongo_checkout_session_id,
      :amount_centavos,
      :currency
    ])
    |> unique_constraint(:paymongo_checkout_session_id)
    |> foreign_key_constraint(:order_id)
  end
end

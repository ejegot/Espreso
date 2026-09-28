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
    belongs_to :tenant, Espreso.Tenancy.Tenant
    belongs_to :branch, Espreso.Tenancy.Branch

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
      :currency,
      :tenant_id,
      :branch_id
    ])
    |> validate_required([
      :order_id,
      :order_number,
      :paymongo_checkout_session_id,
      :amount_centavos,
      :currency
    ])
    |> unique_constraint(:paymongo_checkout_session_id)
    |> Espreso.Tenancy.put_ids()
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:branch_id)
  end
end

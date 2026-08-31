defmodule Espreso.Repo.Migrations.CreatePaymongoPaymentReconciliations do
  use Ecto.Migration

  def change do
    create table(:paymongo_payment_reconciliations) do
      add :order_id, references(:orders, on_delete: :nothing), null: false
      add :order_number, :string, null: false
      add :paymongo_checkout_session_id, :string, null: false
      add :paymongo_payment_id, :string
      add :paymongo_webhook_event_id, :string
      add :amount_centavos, :integer, null: false
      add :currency, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:paymongo_payment_reconciliations, [:paymongo_checkout_session_id])
    create index(:paymongo_payment_reconciliations, [:order_id])
    create index(:paymongo_payment_reconciliations, [:inserted_at])
  end
end

defmodule Espreso.Repo.Migrations.CreateOrderPaymentSplits do
  use Ecto.Migration

  def change do
    create table(:order_payment_splits) do
      add :paid_via, :string, null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :order_id, references(:orders, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:order_payment_splits, [:order_id, :paid_via])
    create index(:order_payment_splits, [:order_id])

    create constraint(:order_payment_splits, :order_payment_splits_amount_positive,
             check: "amount > 0"
           )

    create constraint(:order_payment_splits, :order_payment_splits_paid_via,
             check: "paid_via IN ('cash', 'gcash', 'maya')"
           )
  end
end

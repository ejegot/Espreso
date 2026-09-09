defmodule Espreso.Repo.Migrations.AddSettlementMetadataToOrders do
  use Ecto.Migration

  def up do
    alter table(:orders) do
      add :settled_at, :utc_datetime
      add :settled_by_user_id, references(:users, on_delete: :nilify_all)
      add :settlement_source, :string
      add :cash_tendered, :decimal, precision: 12, scale: 2
      add :change_due, :decimal, precision: 12, scale: 2
      add :settlement_time_estimated, :boolean, null: false, default: false
    end

    execute("""
    UPDATE orders
    SET settled_at = inserted_at,
        settlement_source = 'legacy',
        settlement_time_estimated = TRUE
    WHERE payment_status = 'paid'
    """)

    create index(:orders, [:settled_at, :id])
    create index(:orders, [:settled_by_user_id])

    create constraint(:orders, :paid_orders_have_settlement_time,
             check: "payment_status <> 'paid' OR settled_at IS NOT NULL"
           )

    create constraint(:orders, :paid_orders_have_settlement_source,
             check: "payment_status <> 'paid' OR settlement_source IS NOT NULL"
           )

    create constraint(:orders, :cash_tendered_is_nonnegative,
             check: "cash_tendered IS NULL OR cash_tendered >= 0"
           )

    create constraint(:orders, :change_due_is_nonnegative,
             check: "change_due IS NULL OR change_due >= 0"
           )
  end

  def down do
    drop constraint(:orders, :change_due_is_nonnegative)
    drop constraint(:orders, :cash_tendered_is_nonnegative)
    drop constraint(:orders, :paid_orders_have_settlement_source)
    drop constraint(:orders, :paid_orders_have_settlement_time)
    drop index(:orders, [:settled_by_user_id])
    drop index(:orders, [:settled_at, :id])

    alter table(:orders) do
      remove :settlement_time_estimated
      remove :change_due
      remove :cash_tendered
      remove :settlement_source
      remove :settled_by_user_id
      remove :settled_at
    end
  end
end

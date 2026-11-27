defmodule Espreso.Repo.Migrations.CreateShopSessionAdjustments do
  use Ecto.Migration

  def change do
    alter table(:shift_closes) do
      add :cash_sales, :decimal
      add :adjustment_cash_impact, :decimal
    end

    create table(:shop_session_adjustments) do
      add :kind, :string, null: false
      add :reason, :string, null: false
      add :payment_method, :string, null: false
      add :payment_breakdown, :map, null: false, default: %{}
      add :sales_impact, :decimal, null: false
      add :drawer_impact, :decimal, null: false, default: 0

      add :original_order_id, references(:orders, on_delete: :restrict), null: false
      add :shop_session_id, references(:shop_day_opens, on_delete: :restrict), null: false
      add :recorded_by_user_id, references(:users, on_delete: :restrict), null: false
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false
      add :branch_id, references(:branches, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shop_session_adjustments, [:original_order_id],
             name: :shop_session_adjustments_one_per_original_order
           )

    create index(:shop_session_adjustments, [:branch_id, :shop_session_id])
    create index(:shop_session_adjustments, [:recorded_by_user_id])

    create constraint(:shop_session_adjustments, :shop_session_adjustments_kind,
             check: "kind IN ('refund', 'duplicate_void')"
           )

    create constraint(
             :shop_session_adjustments,
             :shop_session_adjustments_payment_method,
             check: "payment_method IN ('cash', 'gcash', 'maya', 'counter', 'paymongo', 'split')"
           )

    create constraint(:shop_session_adjustments, :shop_session_adjustments_negative_sales_impact,
             check: "sales_impact < 0"
           )

    create constraint(
             :shop_session_adjustments,
             :shop_session_adjustments_nonpositive_drawer_impact,
             check: "drawer_impact <= 0"
           )
  end
end

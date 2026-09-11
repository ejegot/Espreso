defmodule Espreso.Repo.Migrations.CreateLoyaltyPhase1 do
  use Ecto.Migration

  def up do
    create table(:customers) do
      add :phone_e164, :string, null: false
      add :name, :string
      add :points_balance, :integer, null: false, default: 0
      add :spend_remainder_centavos, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customers, [:phone_e164])

    create constraint(:customers, :customers_points_balance_nonnegative,
             check: "points_balance >= 0"
           )

    create constraint(:customers, :customers_spend_remainder_range,
             check: "spend_remainder_centavos >= 0 AND spend_remainder_centavos < 20000"
           )

    create table(:loyalty_ledger_entries) do
      add :kind, :string, null: false
      add :points, :integer, null: false
      add :qualifying_amount_centavos, :integer
      add :metadata, :map, null: false, default: %{}
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :order_id, references(:orders, on_delete: :restrict)

      timestamps(type: :utc_datetime)
    end

    create index(:loyalty_ledger_entries, [:customer_id])
    create index(:loyalty_ledger_entries, [:order_id])

    create unique_index(:loyalty_ledger_entries, [:order_id],
             where: "kind = 'earn' AND order_id IS NOT NULL",
             name: :loyalty_ledger_entries_one_earn_per_order
           )

    create constraint(:loyalty_ledger_entries, :loyalty_ledger_kind_valid,
             check: "kind IN ('earn', 'redeem')"
           )

    create constraint(:loyalty_ledger_entries, :loyalty_ledger_earn_points_nonnegative,
             check: "kind <> 'earn' OR points >= 0"
           )

    create constraint(:loyalty_ledger_entries, :loyalty_ledger_redeem_points_negative,
             check: "kind <> 'redeem' OR points < 0"
           )

    create constraint(:loyalty_ledger_entries, :loyalty_ledger_earn_has_qualifying,
             check:
               "kind <> 'earn' OR (qualifying_amount_centavos IS NOT NULL AND qualifying_amount_centavos >= 0)"
           )

    alter table(:orders) do
      add :customer_id, references(:customers, on_delete: :nilify_all)
      add :loyalty_free_amount_centavos, :integer, null: false, default: 0
    end

    create index(:orders, [:customer_id])

    create constraint(:orders, :orders_loyalty_free_amount_nonnegative,
             check: "loyalty_free_amount_centavos >= 0"
           )
  end

  def down do
    drop constraint(:orders, :orders_loyalty_free_amount_nonnegative)
    drop index(:orders, [:customer_id])

    alter table(:orders) do
      remove :loyalty_free_amount_centavos
      remove :customer_id
    end

    drop constraint(:loyalty_ledger_entries, :loyalty_ledger_earn_has_qualifying)
    drop constraint(:loyalty_ledger_entries, :loyalty_ledger_redeem_points_negative)
    drop constraint(:loyalty_ledger_entries, :loyalty_ledger_earn_points_nonnegative)
    drop constraint(:loyalty_ledger_entries, :loyalty_ledger_kind_valid)

    drop_if_exists index(:loyalty_ledger_entries, [:order_id],
                     name: :loyalty_ledger_entries_one_earn_per_order
                   )

    drop index(:loyalty_ledger_entries, [:order_id])
    drop index(:loyalty_ledger_entries, [:customer_id])
    drop table(:loyalty_ledger_entries)

    drop constraint(:customers, :customers_spend_remainder_range)
    drop constraint(:customers, :customers_points_balance_nonnegative)
    drop_if_exists index(:customers, [:phone_e164])
    drop table(:customers)
  end
end

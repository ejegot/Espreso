defmodule Espreso.Repo.Migrations.CreateTenantsAndBranches do
  use Ecto.Migration

  @shop_tables [
    :users,
    :categories,
    :products,
    :orders,
    :customers,
    :business_settings,
    :shop_day_opens,
    :shift_closes,
    :staff_shifts,
    :cash_outs,
    :loyalty_ledger_entries,
    :order_push_subscriptions,
    :paymongo_payment_reconciliations
  ]

  def up do
    create table(:tenants) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :guest_brand_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:slug])

    create table(:branches) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :code, :string, null: false
      add :address, :string
      add :main, :boolean, null: false, default: false
      add :tenant_id, references(:tenants, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:branches, [:tenant_id, :slug])
    create unique_index(:branches, [:code])
    create index(:branches, [:tenant_id])

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    execute("""
    INSERT INTO tenants (name, slug, guest_brand_name, inserted_at, updated_at)
    VALUES (
      'CoffeeSpot',
      'coffeespot',
      'CoffeeSpot',
      '#{now}',
      '#{now}'
    )
    """)

    execute("""
    INSERT INTO branches (
      name, slug, code, address, main, tenant_id, inserted_at, updated_at
    )
    SELECT
      'Lilac',
      'lilac',
      'lilac',
      '84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811',
      TRUE,
      t.id,
      '#{now}',
      '#{now}'
    FROM tenants t
    WHERE t.slug = 'coffeespot'
    """)

    for table <- @shop_tables do
      alter table(table) do
        add :tenant_id, references(:tenants, on_delete: :restrict)
        add :branch_id, references(:branches, on_delete: :restrict)
      end
    end

    for table <- @shop_tables do
      execute("""
      UPDATE #{table} AS rows
      SET
        tenant_id = t.id,
        branch_id = b.id
      FROM tenants t
      JOIN branches b ON b.tenant_id = t.id AND b.slug = 'lilac'
      WHERE t.slug = 'coffeespot'
        AND rows.tenant_id IS NULL
      """)
    end

    for table <- @shop_tables do
      execute("ALTER TABLE #{table} ALTER COLUMN tenant_id SET NOT NULL")
      execute("ALTER TABLE #{table} ALTER COLUMN branch_id SET NOT NULL")
      create index(table, [:tenant_id])

      unless table == :business_settings do
        create index(table, [:branch_id])
      end
    end

    drop unique_index(:shop_day_opens, [:shop_date])
    create unique_index(:shop_day_opens, [:branch_id, :shop_date])

    drop unique_index(:shift_closes, [:shop_date])
    create unique_index(:shift_closes, [:branch_id, :shop_date])

    drop unique_index(:business_settings, [:singleton_key])
    create unique_index(:business_settings, [:branch_id])
  end

  def down do
    drop unique_index(:business_settings, [:branch_id])
    create unique_index(:business_settings, [:singleton_key])

    drop unique_index(:shift_closes, [:branch_id, :shop_date])
    create unique_index(:shift_closes, [:shop_date])

    drop unique_index(:shop_day_opens, [:branch_id, :shop_date])
    create unique_index(:shop_day_opens, [:shop_date])

    for table <- @shop_tables do
      unless table == :business_settings do
        drop index(table, [:branch_id])
      end

      drop index(table, [:tenant_id])

      alter table(table) do
        remove :branch_id
        remove :tenant_id
      end
    end

    drop table(:branches)
    drop table(:tenants)
  end
end

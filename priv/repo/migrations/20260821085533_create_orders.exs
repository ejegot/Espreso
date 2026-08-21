defmodule Espreso.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :number, :string, null: false
      add :customer_name, :string, null: false
      add :fulfillment, :string, null: false, default: "dine_in"
      add :table_number, :string
      add :notes, :string
      add :status, :string, null: false, default: "received"
      add :payment_method, :string, null: false, default: "counter"
      add :payment_status, :string, null: false, default: "unpaid"
      add :total, :decimal, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:number])
    create index(:orders, [:status])
    create index(:orders, [:inserted_at])

    create table(:order_items) do
      add :name, :string, null: false
      add :size, :string
      add :quantity, :integer, null: false
      add :unit_price, :decimal, null: false
      add :line_total, :decimal, null: false
      add :order_id, references(:orders, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
  end
end

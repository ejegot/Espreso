defmodule Espreso.Repo.Migrations.AddOrderDiscounts do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :discount_kind, :string, null: false, default: "none"
      add :discount_label, :string
      add :discount_amount, :decimal, null: false, default: 0
    end

    create constraint(:orders, :orders_discount_amount_nonnegative,
             check: "discount_amount >= 0"
           )

    create constraint(:orders, :orders_discount_kind_allowed,
             check: "discount_kind IN ('none', 'senior', 'pwd', 'staff', 'peso')"
           )
  end
end

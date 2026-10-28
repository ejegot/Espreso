defmodule Espreso.Repo.Migrations.AddItemDiscountsToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :item_discount_kind, :string, null: false, default: "none"
      add :item_discount_label, :string
      add :item_discount_amount, :decimal, null: false, default: 0
      add :item_discount_quantity, :integer, null: false, default: 0
    end

    create constraint(:order_items, :order_items_item_discount_amount_nonnegative,
             check: "item_discount_amount >= 0"
           )

    create constraint(:order_items, :order_items_item_discount_quantity_valid,
             check: "item_discount_quantity >= 0 AND item_discount_quantity <= quantity"
           )

    create constraint(:order_items, :order_items_item_discount_kind_allowed,
             check: "item_discount_kind IN ('none', 'senior', 'pwd', 'staff', 'peso')"
           )
  end
end

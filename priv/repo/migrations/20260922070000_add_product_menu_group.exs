defmodule Espreso.Repo.Migrations.AddProductMenuGroup do
  use Ecto.Migration

  def up do
    alter table(:products) do
      add :menu_group, :string
    end

    create unique_index(:products, [:category_id, :name], name: :products_category_id_name_index)

    execute """
    UPDATE products AS p
    SET menu_group = v.grp
    FROM (
      VALUES
        ('Chicken Flakes', 'Rice Meal'),
        ('Beef Tapa', 'Rice Meal'),
        ('Corned Beef', 'Rice Meal'),
        ('Spam', 'Rice Meal'),
        ('Pork Liempo', 'Rice Meal'),
        ('Spam Musubi', 'Rice Meal'),
        ('Nugget', 'Rice Meal'),
        ('Solo Fries', 'Appetizers'),
        ('Fries w/ Nuggets', 'Appetizers'),
        ('Beef Nachos', 'Appetizers'),
        ('Quesadillas', 'Appetizers'),
        ('Chicken & Chips', 'Appetizers'),
        ('Spam & Chips', 'Appetizers'),
        ('Slow-Roasted Chicken Sourdough', 'Sandwiches & Wraps'),
        ('Golden Egg Royale', 'Sandwiches & Wraps'),
        ('Tuna Royale Baguette', 'Sandwiches & Wraps'),
        ('Big Assorted Muffin', 'Muffins'),
        ('BNN Cream Cheese', 'Muffins'),
        ('BNN Choco Overload', 'Muffins'),
        ('BNN Biscoff', 'Muffins'),
        ('Choco Chips', 'Muffins'),
        ('Red Velvet', 'Muffins'),
        ('Dark Choco Dream Cake', 'Cakes / Breads'),
        ('Choco Chip Cookies', 'Cakes / Breads'),
        ('BNN Moist Slice', 'Cakes / Breads'),
        ('Choco Moist Slice', 'Cakes / Breads'),
        ('Carrot Moist Slice', 'Cakes / Breads'),
        ('Belgian Waffles', 'Cakes / Breads'),
        ('Chocolate Almond Waffles', 'Cakes / Breads')
    ) AS v(name, grp)
    WHERE p.name = v.name
      AND p.category_id = (SELECT id FROM categories WHERE name = 'FOOD' LIMIT 1)
    """
  end

  def down do
    drop index(:products, [:category_id, :name], name: :products_category_id_name_index)

    alter table(:products) do
      remove :menu_group
    end
  end
end

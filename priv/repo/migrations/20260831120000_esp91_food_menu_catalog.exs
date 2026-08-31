defmodule Espreso.Repo.Migrations.Esp91FoodMenuCatalog do
  use Ecto.Migration
  import Ecto.Query

  @retired_muffins [
    "BNN Cream Cheese",
    "BNN Choco Overload",
    "BNN Biscoff",
    "Choco Chips",
    "Red Velvet"
  ]

  @new_products [
    {"Slow-Roasted Chicken Sourdough", "249"},
    {"Golden Egg Royale", "199"},
    {"Tuna Royale Baguette", "249"},
    {"Big Assorted Muffin", "99"}
  ]

  def up do
    case repo().one(from(c in "categories", where: c.name == "FOOD", select: c.id)) do
      nil ->
        :ok

      food_id ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        from(p in "products",
          where: p.category_id == ^food_id and p.name in ^@retired_muffins,
          update: [set: [available: false, updated_at: ^now]]
        )
        |> repo().update_all([])

        Enum.each(@new_products, fn {name, price} ->
          upsert_food_product(food_id, name, price, now)
        end)
    end
  end

  def down do
    case repo().one(from(c in "categories", where: c.name == "FOOD", select: c.id)) do
      nil ->
        :ok

      food_id ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        new_names = Enum.map(@new_products, &elem(&1, 0))

        from(p in "products",
          where: p.category_id == ^food_id and p.name in ^new_names,
          update: [set: [available: false, updated_at: ^now]]
        )
        |> repo().update_all([])

        from(p in "products",
          where: p.category_id == ^food_id and p.name in ^@retired_muffins,
          update: [set: [available: true, updated_at: ^now]]
        )
        |> repo().update_all([])
    end
  end

  defp upsert_food_product(food_id, name, price, now) do
    product_id =
      case repo().one(
             from(p in "products",
               where: p.category_id == ^food_id and p.name == ^name,
               select: p.id
             )
           ) do
        nil ->
          {1, rows} =
            repo().insert_all(
              "products",
              [
                %{
                  name: name,
                  available: true,
                  category_id: food_id,
                  inserted_at: now,
                  updated_at: now
                }
              ],
              returning: [:id]
            )

          rows |> List.first() |> Map.fetch!(:id)

        id ->
          from(p in "products",
            where: p.id == ^id,
            update: [set: [available: true, updated_at: ^now]]
          )
          |> repo().update_all([])

          id
      end

    price_id =
      repo().one(
        from(pp in "product_prices",
          where: pp.product_id == ^product_id and is_nil(pp.size),
          select: pp.id
        )
      )

    if price_id do
      decimal_price = Decimal.new(price)

      from(pp in "product_prices",
        where: pp.id == ^price_id,
        update: [set: [price: ^decimal_price, updated_at: ^now]]
      )
      |> repo().update_all([])
    else
      repo().insert_all(
        "product_prices",
        [
          %{
            product_id: product_id,
            size: nil,
            price: Decimal.new(price),
            inserted_at: now,
            updated_at: now
          }
        ]
      )
    end
  end
end

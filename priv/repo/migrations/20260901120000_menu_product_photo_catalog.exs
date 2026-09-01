defmodule Espreso.Repo.Migrations.MenuProductPhotoCatalog do
  use Ecto.Migration
  import Ecto.Query

  @cold_product {"Iced Bellagio Choco", "16oz", "180"}

  @food_products [
    {"Belgian Waffles", nil, "149"},
    {"Chocolate Almond Waffles", nil, "149"}
  ]

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rename_soda_product("Green Apple Campaign", "Green Apple Campagna", now)

    case category_id("COLD") do
      nil -> :ok
      cold_id -> upsert_product(cold_id, @cold_product, now)
    end

    case category_id("FOOD") do
      nil ->
        :ok

      food_id ->
        Enum.each(@food_products, fn product ->
          upsert_product(food_id, product, now)
        end)
    end
  end

  def down do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rename_soda_product("Green Apple Campagna", "Green Apple Campaign", now)

    case category_id("COLD") do
      nil -> :ok
      cold_id -> retire_product(cold_id, elem(@cold_product, 0), now)
    end

    case category_id("FOOD") do
      nil ->
        :ok

      food_id ->
        Enum.each(@food_products, fn {name, _, _} ->
          retire_product(food_id, name, now)
        end)
    end
  end

  defp category_id(name) do
    repo().one(from(c in "categories", where: c.name == ^name, select: c.id))
  end

  defp rename_soda_product(old_name, new_name, now) do
    case category_id("SODA") do
      nil ->
        :ok

      soda_id ->
        from(p in "products",
          where: p.category_id == ^soda_id and p.name == ^old_name,
          update: [set: [name: ^new_name, updated_at: ^now]]
        )
        |> repo().update_all([])
    end
  end

  defp retire_product(category_id, name, now) do
    from(p in "products",
      where: p.category_id == ^category_id and p.name == ^name,
      update: [set: [available: false, updated_at: ^now]]
    )
    |> repo().update_all([])
  end

  defp upsert_product(category_id, {name, size, price}, now) do
    product_id =
      case repo().one(
             from(p in "products",
               where: p.category_id == ^category_id and p.name == ^name,
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
                  category_id: category_id,
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

    price_query =
      if is_nil(size) do
        from(pp in "product_prices",
          where: pp.product_id == ^product_id and is_nil(pp.size),
          select: pp.id
        )
      else
        from(pp in "product_prices",
          where: pp.product_id == ^product_id and pp.size == ^size,
          select: pp.id
        )
      end

    case repo().one(price_query) do
      nil ->
        repo().insert_all(
          "product_prices",
          [
            %{
              product_id: product_id,
              size: size,
              price: Decimal.new(price),
              inserted_at: now,
              updated_at: now
            }
          ]
        )

      price_id ->
        decimal_price = Decimal.new(price)

        from(pp in "product_prices",
          where: pp.id == ^price_id,
          update: [set: [price: ^decimal_price, updated_at: ^now]]
        )
        |> repo().update_all([])
    end
  end
end

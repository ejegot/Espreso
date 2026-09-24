defmodule Espreso.Repo.Migrations.UpdateFoodShopCatalog do
  use Ecto.Migration
  import Ecto.Query

  @retired [
    "Spam & Chips",
    "Belgian Waffles",
    "Chocolate Almond Waffles"
  ]

  def up do
    case repo().one(from(c in "categories", where: c.name == "FOOD", select: c.id)) do
      nil ->
        :ok

      food_id ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        rename_or_keep(food_id, "Spam & Chips", "Spam Burger", now)
        rename_or_keep(food_id, "Belgian Waffles", "Waffles", now)

        upsert_single(food_id, "Chicken & Chips", "199", "Appetizers", now)
        upsert_single(food_id, "Spam Burger", "179", "Sandwiches & Wraps", now)
        upsert_flavors(food_id, "Waffles", "Cakes / Breads", now)

        clear_description(food_id, [
          "Spam",
          "Nugget",
          "Chicken & Chips",
          "Spam Burger",
          "Waffles",
          "Big Assorted Muffin"
        ])

        from(p in "products",
          where: p.category_id == ^food_id and p.name in ^@retired,
          update: [set: [available: false, updated_at: ^now]]
        )
        |> repo().update_all([])
    end
  end

  def down do
    :ok
  end

  defp rename_or_keep(food_id, old_name, new_name, now) do
    old_id = product_id(food_id, old_name)
    new_id = product_id(food_id, new_name)

    cond do
      is_nil(old_id) ->
        :ok

      is_nil(new_id) or new_id == old_id ->
        from(p in "products",
          where: p.id == ^old_id,
          update: [set: [name: ^new_name, available: true, updated_at: ^now]]
        )
        |> repo().update_all([])

      true ->
        from(p in "products",
          where: p.id == ^old_id,
          update: [set: [available: false, updated_at: ^now]]
        )
        |> repo().update_all([])
    end
  end

  defp upsert_single(food_id, name, price, group, now) do
    id = ensure_product(food_id, name, group, now)

    from(pp in "product_prices", where: pp.product_id == ^id)
    |> repo().delete_all()

    repo().insert_all("product_prices", [
      %{
        product_id: id,
        size: nil,
        price: Decimal.new(price),
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  defp upsert_flavors(food_id, name, group, now) do
    id = ensure_product(food_id, name, group, now)

    from(pp in "product_prices", where: pp.product_id == ^id)
    |> repo().delete_all()

    repo().insert_all(
      "product_prices",
      [
        price_row(id, "Plain", "99", now),
        price_row(id, "Chocolate", "129", now),
        price_row(id, "Strawberry", "129", now)
      ]
    )
  end

  defp price_row(product_id, size, price, now) do
    %{
      product_id: product_id,
      size: size,
      price: Decimal.new(price),
      inserted_at: now,
      updated_at: now
    }
  end

  defp ensure_product(food_id, name, group, now) do
    case product_id(food_id, name) do
      nil ->
        {1, rows} =
          repo().insert_all(
            "products",
            [
              %{
                name: name,
                available: true,
                category_id: food_id,
                menu_group: group,
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
          update: [set: [available: true, menu_group: ^group, updated_at: ^now]]
        )
        |> repo().update_all([])

        id
    end
  end

  defp product_id(food_id, name) do
    repo().one(
      from(p in "products",
        where: p.category_id == ^food_id and p.name == ^name,
        select: p.id
      )
    )
  end

  defp clear_description(food_id, names) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(p in "products",
      where: p.category_id == ^food_id and p.name in ^names,
      update: [set: [description: nil, updated_at: ^now]]
    )
    |> repo().update_all([])
  end
end

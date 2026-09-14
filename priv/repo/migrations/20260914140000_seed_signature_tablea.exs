defmodule Espreso.Repo.Migrations.SeedSignatureTablea do
  use Ecto.Migration
  import Ecto.Query

  @product_name "Signature Tablea"
  @price "169"

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case category_id("HOT") do
      nil -> :ok
      hot_id -> upsert_product(hot_id, {@product_name, nil, @price}, now)
    end
  end

  def down do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case category_id("HOT") do
      nil -> :ok
      hot_id -> retire_product(hot_id, @product_name, now)
    end
  end

  defp category_id(name) do
    repo().one(from(c in "categories", where: c.name == ^name, select: c.id))
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

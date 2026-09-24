defmodule Espreso.Repo.Migrations.WaffleIncludePlain99 do
  use Ecto.Migration
  import Ecto.Query

  def up do
    case repo().one(from(c in "categories", where: c.name == "FOOD", select: c.id)) do
      nil ->
        :ok

      food_id ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        id =
          repo().one(
            from(p in "products",
              where: p.category_id == ^food_id and p.name == "Waffles",
              select: p.id
            )
          )

        if id do
          from(p in "products",
            where: p.id == ^id,
            update: [set: [available: true, description: nil, updated_at: ^now]]
          )
          |> repo().update_all([])

          from(pp in "product_prices", where: pp.product_id == ^id)
          |> repo().delete_all()

          repo().insert_all("product_prices", [
            price_row(id, "Plain", "99", now),
            price_row(id, "Chocolate", "129", now),
            price_row(id, "Strawberry", "129", now)
          ])
        end
    end
  end

  def down do
    :ok
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
end

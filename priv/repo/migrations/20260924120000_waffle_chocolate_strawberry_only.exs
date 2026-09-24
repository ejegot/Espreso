defmodule Espreso.Repo.Migrations.WaffleChocolateStrawberryOnly do
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
            %{
              product_id: id,
              size: "Chocolate",
              price: Decimal.new("129"),
              inserted_at: now,
              updated_at: now
            },
            %{
              product_id: id,
              size: "Strawberry",
              price: Decimal.new("129"),
              inserted_at: now,
              updated_at: now
            }
          ])
        end
    end
  end

  def down do
    :ok
  end
end

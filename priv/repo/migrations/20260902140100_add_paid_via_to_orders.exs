defmodule Espreso.Repo.Migrations.AddPaidViaToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :paid_via, :string
    end
  end
end

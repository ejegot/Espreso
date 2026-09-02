defmodule Espreso.Repo.Migrations.AddPinHashToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :pin_hash, :string
    end
  end
end

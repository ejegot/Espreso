defmodule Espreso.Repo.Migrations.CreateBusinessGcashQrs do
  use Ecto.Migration

  def change do
    create table(:business_gcash_qrs) do
      add :branch_id,
          references(:branches, on_delete: :delete_all),
          null: false

      add :content_type, :string, null: false
      add :data, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:business_gcash_qrs, [:branch_id])
  end
end

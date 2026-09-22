defmodule Espreso.Repo.Migrations.AddProductPhotos do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :has_custom_photo, :boolean, default: false, null: false
      add :photo_updated_at, :utc_datetime
    end

    create table(:product_photos) do
      add :content_type, :string, null: false
      add :data, :binary, null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_photos, [:product_id])
  end
end

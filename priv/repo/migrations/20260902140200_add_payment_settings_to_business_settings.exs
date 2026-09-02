defmodule Espreso.Repo.Migrations.AddPaymentSettingsToBusinessSettings do
  use Ecto.Migration

  def change do
    alter table(:business_settings) do
      add :payments_mode, :string, null: false, default: "paymongo"
      add :gcash_qrph_path, :string
      add :maya_qrph_path, :string
    end
  end
end

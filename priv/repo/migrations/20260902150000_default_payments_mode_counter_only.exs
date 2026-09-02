defmodule Espreso.Repo.Migrations.DefaultPaymentsModeCounterOnly do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE business_settings
    SET payments_mode = 'counter_only'
    WHERE payments_mode = 'paymongo'
    """)

    alter table(:business_settings) do
      modify :payments_mode, :string, default: "counter_only"
    end
  end

  def down do
    alter table(:business_settings) do
      modify :payments_mode, :string, default: "paymongo"
    end

    execute("""
    UPDATE business_settings
    SET payments_mode = 'paymongo'
    WHERE payments_mode = 'counter_only'
    """)
  end
end

defmodule Espreso.Repo.Migrations.SetGcashQrphPathForQrphManual do
  use Ecto.Migration

  @gcash_path "/images/coffeespot/gcash-qrph.png"

  def up do
    # Availability gate for GCash under qrph_manual. Does not change payments_mode
    # (keep existing qrph_manual in prod) and does not touch maya_qrph_path.
    execute("""
    UPDATE business_settings
    SET gcash_qrph_path = '#{@gcash_path}'
    """)
  end

  def down do
    execute("""
    UPDATE business_settings
    SET gcash_qrph_path = NULL
    WHERE gcash_qrph_path = '#{@gcash_path}'
    """)
  end
end

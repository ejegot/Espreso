defmodule Espreso.Repo.Migrations.AddPettyCashToShiftCloses do
  use Ecto.Migration

  def change do
    alter table(:shift_closes) do
      add :petty_cash_counted, :decimal
      add :petty_cash_expected, :decimal
      add :petty_cash_variance, :decimal
      add :petty_cash_transfer, :decimal
      add :petty_cash_notes, :string
    end
  end
end

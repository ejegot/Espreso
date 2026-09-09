defmodule Espreso.Repo.Migrations.RenameOnlineWalletToPaymentIntent do
  use Ecto.Migration

  def change do
    rename table(:orders), :online_wallet, to: :payment_intent
  end
end

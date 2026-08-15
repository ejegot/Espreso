defmodule Espreso.Repo do
  use Ecto.Repo,
    otp_app: :espreso,
    adapter: Ecto.Adapters.Postgres
end

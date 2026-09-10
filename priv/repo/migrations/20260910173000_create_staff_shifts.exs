defmodule Espreso.Repo.Migrations.CreateStaffShifts do
  use Ecto.Migration

  def change do
    create table(:staff_shifts) do
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :end_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:staff_shifts, [:user_id])

    # One open staff shift per employee (ended_at IS NULL means open).
    create unique_index(:staff_shifts, [:user_id],
             where: "ended_at IS NULL",
             name: :staff_shifts_one_open_per_user
           )
  end
end

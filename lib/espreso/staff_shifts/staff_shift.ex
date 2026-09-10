defmodule Espreso.StaffShifts.StaffShift do
  @moduledoc """
  Employee attendance shift (Time In / Time Out).

  Separate from shop-day `Espreso.Shifts.ShiftClose`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Accounts.User

  @end_reasons ~w(logout auto_close)

  schema "staff_shifts" do
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :end_reason, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def end_reasons, do: @end_reasons

  @doc """
  Changeset for opening a new staff shift (Time In).
  """
  def open_changeset(shift, attrs) do
    shift
    |> cast(attrs, [:user_id, :started_at])
    |> validate_required([:user_id, :started_at])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id, name: :staff_shifts_one_open_per_user)
  end

  @doc """
  Changeset for ending an open staff shift (Time Out or auto-close).
  """
  def close_changeset(shift, attrs) do
    shift
    |> cast(attrs, [:ended_at, :end_reason])
    |> validate_required([:ended_at, :end_reason])
    |> validate_inclusion(:end_reason, @end_reasons)
  end
end

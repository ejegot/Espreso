defmodule Espreso.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "customers" do
    field :phone_e164, :string
    field :name, :string
    field :points_balance, :integer, default: 0
    field :spend_remainder_centavos, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:phone_e164, :name, :points_balance, :spend_remainder_centavos])
    |> update_change(:name, &blank_to_nil/1)
    |> validate_required([:phone_e164])
    |> validate_format(:phone_e164, ~r/^\+639\d{9}$/,
      message: "must be a Philippine mobile (+63)"
    )
    |> validate_length(:name, min: 2, max: 60)
    |> validate_number(:points_balance, greater_than_or_equal_to: 0)
    |> validate_number(:spend_remainder_centavos,
      greater_than_or_equal_to: 0,
      less_than: 20_000
    )
    |> unique_constraint(:phone_e164)
    |> check_constraint(:points_balance, name: :customers_points_balance_nonnegative)
    |> check_constraint(:spend_remainder_centavos, name: :customers_spend_remainder_range)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

defmodule Espreso.Customers do
  @moduledoc """
  Café customer identity for loyalty (phone-based, no login).
  """

  import Ecto.Query

  alias Espreso.Customers.Customer
  alias Espreso.Repo

  @doc """
  Normalizes common Philippine mobile formats to E.164 `+639XXXXXXXXX`.

  Accepts `09…`, `9…`, `639…`, and `+639…`. Returns `{:error, :invalid_phone}` otherwise.
  """
  def normalize_phone(nil), do: {:error, :invalid_phone}

  def normalize_phone(raw) when is_binary(raw) do
    digits = raw |> String.trim() |> String.replace(~r/[^\d+]/, "")

    national =
      cond do
        String.match?(digits, ~r/^\+639\d{9}$/) -> String.slice(digits, 3, 10)
        String.match?(digits, ~r/^639\d{9}$/) -> String.slice(digits, 2, 10)
        String.match?(digits, ~r/^09\d{9}$/) -> String.slice(digits, 1, 10)
        String.match?(digits, ~r/^9\d{9}$/) -> digits
        true -> nil
      end

    case national do
      <<?9, _::binary-size(9)>> -> {:ok, "+63" <> national}
      _ -> {:error, :invalid_phone}
    end
  end

  def normalize_phone(_), do: {:error, :invalid_phone}

  @doc """
  Finds a customer by raw or normalized phone input.
  """
  def get_by_phone(raw) do
    with {:ok, phone} <- normalize_phone(raw) do
      case Repo.get_by(Customer, phone_e164: phone) do
        %Customer{} = customer -> {:ok, customer}
        nil -> {:error, :not_found}
      end
    end
  end

  def get_customer(id) when is_integer(id), do: Repo.get(Customer, id)

  @doc """
  Finds an existing customer by phone or creates one.

  Optional `:name` is stored when creating; when finding, a blank name on the
  existing record may be filled if a non-blank name is provided.
  """
  def find_or_create_by_phone(raw, attrs \\ %{}) when is_map(attrs) do
    with {:ok, phone} <- normalize_phone(raw) do
      name = optional_name(attrs)

      case Repo.get_by(Customer, phone_e164: phone) do
        %Customer{} = customer ->
          maybe_fill_name(customer, name)

        nil ->
          %Customer{}
          |> Customer.changeset(%{
            phone_e164: phone,
            name: name,
            points_balance: 0,
            spend_remainder_centavos: 0
          })
          |> Repo.insert()
          |> case do
            {:ok, customer} ->
              {:ok, customer}

            {:error, %Ecto.Changeset{} = changeset} ->
              if phone_taken?(changeset) do
                case Repo.get_by(Customer, phone_e164: phone) do
                  %Customer{} = customer -> maybe_fill_name(customer, name)
                  nil -> {:error, changeset}
                end
              else
                {:error, changeset}
              end
          end
      end
    end
  end

  defp maybe_fill_name(%Customer{name: existing} = customer, name)
       when is_binary(name) and (is_nil(existing) or existing == "") do
    customer
    |> Customer.changeset(%{name: name})
    |> Repo.update()
  end

  defp maybe_fill_name(customer, _), do: {:ok, customer}

  defp optional_name(attrs) do
    case Map.get(attrs, :name) || Map.get(attrs, "name") do
      nil ->
        nil

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp phone_taken?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:phone_e164, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  @doc false
  def lock_customer!(id) when is_integer(id) do
    Customer
    |> where([c], c.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end
end

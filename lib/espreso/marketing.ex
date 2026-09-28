defmodule Espreso.Marketing do
  @moduledoc """
  Waitlist / shop-setup requests for Espreso (not CoffeeSpot guest contact).
  """

  require Logger

  alias Espreso.Marketing.ShopRequest
  alias Espreso.Repo

  def change_shop_request(attrs \\ %{}) do
    ShopRequest.changeset(%ShopRequest{}, attrs)
  end

  @doc """
  Persists a café setup request.

  A filled honeypot (`company_url`) is treated as success without writing a row.
  """
  def create_shop_request(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    if present?(attrs["company_url"]) do
      {:ok, :ignored}
    else
      changeset = ShopRequest.changeset(%ShopRequest{}, attrs)

      case Repo.insert(changeset) do
        {:ok, request} ->
          Logger.info(
            "shop_request id=#{request.id} cafe=#{request.cafe_name} city=#{request.city}"
          )

          {:ok, request}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}
      end
    end
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end

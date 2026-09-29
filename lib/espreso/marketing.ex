defmodule Espreso.Marketing do
  @moduledoc """
  Waitlist / shop-setup requests for Espreso (not CoffeeSpot guest contact).
  """

  import Ecto.Query

  require Logger

  alias Espreso.Accounts.User
  alias Espreso.Marketing.ShopRequest
  alias Espreso.Repo
  alias Espreso.Tenancy
  alias Espreso.Tenancy.Tenant

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

  def list_pending_shop_requests do
    ShopRequest
    |> where([r], r.status == "pending")
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
  end

  def get_shop_request(id) when is_integer(id), do: Repo.get(ShopRequest, id)

  def get_shop_request(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> get_shop_request(int)
      _ -> nil
    end
  end

  def get_shop_request(_), do: nil

  def dismiss_as(%User{} = actor, %ShopRequest{} = request) do
    with true <- Tenancy.platform_owner?(actor),
         "pending" <- request.status do
      request
      |> ShopRequest.status_changeset(%{status: "dismissed"})
      |> Repo.update()
    else
      false -> {:error, :unauthorized}
      status when is_binary(status) -> {:error, :not_pending}
    end
  end

  def dismiss_as(_, _), do: {:error, :unauthorized}

  def mark_opened!(%ShopRequest{} = request, %Tenant{} = tenant) do
    request
    |> ShopRequest.status_changeset(%{
      status: "opened",
      tenant_id: tenant.id,
      opened_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> case do
      {:ok, request} -> request
      {:error, changeset} -> Repo.rollback(changeset)
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

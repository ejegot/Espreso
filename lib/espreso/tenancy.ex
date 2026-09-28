defmodule Espreso.Tenancy do
  @moduledoc """
  CoffeeSpot Lilac is tenant + main branch. Queries and inserts attach those IDs.

  No Add Branch / Add Tenant UI here — only the lockbox so a second shop cannot
  share Lilac rows by accident.
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Espreso.Repo
  alias Espreso.Tenancy.{Branch, Tenant}

  @coffeespot_slug "coffeespot"
  @lilac_slug "lilac"
  @lilac_code "lilac"

  def coffeespot_slug, do: @coffeespot_slug
  def lilac_slug, do: @lilac_slug

  @doc """
  Idempotent CoffeeSpot + Lilac (main). Safe in tests and after migrate.
  """
  def ensure_coffeespot_lilac! do
    tenant = ensure_tenant!()
    branch = ensure_lilac_branch!(tenant)
    %{tenant: tenant, branch: branch}
  end

  def default_tenant_id do
    ensure_coffeespot_lilac!().tenant.id
  end

  def default_branch_id do
    ensure_coffeespot_lilac!().branch.id
  end

  def coffeespot_lilac_ids do
    %{tenant: tenant, branch: branch} = ensure_coffeespot_lilac!()
    %{tenant_id: tenant.id, branch_id: branch.id}
  end

  def scope_to_tenant(query, nil), do: query

  def scope_to_tenant(query, tenant_id) when is_integer(tenant_id) do
    from(x in query, where: x.tenant_id == ^tenant_id)
  end

  def scope_to_tenant(query, %{tenant_id: tenant_id}) when is_integer(tenant_id) do
    scope_to_tenant(query, tenant_id)
  end

  def scope_to_tenant(query, %{id: tenant_id}) when is_integer(tenant_id) do
    scope_to_tenant(query, tenant_id)
  end

  def scope_to_tenant(query, _), do: query

  def scope_to_branch(query, nil), do: query

  def scope_to_branch(query, branch_id) when is_integer(branch_id) do
    from(x in query, where: x.branch_id == ^branch_id)
  end

  def scope_to_branch(query, %{branch_id: branch_id}) when is_integer(branch_id) do
    scope_to_branch(query, branch_id)
  end

  def scope_to_branch(query, %{id: branch_id}) when is_integer(branch_id) do
    scope_to_branch(query, branch_id)
  end

  def scope_to_branch(query, _), do: query

  @doc """
  Scopes to the current staff branch, or Lilac when none is given.
  """
  def scope_to_branch(query) do
    scope_to_branch(query, default_branch_id())
  end

  @doc """
  Puts Lilac IDs when tenant_id / branch_id are missing. Existing values win.
  """
  def put_ids(%Ecto.Changeset{} = changeset) do
    ids = coffeespot_lilac_ids()

    changeset
    |> maybe_put(:tenant_id, ids.tenant_id)
    |> maybe_put(:branch_id, ids.branch_id)
  end

  def put_ids(attrs) when is_map(attrs) do
    ids = coffeespot_lilac_ids()
    attrs = stringify_keys(attrs)

    attrs
    |> Map.put_new("tenant_id", ids.tenant_id)
    |> Map.put_new("branch_id", ids.branch_id)
  end

  def ids_from(%{tenant_id: tenant_id, branch_id: branch_id})
      when is_integer(tenant_id) and is_integer(branch_id) do
    %{tenant_id: tenant_id, branch_id: branch_id}
  end

  def ids_from(_), do: coffeespot_lilac_ids()

  @doc false
  def insert_tenant!(attrs) when is_map(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert!()
  end

  @doc false
  def insert_branch!(%Tenant{} = tenant, attrs) when is_map(attrs) do
    attrs = Map.put(attrs, :tenant_id, tenant.id)

    %Branch{}
    |> Branch.changeset(attrs)
    |> Repo.insert!()
  end

  defp ensure_tenant! do
    case Repo.get_by(Tenant, slug: @coffeespot_slug) do
      %Tenant{} = tenant ->
        tenant

      nil ->
        %Tenant{}
        |> Tenant.changeset(%{
          name: "CoffeeSpot",
          slug: @coffeespot_slug,
          guest_brand_name: "CoffeeSpot"
        })
        |> Repo.insert()
        |> case do
          {:ok, tenant} -> tenant
          {:error, _} -> Repo.get_by!(Tenant, slug: @coffeespot_slug)
        end
    end
  end

  defp ensure_lilac_branch!(%Tenant{} = tenant) do
    case Repo.get_by(Branch, tenant_id: tenant.id, slug: @lilac_slug) do
      %Branch{} = branch ->
        branch

      nil ->
        %Branch{}
        |> Branch.changeset(%{
          name: "Lilac",
          slug: @lilac_slug,
          code: @lilac_code,
          address: "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811",
          main: true,
          tenant_id: tenant.id
        })
        |> Repo.insert()
        |> case do
          {:ok, branch} -> branch
          {:error, _} -> Repo.get_by!(Branch, tenant_id: tenant.id, slug: @lilac_slug)
        end
    end
  end

  defp maybe_put(changeset, field, value) do
    case get_field(changeset, field) do
      id when is_integer(id) and id > 0 -> changeset
      _ -> put_change(changeset, field, value)
    end
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end

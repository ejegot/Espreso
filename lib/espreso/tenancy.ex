defmodule Espreso.Tenancy do
  @moduledoc """
  CoffeeSpot Lilac is the first tenant + main branch.

  Request-scoped `put_context/1` is the working shop (staff session or guest slug).
  Inserts and list queries follow that context, not always Lilac.
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Espreso.Repo
  alias Espreso.Tenancy.{Branch, Tenant}

  @coffeespot_slug "coffeespot"
  @lilac_slug "lilac"
  @lilac_code "lilac"
  @context_key :espreso_tenancy

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

  @doc """
  Sets the working tenant/branch for this process (one HTTP/LiveView request).
  """
  def put_context(%{tenant_id: tenant_id, branch_id: branch_id})
      when is_integer(tenant_id) and is_integer(branch_id) do
    Process.put(@context_key, %{tenant_id: tenant_id, branch_id: branch_id})
    :ok
  end

  def put_context(_), do: :ok

  def current_ids do
    case Process.get(@context_key) do
      %{tenant_id: tenant_id, branch_id: branch_id}
      when is_integer(tenant_id) and is_integer(branch_id) ->
        %{tenant_id: tenant_id, branch_id: branch_id}

      _ ->
        coffeespot_lilac_ids()
    end
  end

  def current_tenant_id, do: current_ids().tenant_id
  def current_branch_id, do: current_ids().branch_id

  def current_branch do
    case Repo.get(Branch, current_branch_id()) do
      %Branch{} = branch -> branch
      nil -> ensure_coffeespot_lilac!().branch
    end
  end

  def get_branch(id) when is_integer(id), do: Repo.get(Branch, id)

  def get_tenant(id) when is_integer(id), do: Repo.get(Tenant, id)

  def get_tenant_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Tenant, slug: String.downcase(String.trim(slug)))
  end

  def get_tenant_by_slug(_), do: nil

  def list_tenants do
    Tenant
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  @doc """
  CoffeeSpot owner only — not a renter café owner.
  """
  def platform_owner?(%{role: "owner", active: true, tenant_id: tenant_id})
      when is_integer(tenant_id) do
    coffeespot_tenant?(tenant_id)
  end

  def platform_owner?(_), do: false

  def coffeespot_tenant?(tenant_id) when is_integer(tenant_id) do
    case Repo.get(Tenant, tenant_id) do
      %Tenant{slug: @coffeespot_slug} -> true
      _ -> false
    end
  end

  def coffeespot_tenant?(_), do: false

  def coffeespot_guest?, do: coffeespot_tenant?(current_tenant_id())

  def list_branches(tenant_id) when is_integer(tenant_id) do
    Branch
    |> where([b], b.tenant_id == ^tenant_id)
    |> order_by([b], desc: b.main, asc: b.name)
    |> Repo.all()
  end

  def get_branch_by_slug(tenant_id, slug) when is_integer(tenant_id) and is_binary(slug) do
    Repo.get_by(Branch, tenant_id: tenant_id, slug: String.downcase(String.trim(slug)))
  end

  def switcher?(%{role: role, active: true}) when role in ~w(owner manager), do: true
  def switcher?(_), do: false

  @doc """
  Working branch for staff: home branch, unless owner/manager picked another
  shop in the same tenant.
  """
  def resolve_working_branch_id(user, session_branch_id)

  def resolve_working_branch_id(%{branch_id: home_id, tenant_id: tenant_id} = user, session_id)
      when is_integer(home_id) do
    session_id = parse_id(session_id)

    cond do
      not switcher?(user) ->
        home_id

      is_integer(session_id) ->
        case get_branch(session_id) do
          %Branch{tenant_id: ^tenant_id} -> session_id
          _ -> home_id
        end

      true ->
        home_id
    end
  end

  def resolve_working_branch_id(_, _), do: default_branch_id()

  def put_guest_branch(slug) when is_binary(slug) do
    %{tenant: tenant} = ensure_coffeespot_lilac!()

    case get_branch_by_slug(tenant.id, slug) do
      %Branch{} = branch ->
        put_context(%{tenant_id: branch.tenant_id, branch_id: branch.id})
        {:ok, branch}

      nil ->
        put_lilac_context()
        {:error, :not_found}
    end
  end

  def put_guest_branch(_), do: put_lilac_context()

  def put_guest_tenant(slug) when is_binary(slug) do
    case get_tenant_by_slug(slug) do
      %Tenant{} = tenant ->
        case main_branch(tenant.id) do
          %Branch{} = branch ->
            put_context(%{tenant_id: tenant.id, branch_id: branch.id})
            {:ok, tenant}

          nil ->
            put_lilac_context()
            {:error, :not_found}
        end

      nil ->
        put_lilac_context()
        {:error, :not_found}
    end
  end

  def put_guest_tenant(_), do: put_lilac_context()

  def put_guest_tenant_branch(tenant_slug, branch_slug)
      when is_binary(tenant_slug) and is_binary(branch_slug) do
    case get_tenant_by_slug(tenant_slug) do
      %Tenant{} = tenant ->
        case get_branch_by_slug(tenant.id, branch_slug) do
          %Branch{} = branch ->
            put_context(%{tenant_id: branch.tenant_id, branch_id: branch.id})
            {:ok, branch}

          nil ->
            put_lilac_context()
            {:error, :not_found}
        end

      nil ->
        put_lilac_context()
        {:error, :not_found}
    end
  end

  def put_guest_tenant_branch(_, _), do: put_lilac_context()

  def main_branch(tenant_id) when is_integer(tenant_id) do
    Repo.get_by(Branch, tenant_id: tenant_id, main: true)
  end

  def put_lilac_context do
    put_context(coffeespot_lilac_ids())
  end

  def put_staff_context(user, session_branch_id) do
    branch_id = resolve_working_branch_id(user, session_branch_id)
    tenant_id = user.tenant_id || default_tenant_id()
    put_context(%{tenant_id: tenant_id, branch_id: branch_id})
    branch_id
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

  def scope_to_tenant(query) do
    scope_to_tenant(query, current_tenant_id())
  end

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
    scope_to_branch(query, current_branch_id())
  end

  @doc """
  Puts working-shop IDs when tenant_id / branch_id are missing. Existing values win.
  """
  def put_ids(%Ecto.Changeset{} = changeset) do
    ids = current_ids()

    changeset
    |> maybe_put(:tenant_id, ids.tenant_id)
    |> maybe_put(:branch_id, ids.branch_id)
  end

  def put_ids(attrs) when is_map(attrs) do
    ids = current_ids()
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

  defp parse_id(id) when is_integer(id) and id > 0, do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end

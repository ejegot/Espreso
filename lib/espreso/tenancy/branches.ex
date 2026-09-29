defmodule Espreso.Tenancy.Branches do
  @moduledoc """
  Owner creates extra CoffeeSpot shops. Catalog and staff are created on the branch.
  """

  import Ecto.Query

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.BusinessSettings
  alias Espreso.BusinessSettings.Setting
  alias Espreso.Repo
  alias Espreso.Tenancy
  alias Espreso.Tenancy.{Branch, Tenant}

  def create_as(%User{} = actor, attrs) when is_map(attrs) do
    with :ok <- Authorization.authorize(actor, :user_management),
         tenant_id when is_integer(tenant_id) <- actor.tenant_id || Tenancy.default_tenant_id(),
         {:ok, name} <- fetch_name(attrs),
         slug <- unique_slug(tenant_id, slugify(name)),
         code <- unique_code(slug) do
      address = optional_address(attrs)

      Repo.transaction(fn ->
        branch =
          %Branch{}
          |> Branch.changeset(%{
            name: name,
            slug: slug,
            code: code,
            address: address,
            main: false,
            tenant_id: tenant_id
          })
          |> Repo.insert()
          |> case do
            {:ok, branch} -> branch
            {:error, changeset} -> Repo.rollback(changeset)
          end

        copy_settings!(branch, address)
        branch
      end)
    else
      nil -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_as(_, _), do: {:error, :unauthorized}

  def guest_menu_path(%Branch{} = branch) do
    tenant = Repo.get!(Tenant, branch.tenant_id)

    cond do
      tenant.slug == Tenancy.coffeespot_slug() and branch.slug == Tenancy.lilac_slug() ->
        "/menu"

      tenant.slug == Tenancy.coffeespot_slug() ->
        "/b/#{branch.slug}/menu"

      branch.main ->
        "/t/#{tenant.slug}/menu"

      true ->
        "/t/#{tenant.slug}/b/#{branch.slug}/menu"
    end
  end

  def guest_login_path(%Branch{} = branch) do
    tenant = Repo.get!(Tenant, branch.tenant_id)

    if tenant.slug == Tenancy.coffeespot_slug() do
      "/login"
    else
      "/t/#{tenant.slug}/login"
    end
  end

  defp fetch_name(attrs) do
    name =
      (Map.get(attrs, :name) || Map.get(attrs, "name") || "")
      |> to_string()
      |> String.trim()

    cond do
      name == "" -> {:error, :invalid_name}
      String.length(name) < 2 -> {:error, :invalid_name}
      String.length(name) > 80 -> {:error, :invalid_name}
      true -> {:ok, name}
    end
  end

  defp optional_address(attrs) do
    case Map.get(attrs, :address) || Map.get(attrs, "address") do
      nil ->
        nil

      value ->
        case String.trim(to_string(value)) do
          "" -> nil
          trimmed -> trimmed
        end
    end
  end

  defp slugify(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 40)

    if slug == "" or String.length(slug) < 2, do: "shop", else: slug
  end

  defp unique_slug(tenant_id, base) do
    Enum.reduce_while(0..30, base, fn n, _acc ->
      slug = if n == 0, do: base, else: String.slice("#{base}-#{n}", 0, 40)

      exists? =
        Repo.exists?(from b in Branch, where: b.tenant_id == ^tenant_id and b.slug == ^slug)

      if exists?, do: {:cont, slug}, else: {:halt, slug}
    end)
  end

  defp unique_code(slug) do
    base = slug |> String.replace("-", "") |> String.slice(0, 12)

    Enum.reduce_while(0..40, base, fn n, _acc ->
      code =
        if n == 0 do
          base
        else
          String.slice("#{base}#{n}", 0, 20)
        end

      exists? = Repo.exists?(from b in Branch, where: b.code == ^code)
      if exists?, do: {:cont, code}, else: {:halt, code}
    end)
  end

  defp copy_settings!(%Branch{} = branch, address) do
    source = source_settings()
    tenant = Repo.get!(Tenant, branch.tenant_id)

    attrs = %{
      business_name: source.business_name || tenant.guest_brand_name,
      address: address || source.address || branch.name,
      phone: source.phone,
      email: source.email,
      hours_lines: source.hours_lines,
      instagram_url: source.instagram_url,
      facebook_url: source.facebook_url,
      tiktok_url: source.tiktok_url,
      payments_mode: source.payments_mode || "counter_only",
      gcash_qrph_path: nil,
      maya_qrph_path: nil,
      tenant_id: branch.tenant_id,
      branch_id: branch.id
    }

    %Setting{}
    |> Setting.changeset(attrs)
    |> Repo.insert!()
  end

  defp source_settings do
    BusinessSettings.get_for_branch(Tenancy.current_branch_id())
  end
end

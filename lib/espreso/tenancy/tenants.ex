defmodule Espreso.Tenancy.Tenants do
  @moduledoc """
  Platform (CoffeeSpot owner) creates a renter café: tenant, main branch, settings, owner PIN.
  """

  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Accounts.User
  alias Espreso.BusinessSettings.Setting
  alias Espreso.Repo
  alias Espreso.Tenancy
  alias Espreso.Tenancy.{Branch, Tenant}

  @reserved_slugs ~w(
    coffeespot lilac admin staff login setup register product menu about contact
    session api t b media
  )

  def create_as(%User{} = actor, attrs) when is_map(attrs) do
    prev = Process.get(:espreso_tenancy)

    with true <- Tenancy.platform_owner?(actor),
         {:ok, name} <- fetch_name(attrs),
         {:ok, owner_name} <- fetch_owner_name(attrs),
         {:ok, pin} <- fetch_pin(attrs) do
      slug = unique_slug(slugify(name))
      address = optional_address(attrs) || name

      result =
        Repo.transaction(fn ->
          tenant =
            insert!(%Tenant{}, %{
              name: name,
              slug: slug,
              guest_brand_name: name
            })

          branch =
            insert!(%Branch{}, %{
              name: name,
              slug: "main",
              code: unique_code(slug),
              address: address,
              main: true,
              tenant_id: tenant.id
            })

          insert_settings!(tenant, branch, address)

          Tenancy.put_context(%{tenant_id: tenant.id, branch_id: branch.id})

          owner =
            case Accounts.register_user(%{
                   name: owner_name,
                   email: placeholder_email(slug),
                   password: placeholder_password(),
                   role: "owner",
                   tenant_id: tenant.id,
                   branch_id: branch.id
                 }) do
              {:ok, user} ->
                case Accounts.set_pin(user, pin) do
                  {:ok, user} -> user
                  {:error, reason} -> Repo.rollback(reason)
                end

              {:error, reason} ->
                Repo.rollback(reason)
            end

          %{tenant: tenant, branch: branch, owner: owner}
        end)

      restore_context(prev)
      result
    else
      false ->
        restore_context(prev)
        {:error, :unauthorized}

      {:error, reason} ->
        restore_context(prev)
        {:error, reason}
    end
  end

  def create_as(_, _), do: {:error, :unauthorized}

  def guest_menu_path(%Tenant{slug: slug}) do
    if slug == Tenancy.coffeespot_slug(), do: "/menu", else: "/t/#{slug}/menu"
  end

  def guest_login_path(%Tenant{slug: slug}) do
    if slug == Tenancy.coffeespot_slug(), do: "/login", else: "/t/#{slug}/login"
  end

  defp insert!(schema, attrs) do
    schema
    |> changeset_for(schema, attrs)
    |> Repo.insert()
    |> case do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp changeset_for(%Tenant{}, _, attrs), do: Tenant.changeset(%Tenant{}, attrs)
  defp changeset_for(%Branch{}, _, attrs), do: Branch.changeset(%Branch{}, attrs)

  defp insert_settings!(%Tenant{} = tenant, %Branch{} = branch, address) do
    attrs = %{
      business_name: tenant.guest_brand_name,
      address: address,
      phone: "+63 000 0000",
      email: "hello@internal.espreso.invalid",
      hours_lines: ["Daily · 8:00 AM – 8:00 PM"],
      instagram_url: "https://www.instagram.com/",
      facebook_url: "https://www.facebook.com/",
      tiktok_url: "https://www.tiktok.com/",
      payments_mode: "counter_only",
      tenant_id: tenant.id,
      branch_id: branch.id
    }

    %Setting{}
    |> Setting.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, setting} -> setting
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp restore_context(%{tenant_id: tenant_id, branch_id: branch_id})
       when is_integer(tenant_id) and is_integer(branch_id) do
    Tenancy.put_context(%{tenant_id: tenant_id, branch_id: branch_id})
  end

  defp restore_context(_) do
    Tenancy.put_lilac_context()
  end

  defp fetch_name(attrs) do
    fetch_label(attrs, [:name, "name"], :invalid_name)
  end

  defp fetch_owner_name(attrs) do
    fetch_label(attrs, [:owner_name, "owner_name"], :invalid_owner_name)
  end

  defp fetch_label(attrs, keys, error) do
    value =
      Enum.find_value(keys, fn key ->
        case Map.get(attrs, key) do
          nil -> nil
          v -> v
        end
      end)
      |> to_string()
      |> String.trim()

    cond do
      value == "" -> {:error, error}
      String.length(value) < 2 -> {:error, error}
      String.length(value) > 80 -> {:error, error}
      true -> {:ok, value}
    end
  end

  defp fetch_pin(attrs) do
    pin = attrs |> attr(:pin) |> to_string() |> String.trim()
    confirm = attrs |> attr(:pin_confirmation) |> to_string() |> String.trim()
    confirm = if confirm == "", do: pin, else: confirm

    cond do
      pin != confirm -> {:error, :pin_mismatch}
      not Regex.match?(~r/^\d{4,6}$/, pin) -> {:error, :invalid_pin_format}
      true -> {:ok, pin}
    end
  end

  defp attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
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

    if slug == "" or String.length(slug) < 2, do: "cafe", else: slug
  end

  defp unique_slug(base) do
    base = if reserved_slug?(base), do: "#{base}-cafe", else: base

    Enum.reduce_while(0..40, base, fn n, _acc ->
      slug = if n == 0, do: base, else: String.slice("#{base}-#{n}", 0, 40)

      exists? = Repo.exists?(from t in Tenant, where: t.slug == ^slug)

      if exists? or reserved_slug?(slug) do
        {:cont, slug}
      else
        {:halt, slug}
      end
    end)
  end

  defp reserved_slug?(slug), do: slug in @reserved_slugs

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

  defp placeholder_email(slug) do
    token = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    "owner.#{slug}.#{token}@internal.espreso.invalid"
  end

  defp placeholder_password do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end
end

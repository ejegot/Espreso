defmodule Espreso.BusinessSettings do
  @moduledoc """
  Owner-managed shop contact, hours, and social links (one row per branch).
  """

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.BusinessSettings.Setting
  alias Espreso.Repo
  alias Espreso.Tenancy

  @payments_modes ~w(paymongo qrph_manual counter_only)

  @defaults %{
    business_name: "CoffeeSpot",
    address: "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811",
    phone: "+639566728906",
    email: "elilaicorp.ph@gmail.com",
    hours_lines: [
      "Sun–Wed · 11:00 AM – 11:00 PM",
      "Thu · 11:00 AM – 12:00 AM",
      "Fri–Sat · 11:00 AM – 2:00 AM",
      "Holiday hours on Instagram"
    ],
    instagram_url: "https://www.instagram.com/coffeespot_lilac.marikina/",
    facebook_url: "https://www.facebook.com/profile.php?id=61572602608495",
    tiktok_url: "https://www.tiktok.com/@coffeespotlilac_",
    payments_mode: "counter_only",
    gcash_qrph_path: nil,
    maya_qrph_path: nil,
    singleton_key: 1
  }

  @doc """
  Returns settings for Lilac (current live shop), creating defaults if missing.
  """
  def get do
    get_for_branch(Tenancy.default_branch_id())
  end

  def get_for_branch(branch_id) when is_integer(branch_id) do
    case Repo.get_by(Setting, branch_id: branch_id) do
      %Setting{} = setting -> setting
      nil -> ensure_defaults_for_branch!(branch_id)
    end
  end

  @doc """
  Idempotent insert of the CoffeeSpot Lilac settings row.
  """
  def ensure_defaults! do
    get_for_branch(Tenancy.default_branch_id())
  end

  defp ensure_defaults_for_branch!(branch_id) do
    %{tenant: tenant, branch: branch} = Tenancy.ensure_coffeespot_lilac!()

    {tenant_id, branch_id} =
      if branch.id == branch_id do
        {tenant.id, branch.id}
      else
        found = Repo.get!(Espreso.Tenancy.Branch, branch_id)
        {found.tenant_id, found.id}
      end

    attrs =
      @defaults
      |> Map.put(:tenant_id, tenant_id)
      |> Map.put(:branch_id, branch_id)

    %Setting{}
    |> Setting.changeset(attrs)
    |> Repo.insert!()
  end

  def defaults, do: @defaults

  def payments_modes, do: @payments_modes

  @doc """
  Returns the configured payments mode: `paymongo`, `qrph_manual`, or `counter_only`.
  """
  def payments_mode do
    get().payments_mode || "counter_only"
  end

  @doc """
  Payment-related settings for checkout and staff flows.
  """
  def payment_config do
    setting = get()

    %{
      payments_mode: setting.payments_mode || "counter_only",
      gcash_qrph_path: setting.gcash_qrph_path,
      maya_qrph_path: setting.maya_qrph_path
    }
  end

  def qrph_manual?, do: payments_mode() == "qrph_manual"
  def counter_only?, do: payments_mode() == "counter_only"
  def paymongo?, do: payments_mode() == "paymongo"

  def change(%Setting{} = setting, attrs \\ %{}) do
    setting
    |> with_hours_text()
    |> Setting.changeset(attrs)
  end

  @doc """
  Updates settings when the actor has `:business_settings` permission.
  """
  def update_as(%User{} = actor, attrs) when is_map(attrs) do
    with :ok <- Authorization.authorize(actor, :business_settings) do
      get()
      |> Setting.changeset(normalize_attrs(attrs))
      |> Repo.update()
    end
  end

  defp with_hours_text(%Setting{} = setting) do
    %{setting | hours_text: Enum.join(setting.hours_lines || [], "\n")}
  end

  defp normalize_attrs(attrs) do
    # Allow form maps with string keys for hours_text.
    attrs
  end
end

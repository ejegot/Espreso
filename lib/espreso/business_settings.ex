defmodule Espreso.BusinessSettings do
  @moduledoc """
  Owner-managed shop contact, hours, and social links (one row per branch).
  """

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.BusinessSettings.Setting
  alias Espreso.BusinessSettings.GcashQr
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
    get_for_branch(Tenancy.current_branch_id())
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
    get_for_branch(Tenancy.current_branch_id())
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
    gcash_qr = get_gcash_qr()

    gcash_qrph_path =
      case gcash_qr do
        nil -> setting.gcash_qrph_path
        qr -> "/media/business/gcash-qr?v=#{DateTime.to_unix(qr.updated_at)}"
      end

    %{
      payments_mode: setting.payments_mode || "counter_only",
      gcash_qrph_path: gcash_qrph_path,
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

  @gcash_qr_max_bytes 2_000_000
  @gcash_qr_types ["image/jpeg", "image/png", "image/webp"]

  def get_gcash_qr do
    Repo.get_by(GcashQr, branch_id: Tenancy.current_branch_id())
  end

  def save_gcash_qr_as(%User{} = actor, binary, content_type)
      when is_binary(binary) and is_binary(content_type) do
    with :ok <- Authorization.authorize(actor, :business_settings),
         :ok <- validate_gcash_qr(binary, content_type) do
      branch_id = Tenancy.current_branch_id()
      attrs = %{branch_id: branch_id, data: binary, content_type: content_type}

      case get_gcash_qr() do
        nil ->
          %GcashQr{}
          |> GcashQr.changeset(attrs)
          |> Repo.insert()

        qr ->
          qr
          |> GcashQr.changeset(attrs)
          |> Repo.update()
      end
    end
  end

  def save_gcash_qr_as(_, _, _), do: {:error, :invalid_photo}

  defp validate_gcash_qr(binary, content_type) do
    cond do
      content_type not in @gcash_qr_types ->
        {:error, :invalid_photo}

      byte_size(binary) > @gcash_qr_max_bytes ->
        {:error, :photo_too_large}

      byte_size(binary) < 32 ->
        {:error, :invalid_photo}

      not valid_gcash_qr_signature?(binary, content_type) ->
        {:error, :invalid_photo}

      not valid_image_structure?(binary, content_type) ->
        {:error, :invalid_photo}

      true ->
        :ok
    end
  end

  defp valid_gcash_qr_signature?(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>, "image/png"),
    do: true

  defp valid_gcash_qr_signature?(<<255, 216, 255, _::binary>>, "image/jpeg"), do: true

  defp valid_gcash_qr_signature?(
         <<"RIFF", _size::little-32, "WEBP", _::binary>>,
         "image/webp"
       ),
       do: true

  defp valid_gcash_qr_signature?(_, _), do: false

  # Validate that the image binary actually contains valid image structure
  # beyond just the file signature. This prevents files with valid headers
  # but corrupted/invalid content from being accepted.
  defp valid_image_structure?(binary, "image/png") do
    # PNG files have specific structure: signature + chunks
    # At minimum, must have IHDR chunk after signature and IEND chunk at end
    case binary do
      <<137, 80, 78, 71, 13, 10, 26, 10, # PNG signature
        _::binary>> ->
        # Check for required IHDR and IEND chunks
        String.contains?(binary, <<"IHDR">>) and String.contains?(binary, <<"IEND">>)

      _ ->
        false
    end
  end

  defp valid_image_structure?(binary, "image/jpeg") do
    # JPEG must have minimal structure: SOI marker + segments + EOI marker
    # SOI (Start of Image) is FFD8, EOI (End of Image) is FFD9
    case binary do
      <<255, 216, # SOI marker
        _rest::binary>> ->
        # Check for EOI marker
        byte_size(binary) > 4 and String.contains?(binary, <<255, 217>>)

      _ ->
        false
    end
  end

  defp valid_image_structure?(binary, "image/webp") do
    # WebP must have: RIFF header + size + WEBP + VP8/VP8L/VP8X chunk
    case binary do
      <<"RIFF", # RIFF header
        _size::little-32,
        "WEBP", # WEBP signature
        rest::binary>> ->
        # Must have at least one valid VP8 chunk
        byte_size(rest) >= 10 and
          (String.starts_with?(rest, <<"VP8 ">>) or
             String.starts_with?(rest, <<"VP8L">>) or
             String.starts_with?(rest, <<"VP8X">>))

      _ ->
        false
    end
  end

  defp valid_image_structure?(_, _), do: false

  defp with_hours_text(%Setting{} = setting) do
    %{setting | hours_text: Enum.join(setting.hours_lines || [], "\n")}
  end

  defp normalize_attrs(attrs) do
    # Allow form maps with string keys for hours_text.
    attrs
  end
end

defmodule Espreso.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(barista manager owner)

  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :role, :string, default: "barista"
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :password, :role, :active])
    |> update_change(:email, &normalize_email/1)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :email, :role])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:email)
    |> maybe_clear_blank_password()
    |> maybe_validate_password(opts)
    |> maybe_hash_password(opts)
  end

  def update_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :password, :role, :active])
    |> update_change(:email, &normalize_email/1)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :email, :role])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:email)
    |> maybe_clear_blank_password()
    |> maybe_validate_password(Keyword.put(opts, :password_required, false))
    |> maybe_hash_password(opts)
  end

  def role_label("barista"), do: "Staff"
  def role_label("manager"), do: "Manager"
  def role_label("owner"), do: "Owner"
  def role_label(other), do: other

  def staff_role?(%__MODULE__{role: role}) when role in @roles, do: true
  def staff_role?(_), do: false

  def owner?(%__MODULE__{role: "owner", active: true}), do: true
  def owner?(_), do: false

  def can_access_orders?(user), do: Espreso.Accounts.Authorization.can?(user, :orders)

  def can_manage_users?(user), do: Espreso.Accounts.Authorization.can?(user, :user_management)

  def can?(user, permission), do: Espreso.Accounts.Authorization.can?(user, permission)

  defp maybe_clear_blank_password(changeset) do
    case get_change(changeset, :password) do
      pwd when pwd in [nil, ""] -> delete_change(changeset, :password)
      _ -> changeset
    end
  end

  defp maybe_validate_password(changeset, opts) do
    required? = Keyword.get(opts, :password_required, true)
    password = get_change(changeset, :password)

    cond do
      is_binary(password) ->
        changeset
        |> validate_required([:password])
        |> validate_length(:password, min: 8, max: 72)

      required? ->
        validate_required(changeset, [:password])

      true ->
        changeset
    end
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? and is_binary(password) and changeset.valid? do
      changeset
      |> put_change(:password_hash, Pbkdf2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end
end

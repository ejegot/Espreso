defmodule Espreso.Accounts do
  @moduledoc """
  Staff accounts, authentication, and role helpers.
  """

  import Ecto.Query

  alias Espreso.Repo
  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User

  def get_user(id) when is_integer(id), do: Repo.get(User, id)
  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()
    Repo.get_by(User, email: email)
  end

  def list_users do
    User
    |> order_by([u], asc: u.name)
    |> Repo.all()
  end

  def count_users do
    Repo.aggregate(User, :count, :id)
  end

  def first_user? do
    count_users() == 0
  end

  def registration_open? do
    # Public self-registration is always available for staff/manager.
    true
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Public self-registration.

  - First account becomes **owner**
  - Later accounts may choose **barista** or **manager** only (not owner)
  """
  def register_self(attrs) when is_map(attrs) do
    name = attrs["name"] || attrs[:name]
    email = attrs["email"] || attrs[:email]
    password = attrs["password"] || attrs[:password]
    requested_role = attrs["role"] || attrs[:role] || "barista"

    role =
      cond do
        first_user?() -> "owner"
        requested_role in ["barista", "manager"] -> requested_role
        true -> "barista"
      end

    register_user(%{
      "name" => name,
      "email" => email,
      "password" => password,
      "role" => role
    })
  end

  @doc """
  Creates the first owner when no users exist yet.
  """
  def register_first_owner(attrs) when is_map(attrs) do
    if first_user?() do
      register_self(Map.put(attrs, "role", "owner"))
    else
      {:error, :registration_closed}
    end
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a user when the actor has `:user_management` permission (owners).
  """
  def create_user_as(%User{} = actor, attrs) do
    with :ok <- Authorization.authorize(actor, :user_management) do
      register_user(attrs)
    end
  end

  @doc """
  Updates a user when the actor has `:user_management` permission.

  Actors cannot change their own role (blocks self escalation / demotion).
  """
  def update_user_as(%User{} = actor, %User{} = target, attrs) when is_map(attrs) do
    with :ok <- Authorization.authorize(actor, :user_management) do
      attrs = reject_self_role_change(actor, target, attrs)
      update_user(target, attrs)
    end
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, password_required: false)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.update_changeset(user, attrs, password_required: false, hash_password: false)
  end

  defp reject_self_role_change(%User{id: id}, %User{id: id}, attrs) do
    attrs
    |> Map.delete("role")
    |> Map.delete(:role)
  end

  defp reject_self_role_change(_actor, _target, attrs), do: attrs

  @doc """
  Authenticates by email and password.

  Returns `{:ok, user}` or `{:error, :invalid_credentials}` (same message for
  unknown email / wrong password / inactive).
  """
  def authenticate_user(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    cond do
      user && user.active && Pbkdf2.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        Pbkdf2.no_user_verify()
        {:error, :invalid_credentials}

      true ->
        Pbkdf2.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def authenticate_user(_, _), do: {:error, :invalid_credentials}

  def ensure_owner!(attrs) when is_map(attrs) do
    email = attrs[:email] || attrs["email"]

    case get_user_by_email(email) do
      %User{} = user ->
        {:ok, user}

      nil ->
        register_user(Map.put(attrs, :role, "owner"))
    end
  end
end

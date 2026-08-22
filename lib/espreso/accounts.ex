defmodule Espreso.Accounts do
  @moduledoc """
  Staff accounts, authentication, and role helpers.
  """

  import Ecto.Query

  alias Espreso.Repo
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

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, password_required: false)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.update_changeset(user, attrs, password_required: false, hash_password: false)
  end

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

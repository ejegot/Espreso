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
  Actors cannot deactivate themselves.
  Disabling or demoting an Owner is rejected when it would leave zero active Owners.
  """
  def update_user_as(%User{} = actor, %User{} = target, attrs) when is_map(attrs) do
    with :ok <- Authorization.authorize(actor, :user_management),
         attrs <- reject_self_role_change(actor, target, attrs),
         :ok <- reject_self_deactivation(actor, target, attrs) do
      update_user_as_safe(target, attrs)
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

  defp reject_self_deactivation(%User{id: id}, %User{id: id}, attrs) do
    if deactivating_attrs?(attrs) do
      {:error, :cannot_deactivate_self}
    else
      :ok
    end
  end

  defp reject_self_deactivation(_actor, _target, _attrs), do: :ok

  defp update_user_as_safe(%User{} = target, attrs) do
    result =
      Repo.transaction(fn ->
        # Lock active Owners in stable id order first to avoid deadlocks when two
        # Owners concurrently demote/disable each other.
        active_owners =
          User
          |> where([u], u.role == "owner" and u.active == true)
          |> order_by([u], asc: u.id)
          |> lock("FOR UPDATE")
          |> Repo.all()

        locked_target =
          case Enum.find(active_owners, &(&1.id == target.id)) do
            %User{} = owner ->
              owner

            nil ->
              User
              |> where([u], u.id == ^target.id)
              |> lock("FOR UPDATE")
              |> Repo.one!()
          end

        case reject_last_owner_violation(locked_target, attrs) do
          {:error, reason} ->
            Repo.rollback(reason)

          :ok ->
            case update_user(locked_target, attrs) do
              {:ok, user} -> user
              {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
            end
        end
      end)

    case result do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, :last_owner} -> {:error, :last_owner}
      {:error, :cannot_deactivate_self} -> {:error, :cannot_deactivate_self}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reject_last_owner_violation(%User{role: "owner", active: true} = target, attrs) do
    if owner_privilege_loss?(attrs) do
      other_active_owners =
        User
        |> where([u], u.role == "owner" and u.active == true and u.id != ^target.id)
        |> Repo.aggregate(:count, :id)

      if other_active_owners == 0 do
        {:error, :last_owner}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp reject_last_owner_violation(_target, _attrs), do: :ok

  defp owner_privilege_loss?(attrs) do
    deactivating_attrs?(attrs) or demoting_owner_attrs?(attrs)
  end

  defp deactivating_attrs?(attrs) do
    case attr(attrs, :active) do
      false -> true
      "false" -> true
      _ -> false
    end
  end

  defp demoting_owner_attrs?(attrs) do
    case attr(attrs, :role) do
      role when role in ["barista", "manager"] -> true
      _ -> false
    end
  end

  defp attr(attrs, key) when is_atom(key) do
    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, Atom.to_string(key)) -> Map.get(attrs, Atom.to_string(key))
      true -> nil
    end
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

  @pin_pattern ~r/^\d{4,6}$/
  @staff_roster_roles ~w(barista manager owner)

  @doc """
  Lists active staff for the employee login grid.

  Returns maps with `id`, `name`, and `role` only — no secrets.
  """
  def list_active_staff_for_roster do
    User
    |> where([u], u.active == true and u.role in ^@staff_roster_roles)
    |> order_by([u], asc: u.name)
    |> select([u], %{id: u.id, name: u.name, role: u.role})
    |> Repo.all()
  end

  @doc """
  Active staff with a PIN configured — for the tablet login grid.
  """
  def list_staff_for_pin_login do
    User
    |> where(
      [u],
      u.active == true and u.role in ^@staff_roster_roles and not is_nil(u.pin_hash) and
        u.pin_hash != ""
    )
    |> order_by([u], asc: u.name)
    |> select([u], %{id: u.id, name: u.name, role: u.role})
    |> Repo.all()
  end

  @doc """
  Returns whether the user has a PIN configured.
  """
  def pin_set?(%User{pin_hash: pin_hash}) when is_binary(pin_hash) and pin_hash != "",
    do: true

  def pin_set?(_), do: false

  @doc """
  Sets a 4–6 digit PIN for a user. Hashes with Pbkdf2.
  """
  def set_pin(%User{} = user, pin) when is_binary(pin) do
    with :ok <- validate_pin_format(pin) do
      user
      |> Ecto.Changeset.change(%{pin_hash: Pbkdf2.hash_pwd_salt(pin)})
      |> Repo.update()
    end
  end

  @doc """
  Clears a user's PIN.
  """
  def clear_pin(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{pin_hash: nil})
    |> Repo.update()
  end

  @doc """
  Sets a user's PIN when the actor has `:user_management` permission.
  """
  def set_pin_as(%User{} = actor, %User{} = target, pin) when is_binary(pin) do
    with :ok <- Authorization.authorize(actor, :user_management) do
      set_pin(target, pin)
    end
  end

  @doc """
  Clears a user's PIN when the actor has `:user_management` permission.
  """
  def clear_pin_as(%User{} = actor, %User{} = target) do
    with :ok <- Authorization.authorize(actor, :user_management) do
      clear_pin(target)
    end
  end

  @doc """
  Verifies a PIN for an active user.

  Returns `{:ok, user}` or `{:error, reason}` where reason is
  `:invalid_pin`, `:pin_not_set`, `:inactive`, or `:not_found`.
  """
  def verify_pin(%User{id: id}, pin) when is_binary(pin), do: verify_pin(id, pin)

  def verify_pin(user_id, pin) when is_binary(user_id) and is_binary(pin) do
    case Integer.parse(user_id) do
      {id, ""} -> verify_pin(id, pin)
      _ -> {:error, :invalid_pin}
    end
  end

  def verify_pin(user_id, pin) when is_integer(user_id) and is_binary(pin) do
    case Repo.get(User, user_id) do
      nil ->
        Pbkdf2.no_user_verify()
        {:error, :not_found}

      %User{active: false} ->
        Pbkdf2.no_user_verify()
        {:error, :inactive}

      %User{pin_hash: hash} when is_binary(hash) and hash != "" ->
        if Pbkdf2.verify_pass(pin, hash) do
          {:ok, Repo.get!(User, user_id)}
        else
          {:error, :invalid_pin}
        end

      %User{} ->
        Pbkdf2.no_user_verify()
        {:error, :pin_not_set}
    end
  end

  def verify_pin(_, _), do: {:error, :invalid_pin}

  defp validate_pin_format(pin) do
    if Regex.match?(@pin_pattern, pin) do
      :ok
    else
      {:error, :invalid_pin_format}
    end
  end

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

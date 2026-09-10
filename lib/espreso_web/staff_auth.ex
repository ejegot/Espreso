defmodule EspresoWeb.StaffAuth do
  @moduledoc """
  Session authentication and role authorization for staff
  (barista / manager / owner).
  """

  use EspresoWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  require Logger

  alias Espreso.Accounts
  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.StaffShifts

  def log_in_user(conn, user, params \\ %{}) do
    case maybe_open_staff_shift(user) do
      :ok ->
        user_return_to = get_session(conn, :user_return_to) || signed_in_path(user)

        conn
        |> renew_session()
        |> put_session(:user_id, user.id)
        |> delete_session(:user_return_to)
        |> redirect(to: params["redirect_to"] || user_return_to)

      {:error, reason} ->
        Logger.error("staff shift open failed for user_id=#{user.id}: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Unable to start your shift. Please try again.")
        |> redirect(to: ~p"/login")
    end
  end

  def log_out_user(conn) do
    case get_session(conn, :user_id) do
      nil ->
        :ok

      user_id ->
        maybe_close_staff_shift(user_id)
    end

    conn
    |> renew_session()
    |> delete_session(:user_id)
    |> redirect(to: ~p"/login")
  end

  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = if user_id, do: Accounts.get_user(user_id)
    assign(conn, :current_user, user)
  end

  def redirect_if_staff_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] && User.can_access_orders?(conn.assigns.current_user) do
      conn
      |> redirect(to: signed_in_path(conn.assigns.current_user))
      |> halt()
    else
      conn
    end
  end

  def require_authenticated_staff(conn, _opts) do
    user = conn.assigns[:current_user]

    if User.can_access_orders?(user) do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> put_flash(:error, "Please log in to continue.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc """
  Plug that requires a specific permission atom, e.g. `:user_management`.
  """
  def require_permission(conn, permission) when is_atom(permission) do
    user = conn.assigns[:current_user]

    if Authorization.can?(user, permission) do
      conn
    else
      conn
      |> put_flash(:error, "You don’t have permission to do that.")
      |> redirect(to: home_path(user))
      |> halt()
    end
  end

  def require_owner(conn, _opts) do
    require_permission(conn, :user_management)
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_staff, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if User.can_access_orders?(socket.assigns.current_user) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Please log in to continue.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount({:ensure_permission, permission}, _params, session, socket)
      when is_atom(permission) do
    socket = mount_current_user(socket, session)

    if Authorization.can?(socket.assigns.current_user, permission) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don’t have permission to do that.")
        |> Phoenix.LiveView.redirect(to: home_path(socket.assigns.current_user))

      {:halt, socket}
    end
  end

  def on_mount(:ensure_owner, _params, session, socket) do
    on_mount({:ensure_permission, :user_management}, %{}, session, socket)
  end

  def on_mount(:ensure_barista, _params, session, socket) do
    socket = mount_current_user(socket, session)
    user = socket.assigns.current_user

    if barista?(user) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don’t have permission to do that.")
        |> Phoenix.LiveView.redirect(to: home_path(user))

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if User.can_access_orders?(socket.assigns.current_user) do
      {:halt, Phoenix.LiveView.redirect(socket, to: home_path(socket.assigns.current_user))}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      case session do
        %{"user_id" => user_id} -> Accounts.get_user(user_id)
        _ -> nil
      end
    end)
  end

  defp renew_session(conn) do
    preferred_locale = get_session(conn, :locale)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:locale, preferred_locale)
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  @doc """
  Role-aware staff home after login / `/staff`.

  Barista → `/orders`. Manager and owner → `/dashboard`.
  """
  def home_path(%User{role: "barista"}), do: ~p"/orders"
  def home_path(%User{}), do: ~p"/dashboard"
  def home_path(_), do: ~p"/login"

  defp signed_in_path(user), do: home_path(user)

  # Employee StaffShift Time In/Out is barista-only. Manager/owner login and logout
  # must not create or close attendance shifts.
  defp maybe_open_staff_shift(%User{role: "barista"} = user) do
    case StaffShifts.open_shift_for_login(user) do
      {:ok, _shift} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_open_staff_shift(%User{}), do: :ok
  defp maybe_open_staff_shift(_), do: :ok

  defp maybe_close_staff_shift(user_id) when is_integer(user_id) do
    case Accounts.get_user(user_id) do
      %User{role: "barista"} ->
        case StaffShifts.close_shift_for_logout(user_id) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("staff shift close failed for user_id=#{user_id}: #{inspect(reason)}")
        end

      _ ->
        :ok
    end
  end

  defp barista?(%User{role: "barista", active: true}), do: true
  defp barista?(_), do: false
end

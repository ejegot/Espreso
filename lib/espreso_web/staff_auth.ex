defmodule EspresoWeb.StaffAuth do
  @moduledoc """
  Session authentication for staff (barista / manager / owner).
  """

  use EspresoWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Espreso.Accounts
  alias Espreso.Accounts.User

  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to) || signed_in_path(user)

    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> delete_session(:user_return_to)
    |> redirect(to: params["redirect_to"] || user_return_to)
  end

  def log_out_user(conn) do
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

  def require_owner(conn, _opts) do
    user = conn.assigns[:current_user]

    if User.can_manage_users?(user) do
      conn
    else
      conn
      |> put_flash(:error, "Owners only.")
      |> redirect(to: ~p"/orders")
      |> halt()
    end
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

  def on_mount(:ensure_owner, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if User.can_manage_users?(socket.assigns.current_user) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Owners only.")
        |> Phoenix.LiveView.redirect(to: ~p"/orders")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if User.can_access_orders?(socket.assigns.current_user) do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket.assigns.current_user))}
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

  defp signed_in_path(%User{role: "owner"}), do: ~p"/orders"
  defp signed_in_path(_user), do: ~p"/orders"
end

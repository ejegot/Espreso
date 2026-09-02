defmodule EspresoWeb.UserSessionController do
  use EspresoWeb, :controller

  alias Espreso.Accounts
  alias EspresoWeb.StaffAuth

  def create(conn, %{"user" => user_params}) do
    email = user_params["email"]
    password = user_params["password"]

    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome back, #{user.name}.")
        |> StaffAuth.log_in_user(user, user_params)

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> redirect(to: ~p"/login")
    end
  end

  def create_pin(conn, %{"user_id" => user_id, "pin" => pin}) when is_binary(pin) do
    case Accounts.verify_pin(user_id, pin) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome back, #{user.name}.")
        |> StaffAuth.log_in_user(user, %{})

      {:error, _} ->
        conn
        |> put_flash(:error, "Invalid PIN. Try again or use owner login.")
        |> redirect(to: ~p"/login")
    end
  end

  def create_pin(conn, _params) do
    conn
    |> put_flash(:error, "Invalid PIN login.")
    |> redirect(to: ~p"/login")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out.")
    |> StaffAuth.log_out_user()
  end
end

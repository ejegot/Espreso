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

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out.")
    |> StaffAuth.log_out_user()
  end
end

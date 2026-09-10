defmodule EspresoWeb.UserSessionController do
  use EspresoWeb, :controller

  alias Espreso.Accounts
  alias Espreso.Auth.PinAttemptLimiter
  alias EspresoWeb.ClientIP
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
    pin = String.trim(pin)

    if pin == "" do
      conn
      |> put_flash(:error, "Enter your PIN.")
      |> redirect(to: ~p"/login")
    else
      ip = ClientIP.from_conn(conn)

      case PinAttemptLimiter.check(user_id, ip) do
        {:error, :rate_limited} ->
          conn
          |> put_flash(:error, "Too many attempts. Please wait a moment before trying again.")
          |> redirect(to: ~p"/login")

        :ok ->
          case Accounts.verify_pin(user_id, pin) do
            {:ok, user} ->
              PinAttemptLimiter.record_success(user_id, ip)

              conn
              |> put_flash(:info, "Welcome back, #{user.name}.")
              |> StaffAuth.log_in_user(user, %{})

            {:error, _} ->
              PinAttemptLimiter.record_failure(user_id, ip)

              conn
              |> put_flash(:error, "Incorrect PIN. Try again.")
              |> redirect(to: ~p"/login")
          end
      end
    end
  end

  def create_pin(conn, _params) do
    conn
    |> put_flash(:error, "Select your name first.")
    |> redirect(to: ~p"/login")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out.")
    |> StaffAuth.log_out_user()
  end
end

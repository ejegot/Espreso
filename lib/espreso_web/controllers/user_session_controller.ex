defmodule EspresoWeb.UserSessionController do
  use EspresoWeb, :controller

  alias Espreso.Accounts
  alias Espreso.Auth.PinAttemptLimiter
  alias Espreso.Tenancy
  alias EspresoWeb.ClientIP
  alias EspresoWeb.StaffAuth

  def create(conn, %{"user" => user_params} = params) do
    email = user_params["email"]
    password = user_params["password"]
    login_path = login_path(params)

    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        if tenant_ok?(user, params) do
          conn
          |> put_flash(:info, "Welcome back, #{user.name}.")
          |> StaffAuth.log_in_user(user, user_params)
        else
          conn
          |> put_flash(:error, "Invalid email or password.")
          |> redirect(to: login_path)
        end

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> redirect(to: login_path)
    end
  end

  def create_pin(conn, %{"user_id" => user_id, "pin" => pin} = params) when is_binary(pin) do
    pin = String.trim(pin)
    login_path = login_path(params)

    if pin == "" do
      conn
      |> put_flash(:error, "Enter your PIN.")
      |> redirect(to: login_path)
    else
      ip = ClientIP.from_conn(conn)

      case PinAttemptLimiter.check(user_id, ip) do
        {:error, :rate_limited} ->
          conn
          |> put_flash(:error, "Too many attempts. Please wait a moment before trying again.")
          |> redirect(to: login_path)

        :ok ->
          case Accounts.verify_pin(user_id, pin) do
            {:ok, user} ->
              if tenant_ok?(user, params) do
                PinAttemptLimiter.record_success(user_id, ip)

                conn
                |> put_flash(:info, "Welcome back, #{user.name}.")
                |> StaffAuth.log_in_user(user, %{})
              else
                PinAttemptLimiter.record_failure(user_id, ip)

                conn
                |> put_flash(:error, "Incorrect PIN. Try again.")
                |> redirect(to: login_path)
              end

            {:error, _} ->
              PinAttemptLimiter.record_failure(user_id, ip)

              conn
              |> put_flash(:error, "Incorrect PIN. Try again.")
              |> redirect(to: login_path)
          end
      end
    end
  end

  def create_pin(conn, params) do
    conn
    |> put_flash(:error, "Select your name first.")
    |> redirect(to: login_path(params))
  end

  def create_from_token(conn, %{"token" => token}) when is_binary(token) do
    case StaffAuth.verify_login_token(token) do
      {:ok, user_id} ->
        case Accounts.get_user(user_id) do
          %Espreso.Accounts.User{active: true} = user ->
            conn
            |> put_flash(:info, "Welcome, #{user.name}. Your owner account is ready.")
            |> StaffAuth.log_in_user(user, %{})

          _ ->
            conn
            |> put_flash(:error, "That setup link is no longer valid. Please sign in.")
            |> redirect(to: ~p"/login")
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "That setup link expired. Please sign in.")
        |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    StaffAuth.log_out_user(conn)
  end

  defp tenant_ok?(user, params) do
    case params["tenant_slug"] do
      slug when is_binary(slug) and slug != "" ->
        case Tenancy.get_tenant_by_slug(slug) do
          %{id: tenant_id} -> user.tenant_id == tenant_id
          _ -> false
        end

      _ ->
        Tenancy.coffeespot_tenant?(user.tenant_id)
    end
  end

  defp login_path(%{"tenant_slug" => slug}) when is_binary(slug) and slug != "" do
    case Tenancy.get_tenant_by_slug(slug) do
      %{slug: slug} -> "/t/#{slug}/login"
      _ -> "/login"
    end
  end

  defp login_path(_), do: "/login"
end

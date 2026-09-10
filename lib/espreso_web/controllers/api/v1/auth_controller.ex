defmodule EspresoWeb.Api.V1.AuthController do
  use EspresoWeb, :controller

  alias Espreso.Accounts
  alias Espreso.Accounts.Token
  alias Espreso.Auth.PinAttemptLimiter
  alias EspresoWeb.Api.JSON
  alias EspresoWeb.ClientIP

  action_fallback EspresoWeb.Api.V1.FallbackController

  def pin(conn, %{"user_id" => user_id, "pin" => pin}) when is_binary(pin) do
    pin = String.trim(pin)

    if pin == "" do
      {:error, :invalid_credentials}
    else
      with user_id when is_integer(user_id) <- parse_id(user_id),
           ip = ClientIP.from_conn(conn),
           :ok <- PinAttemptLimiter.check(user_id, ip) do
        case Accounts.verify_pin(user_id, pin) do
          {:ok, user} ->
            PinAttemptLimiter.record_success(user_id, ip)

            case Token.issue_token_pair(user) do
              {:ok, tokens} -> json(conn, auth_payload(tokens, user))
              {:error, _} -> {:error, :invalid_credentials}
            end

          {:error, _} ->
            PinAttemptLimiter.record_failure(user_id, ip)
            {:error, :invalid_credentials}
        end
      else
        :error ->
          {:error, :invalid_credentials}

        {:error, :rate_limited} ->
          {:error, :too_many_attempts}
      end
    end
  end

  def pin(_conn, _params), do: {:error, :invalid_credentials}

  def email(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    with {:ok, user} <- Accounts.authenticate_user(email, password),
         {:ok, tokens} <- Token.issue_token_pair(user) do
      json(conn, auth_payload(tokens, user))
    else
      {:error, :invalid_credentials} -> {:error, :invalid_credentials}
    end
  end

  def email(_conn, _params), do: {:error, :invalid_credentials}

  def refresh(conn, %{"refresh_token" => refresh_token}) when is_binary(refresh_token) do
    case Token.refresh_access(refresh_token) do
      {:ok, %{access_token: access_token, user: user}} ->
        json(conn, %{
          access_token: access_token,
          user: JSON.user(user)
        })

      {:error, _} ->
        {:error, :invalid_token}
    end
  end

  def refresh(_conn, _params), do: {:error, :invalid_token}

  defp auth_payload(tokens, user) do
    Map.merge(tokens, %{user: JSON.user(user)})
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> :error
    end
  end

  defp parse_id(_), do: :error
end

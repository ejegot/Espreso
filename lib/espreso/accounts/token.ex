defmodule Espreso.Accounts.Token do
  @moduledoc false

  use Joken.Config

  alias Espreso.Accounts
  alias Espreso.Accounts.User

  @impl Joken.Config
  def token_config do
    default_claims(skip: [:aud, :iss, :jti])
  end

  @doc """
  Issues an access + refresh token pair for an active staff user.
  """
  def issue_token_pair(%User{} = user) do
    with {:ok, access_token} <- sign_access(user),
         {:ok, refresh_token} <- sign_refresh(user) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}}
    end
  end

  @doc """
  Verifies an access token and returns the active user.
  """
  def verify_access(token) when is_binary(token) do
    with {:ok, claims} <- verify_and_validate(token, signer()),
         :ok <- assert_type(claims, "access"),
         {:ok, user} <- user_from_claims(claims) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Verifies a refresh token and returns a new access token.
  """
  def refresh_access(token) when is_binary(token) do
    with {:ok, claims} <- verify_and_validate(token, signer()),
         :ok <- assert_type(claims, "refresh"),
         {:ok, user} <- user_from_claims(claims),
         {:ok, access_token} <- sign_access(user) do
      {:ok, %{access_token: access_token, user: user}}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp sign_access(%User{id: user_id}) do
    claims = base_claims(user_id, "access", access_ttl())

    case generate_and_sign(claims, signer()) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sign_refresh(%User{id: user_id}) do
    claims = base_claims(user_id, "refresh", refresh_ttl())

    case generate_and_sign(claims, signer()) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_claims(user_id, type, ttl_seconds) do
    now = System.system_time(:second)

    %{
      "user_id" => user_id,
      "typ" => type,
      "iat" => now,
      "exp" => now + ttl_seconds
    }
  end

  defp assert_type(%{"typ" => type}, expected) when type == expected, do: :ok
  defp assert_type(_, _), do: {:error, :invalid_token}

  defp user_from_claims(%{"user_id" => user_id}) when is_integer(user_id) do
    case Accounts.get_user(user_id) do
      %User{active: true} = user -> {:ok, user}
      _ -> {:error, :invalid_token}
    end
  end

  defp user_from_claims(%{"user_id" => user_id}) when is_float(user_id) do
    user_from_claims(%{"user_id" => trunc(user_id)})
  end

  defp user_from_claims(_), do: {:error, :invalid_token}

  defp signer do
    secret = Application.fetch_env!(:espreso, __MODULE__)[:signing_secret]
    Joken.Signer.create("HS256", secret)
  end

  defp access_ttl do
    Application.get_env(:espreso, __MODULE__, [])[:access_ttl] || 15 * 60
  end

  defp refresh_ttl do
    Application.get_env(:espreso, __MODULE__, [])[:refresh_ttl] || 7 * 24 * 60 * 60
  end
end

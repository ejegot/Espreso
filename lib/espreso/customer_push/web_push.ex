defmodule Espreso.CustomerPush.WebPush do
  @moduledoc false

  require Logger

  @finch Espreso.Finch
  @ttl_seconds 86_400

  def send_web_push(message, subscription, vapid) when is_binary(message) do
    with {:ok, endpoint} <- fetch_endpoint(subscription),
         {:ok, ua_public} <- decode_key(subscription, "p256dh"),
         {:ok, auth_secret} <- decode_key(subscription, "auth"),
         {:ok, body} <- encrypt(message, ua_public, auth_secret),
         {:ok, jwt, vapid_public} <- vapid_jwt(endpoint, vapid) do
      headers = [
        {"authorization", "vapid t=#{jwt},k=#{vapid_public}"},
        {"content-encoding", "aes128gcm"},
        {"content-type", "application/octet-stream"},
        {"ttl", Integer.to_string(@ttl_seconds)},
        {"urgency", "normal"}
      ]

      case Finch.build(:post, endpoint, headers, body) |> Finch.request(@finch) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status}} when status in [404, 410] ->
          {:error, :gone}

        {:ok, %{status: status, body: resp}} ->
          {:error, {:http, status, resp}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    error ->
      {:error, error}
  end

  defp fetch_endpoint(%{"endpoint" => endpoint}) when is_binary(endpoint), do: {:ok, endpoint}
  defp fetch_endpoint(_), do: {:error, :invalid_subscription}

  defp decode_key(subscription, name) do
    value =
      subscription
      |> Map.get("keys", %{})
      |> Map.get(name)

    case decode_url64(value) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, {:invalid_key, name}}
    end
  end

  defp encrypt(message, ua_public, auth_secret)
       when byte_size(ua_public) == 65 and byte_size(auth_secret) >= 16 do
    {as_public, as_private} = :crypto.generate_key(:ecdh, :prime256v1)
    ecdh_secret = :crypto.compute_key(:ecdh, ua_public, as_private, :prime256v1)
    salt = :crypto.strong_rand_bytes(16)

    key_info = "WebPush: info" <> <<0>> <> ua_public <> as_public
    ikm = hkdf_sha256(ecdh_secret, auth_secret, key_info, 32)
    cek = hkdf_sha256(ikm, salt, "Content-Encoding: aes128gcm" <> <<0>>, 16)
    nonce = hkdf_sha256(ikm, salt, "Content-Encoding: nonce" <> <<0>>, 12)

    plaintext = message <> <<2>>

    encrypted =
      :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, plaintext, <<>>, 16, true)

    cipher = aead_binary(encrypted)
    header = salt <> <<4096::32>> <> <<byte_size(as_public)::8>> <> as_public
    {:ok, header <> cipher}
  end

  defp encrypt(_message, _ua_public, _auth_secret), do: {:error, :invalid_client_key}

  defp aead_binary({ciphertext, tag}) when is_binary(ciphertext) and is_binary(tag),
    do: ciphertext <> tag

  defp aead_binary(binary) when is_binary(binary), do: binary

  defp hkdf_sha256(ikm, salt, info, length) when length in 1..32 do
    prk = :crypto.mac(:hmac, :sha256, salt, ikm)
    t1 = :crypto.mac(:hmac, :sha256, prk, info <> <<1>>)
    binary_part(t1, 0, length)
  end

  defp vapid_jwt(endpoint, vapid) do
    with {:ok, public} <- decode_url64(vapid[:public_key] || vapid["public_key"]),
         {:ok, private} <- decode_url64(vapid[:private_key] || vapid["private_key"]),
         {:ok, origin} <- audience(endpoint),
         {:ok, {x, y}} <- public_xy(public) do
      now = DateTime.utc_now() |> DateTime.to_unix()

      jwk =
        JOSE.JWK.from_map(%{
          "kty" => "EC",
          "crv" => "P-256",
          "x" => Base.url_encode64(x, padding: false),
          "y" => Base.url_encode64(y, padding: false),
          "d" => Base.url_encode64(private, padding: false)
        })

      claims = %{
        "aud" => origin,
        "exp" => now + 12 * 60 * 60,
        "sub" => vapid[:subject] || vapid["subject"] || "https://espreso.fly.dev"
      }

      {_, jwt} = JOSE.JWS.compact(JOSE.JWS.sign(jwk, Jason.encode!(claims), %{"alg" => "ES256"}))
      {:ok, jwt, Base.url_encode64(public, padding: false)}
    else
      :error -> {:error, :invalid_vapid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp public_xy(<<4, x::binary-size(32), y::binary-size(32)>>), do: {:ok, {x, y}}
  defp public_xy(_), do: {:error, :invalid_vapid}

  defp audience(endpoint) do
    uri = URI.parse(endpoint)

    case {uri.scheme, uri.host} do
      {scheme, host} when scheme in ["https", "http"] and is_binary(host) ->
        port =
          cond do
            uri.port in [80, 443, nil] -> ""
            true -> ":#{uri.port}"
          end

        {:ok, "#{scheme}://#{host}#{port}"}

      _ ->
        {:error, :invalid_endpoint}
    end
  end

  defp decode_url64(nil), do: :error

  defp decode_url64(value) when is_binary(value) do
    padded =
      case rem(byte_size(value), 4) do
        0 -> value
        n -> value <> String.duplicate("=", 4 - n)
      end

    case Base.url_decode64(padded, padding: true) do
      {:ok, bin} -> {:ok, bin}
      :error -> Base.decode64(padded)
    end
  end
end

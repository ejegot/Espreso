defmodule Espreso.PayMongo do
  @moduledoc """
  PayMongo hosted checkout for GCash and Maya (PayMaya) payments.
  """

  alias Espreso.Orders
  alias Espreso.Orders.Order

  @type payment_channel :: :gcash | :maya

  @doc """
  Creates a PayMongo checkout session for an unpaid online order.

  `channel` is `:gcash` or `:maya`. Redirect the customer to the returned
  `checkout_url`. Payment confirmation arrives via webhook.
  """
  def create_checkout_session(%Order{} = order, lines, opts) when is_list(lines) do
    client().create_checkout_session(order, lines, opts)
  end

  @doc """
  Verifies a PayMongo webhook signature from the raw request body and header.
  """
  def verify_webhook_signature(raw_body, signature_header) when is_binary(raw_body) do
    with {:ok, parts} <- parse_signature_header(signature_header),
         {:ok, signature} <- pick_signature(parts),
         expected <- sign_payload(parts.timestamp, raw_body),
         true <- secure_compare(expected, signature) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_signature}
    end
  end

  @doc """
  Handles a verified PayMongo webhook payload.

  Marks the referenced order paid on `checkout_session.payment.paid`.
  Unknown event types are acknowledged without action.
  """
  def handle_webhook_event(payload) when is_map(payload) do
    event_type = get_in(payload, ["data", "attributes", "type"])

    case event_type do
      "checkout_session.payment.paid" ->
        handle_checkout_paid(payload)

      _ ->
        :ok
    end
  end

  @doc """
  Builds a Paymongo-Signature header value for tests.
  """
  def sign_for_test(raw_body, opts \\ []) do
    secret = Keyword.get(opts, :secret, webhook_secret())
    timestamp = Keyword.get(opts, :timestamp, System.system_time(:second))
    mode = Keyword.get(opts, :mode, :test)
    signature = sign_payload(timestamp, raw_body, secret)

    case mode do
      :live -> "t=#{timestamp},te=,li=#{signature}"
      _ -> "t=#{timestamp},te=#{signature},li="
    end
  end

  defp handle_checkout_paid(payload) do
    session = get_in(payload, ["data", "attributes", "data"]) || %{}
    session_id = Map.get(session, "id")
    reference_number = get_in(session, ["attributes", "reference_number"])

    _ =
      cond do
        is_binary(reference_number) and reference_number != "" ->
          Orders.mark_paid_from_paymongo(reference_number, session_id)

        is_binary(session_id) and session_id != "" ->
          Orders.mark_paid_from_paymongo_session(session_id)

        true ->
          {:error, :missing_reference}
      end

    :ok
  end

  defp parse_signature_header(header) when is_binary(header) do
    parts =
      header
      |> String.split(",", trim: true)
      |> Enum.reduce(%{}, fn part, acc ->
        case String.split(part, "=", parts: 2) do
          [key, value] -> Map.put(acc, key, value)
          _ -> acc
        end
      end)

    case Map.fetch(parts, "t") do
      {:ok, timestamp} -> {:ok, %{timestamp: timestamp, te: Map.get(parts, "te"), li: Map.get(parts, "li")}}
      :error -> {:error, :missing_timestamp}
    end
  end

  defp parse_signature_header(_), do: {:error, :missing_signature}

  defp pick_signature(%{te: _te, li: li}) when is_binary(li) and li != "" do
    {:ok, li}
  end

  defp pick_signature(%{te: te}) when is_binary(te) and te != "" do
    {:ok, te}
  end

  defp pick_signature(_), do: {:error, :missing_signature}

  defp sign_payload(timestamp, raw_body, secret \\ webhook_secret()) do
    :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{raw_body}")
    |> Base.encode16(case: :lower)
  end

  defp secure_compare(left, right) when is_binary(left) and is_binary(right) do
    byte_size(left) == byte_size(right) and Plug.Crypto.secure_compare(left, right)
  end

  defp secure_compare(_, _), do: false

  defp client do
    Application.get_env(:espreso, :paymongo, [])[:client] || Espreso.PayMongo.HTTPClient
  end

  defp webhook_secret do
    case Application.get_env(:espreso, :paymongo, [])[:webhook_secret] do
      secret when is_binary(secret) and secret != "" -> secret
      _ -> raise "PayMongo webhook secret is not configured"
    end
  end
end

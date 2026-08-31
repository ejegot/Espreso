defmodule Espreso.PayMongo do
  @moduledoc """
  PayMongo hosted checkout for GCash and Maya (PayMaya) payments.
  """

  alias Espreso.Orders
  alias Espreso.Orders.Order

  require Logger

  @type payment_channel :: :gcash | :maya

  @doc """
  Creates a PayMongo checkout session for an unpaid online order.

  `channel` is `:gcash` or `:maya`. Redirect the customer to the returned
  `checkout_url`. Payment confirmation arrives via webhook.

  Fails closed with `{:error, :checkout_amount_mismatch}` when the checkout
  line-item centavo total does not exactly equal `order.total`.
  """
  def create_checkout_session(%Order{} = order, lines, opts) when is_list(lines) do
    with {:ok, line_items} <- build_checkout_line_items(lines),
         :ok <- assert_checkout_amount_matches_order(order, line_items) do
      client().create_checkout_session(order, lines, opts)
    end
  end

  @doc false
  def build_checkout_line_items(lines) when is_list(lines) do
    lines
    |> Enum.reduce_while([], fn line, acc ->
      case build_checkout_line_item(line) do
        {:ok, item} -> {:cont, [item | acc]}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:error, _} = error -> error
      items when is_list(items) -> {:ok, Enum.reverse(items)}
    end
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
  Verifies that a signed webhook payload's `livemode` matches this app.

  Must only be called after `verify_webhook_signature/2` succeeds.
  """
  def verify_webhook_livemode(payload) when is_map(payload) do
    with {:ok, expected} <- expected_livemode(),
         {:ok, actual} <- parse_payload_livemode(payload),
         true <- actual == expected do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :livemode_mismatch}
    end
  end

  @doc """
  Returns the application's expected PayMongo `livemode` flag.

  Uses explicit `:livemode` config when set; otherwise derives from
  `:secret_key` (`sk_test_*` → false, `sk_live_*` → true).
  """
  def expected_livemode do
    config = Application.get_env(:espreso, :paymongo, [])

    case Keyword.get(config, :livemode) do
      livemode when is_boolean(livemode) ->
        {:ok, livemode}

      _ ->
        derive_livemode_from_secret_key(Keyword.get(config, :secret_key))
    end
  end

  @doc """
  Handles a verified PayMongo webhook payload.

  Marks the referenced order paid on `checkout_session.payment.paid` only when
  the paid payment amount matches the order total and the webhook checkout
  session id matches the session already stored on the order. Unknown event
  types are acknowledged without action.
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
  Converts a peso Decimal total to an exact integer centavo amount.

  Rejects totals that are not an exact number of centavos (no float math).
  """
  def pesos_to_centavos(%Decimal{} = total) do
    scaled = Decimal.mult(total, Decimal.new(100))

    if Decimal.equal?(scaled, Decimal.round(scaled, 0)) do
      {:ok, Decimal.to_integer(Decimal.round(scaled, 0))}
    else
      {:error, :invalid_order_total}
    end
  end

  def pesos_to_centavos(_), do: {:error, :invalid_order_total}

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

    with {:ok, amount} <- extract_paid_amount_centavos(session),
         {:ok, order} <- find_order(reference_number, session_id),
         :ok <- verify_amount_matches(order, amount),
         :ok <- verify_checkout_session(order, session_id) do
      case mark_order_paid(order, session_id) do
        {:ok, _} ->
          :ok

        {:error, :order_cancelled} = error ->
          record_cancelled_payment_reconciliation(payload, session, session_id, order, amount)
          error

        other ->
          other
      end
    else
      {:error, :missing_amount} = error -> error
      {:error, :invalid_amount} = error -> error
      {:error, :amount_mismatch} = error -> error
      {:error, :invalid_order_total} = error -> error
      {:error, :missing_session} = error -> error
      {:error, :session_mismatch} = error -> error
      {:error, :not_found} -> :ok
      {:error, :missing_reference} -> :ok
      {:error, _} -> :ok
    end
  end

  defp extract_paid_amount_centavos(session) when is_map(session) do
    case get_in(session, ["attributes", "payments"]) do
      payments when is_list(payments) and payments != [] ->
        paid =
          Enum.filter(payments, fn payment ->
            get_in(payment, ["attributes", "status"]) == "paid"
          end)

        amounts = Enum.map(paid, &get_in(&1, ["attributes", "amount"]))

        cond do
          paid == [] ->
            {:error, :missing_amount}

          Enum.any?(amounts, fn amount -> not is_integer(amount) or amount < 0 end) ->
            {:error, :invalid_amount}

          true ->
            {:ok, Enum.sum(amounts)}
        end

      _ ->
        {:error, :missing_amount}
    end
  end

  defp find_order(reference_number, session_id) do
    cond do
      is_binary(reference_number) and reference_number != "" ->
        case Orders.get_order_by_number(reference_number) do
          %Order{} = order -> {:ok, order}
          nil -> {:error, :not_found}
        end

      is_binary(session_id) and session_id != "" ->
        case Espreso.Repo.get_by(Order, paymongo_checkout_session_id: session_id) do
          %Order{} = order -> {:ok, order}
          nil -> {:error, :not_found}
        end

      true ->
        {:error, :missing_reference}
    end
  end

  defp verify_amount_matches(%Order{total: total}, amount_centavos)
       when is_integer(amount_centavos) do
    case pesos_to_centavos(total) do
      {:ok, ^amount_centavos} -> :ok
      {:ok, _} -> {:error, :amount_mismatch}
      {:error, _} = error -> error
    end
  end

  defp verify_checkout_session(_order, session_id)
       when not is_binary(session_id) or session_id == "" do
    {:error, :missing_session}
  end

  defp verify_checkout_session(%Order{paymongo_checkout_session_id: stored}, _session_id)
       when not is_binary(stored) or stored == "" do
    {:error, :missing_session}
  end

  defp verify_checkout_session(%Order{paymongo_checkout_session_id: stored}, session_id)
       when stored == session_id do
    :ok
  end

  defp verify_checkout_session(_order, _session_id), do: {:error, :session_mismatch}

  defp mark_order_paid(%Order{number: number}, session_id) do
    case Orders.mark_paid_from_paymongo(number, session_id) do
      {:error, :cancelled} -> {:error, :order_cancelled}
      other -> other
    end
  end

  defp record_cancelled_payment_reconciliation(payload, session, session_id, order, amount_centavos) do
    {payment_id, currency} = extract_paid_payment_audit(session)
    event_id = get_in(payload, ["data", "id"])

    case Orders.record_paymongo_reconciliation(%{
           order_id: order.id,
           order_number: order.number,
           paymongo_checkout_session_id: session_id,
           paymongo_payment_id: payment_id,
           paymongo_webhook_event_id: event_id,
           amount_centavos: amount_centavos,
           currency: currency || "PHP"
         }) do
      {:ok, _record} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "failed to record PayMongo reconciliation for order #{order.number}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp extract_paid_payment_audit(session) when is_map(session) do
    case get_in(session, ["attributes", "payments"]) do
      payments when is_list(payments) ->
        paid =
          Enum.filter(payments, fn payment ->
            get_in(payment, ["attributes", "status"]) == "paid"
          end)

        payment_ids =
          paid
          |> Enum.map(&Map.get(&1, "id"))
          |> Enum.filter(&(is_binary(&1) and &1 != ""))

        currency =
          paid
          |> Enum.find_value(fn payment ->
            case get_in(payment, ["attributes", "currency"]) do
              c when is_binary(c) and c != "" -> c
              _ -> nil
            end
          end)

        payment_id =
          case payment_ids do
            [only] -> only
            many when many != [] -> Enum.join(many, ",")
            _ -> nil
          end

        {payment_id, currency}

      _ ->
        {nil, nil}
    end
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
      {:ok, timestamp} ->
        {:ok, %{timestamp: timestamp, te: Map.get(parts, "te"), li: Map.get(parts, "li")}}

      :error ->
        {:error, :missing_timestamp}
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

  defp parse_payload_livemode(payload) do
    case get_in(payload, ["data", "attributes", "livemode"]) do
      livemode when is_boolean(livemode) -> {:ok, livemode}
      _ -> {:error, :missing_livemode}
    end
  end

  defp derive_livemode_from_secret_key("sk_live_" <> _), do: {:ok, true}
  defp derive_livemode_from_secret_key("sk_test_" <> _), do: {:ok, false}
  defp derive_livemode_from_secret_key(_), do: {:error, :unconfigured_livemode}

  defp assert_checkout_amount_matches_order(%Order{total: total}, line_items)
       when is_list(line_items) do
    with {:ok, expected_centavos} <- pesos_to_centavos(total) do
      checkout_centavos =
        Enum.reduce(line_items, 0, fn item, acc ->
          acc + item.amount * item.quantity
        end)

      if checkout_centavos == expected_centavos do
        :ok
      else
        {:error, :checkout_amount_mismatch}
      end
    end
  end

  defp build_checkout_line_item(line) when is_map(line) do
    price = Map.get(line, :price) || Map.get(line, "price")
    quantity = Map.get(line, :quantity) || Map.get(line, "quantity")

    with {:ok, amount} <- unit_price_to_centavos(price),
         true <- is_integer(quantity) and quantity >= 1 do
      {:ok,
       %{
         name: line_item_name(line),
         amount: amount,
         currency: "PHP",
         quantity: quantity
       }}
    else
      false ->
        {:error, :invalid_line_quantity}

      {:error, :invalid_order_total} ->
        {:error, :invalid_line_amount}

      {:error, _} = error ->
        error
    end
  end

  defp unit_price_to_centavos(%Decimal{} = price), do: pesos_to_centavos(price)

  defp unit_price_to_centavos(price) when is_binary(price) do
    pesos_to_centavos(Decimal.new(price))
  rescue
    ArgumentError -> {:error, :invalid_line_amount}
    Decimal.Error -> {:error, :invalid_line_amount}
  end

  defp unit_price_to_centavos(_price), do: {:error, :invalid_line_amount}

  defp line_item_name(line) do
    name = Map.get(line, :name) || Map.get(line, "name")

    case Map.get(line, :size) || Map.get(line, "size") do
      nil -> name
      "" -> name
      size -> "#{name} (#{size})"
    end
  end
end

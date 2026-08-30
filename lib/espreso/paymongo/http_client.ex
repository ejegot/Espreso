defmodule Espreso.PayMongo.HTTPClient do
  @moduledoc false

  @behaviour Espreso.PayMongo.Client

  alias Espreso.Orders.Order

  @api_url "https://api.paymongo.com/v2/checkout_sessions"
  @finch Espreso.Finch

  @impl true
  def create_checkout_session(%Order{} = order, lines, opts) when is_list(lines) do
    channel = Keyword.fetch!(opts, :channel)
    success_url = Keyword.fetch!(opts, :success_url)
    cancel_url = Keyword.fetch!(opts, :cancel_url)

    body =
      %{
        data: %{
          attributes: %{
            billing: %{
              name: order.customer_name
            },
            line_items: line_items(lines),
            payment_method_types: [payment_method_type(channel)],
            reference_number: order.number,
            success_url: success_url,
            cancel_url: cancel_url,
            metadata: %{
              order_number: order.number,
              order_id: order.id
            }
          }
        }
      }
      |> Jason.encode!()

    case Finch.build(:post, @api_url, headers(), body)
         |> Finch.request(@finch) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        decode_checkout_response(response_body)

      {:ok, %{status: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers do
    auth = Base.encode64("#{secret_key()}:")
    [{"content-type", "application/json"}, {"authorization", "Basic #{auth}"}]
  end

  defp secret_key do
    case Application.get_env(:espreso, :paymongo, [])[:secret_key] do
      key when is_binary(key) and key != "" -> key
      _ -> raise "PayMongo secret key is not configured"
    end
  end

  defp payment_method_type(:gcash), do: "gcash"
  defp payment_method_type(:maya), do: "paymaya"
  defp payment_method_type("gcash"), do: "gcash"
  defp payment_method_type("maya"), do: "paymaya"

  defp line_items(lines) do
    Enum.map(lines, fn line ->
      name =
        case Map.get(line, :size) || Map.get(line, "size") do
          nil -> Map.get(line, :name) || Map.get(line, "name")
          "" -> Map.get(line, :name) || Map.get(line, "name")
          size -> "#{Map.get(line, :name) || Map.get(line, "name")} (#{size})"
        end

      %{
        name: name,
        amount: to_centavos(Map.get(line, :price) || Map.get(line, "price")),
        currency: "PHP",
        quantity: Map.get(line, :quantity) || Map.get(line, "quantity")
      }
    end)
  end

  defp to_centavos(%Decimal{} = amount) do
    amount
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  defp to_centavos(amount) when is_binary(amount), do: amount |> Decimal.new() |> to_centavos()
  defp to_centavos(amount) when is_number(amount), do: round(amount * 100)

  defp decode_checkout_response(body) do
    with {:ok, %{"data" => %{"id" => id, "attributes" => attrs}}} <- Jason.decode(body),
         checkout_url when is_binary(checkout_url) <- Map.get(attrs, "checkout_url") do
      {:ok, %{id: id, checkout_url: checkout_url}}
    else
      _ -> {:error, :invalid_response}
    end
  end
end

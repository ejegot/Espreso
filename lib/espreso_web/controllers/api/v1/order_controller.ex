defmodule EspresoWeb.Api.V1.OrderController do
  use EspresoWeb, :controller

  alias Espreso.Menu
  alias Espreso.Orders
  alias EspresoWeb.Api.JSON

  action_fallback EspresoWeb.Api.V1.FallbackController

  def index(conn, params) do
    scope = Map.get(params, "scope", "active")

    orders =
      scope
      |> Orders.list_orders_for_api()
      |> Enum.map(&JSON.order/1)

    json(conn, %{orders: orders})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, order} <- Orders.get_order_for_api(id) do
      json(conn, %{order: JSON.order(order)})
    end
  end

  def create(conn, params) do
    with {:ok, lines} <- build_lines(params["lines"] || []),
         {:ok, attrs} <- build_create_attrs(params, conn.assigns.current_user.id),
         {:ok, order} <- Orders.create_order(lines, attrs) do
      conn
      |> put_status(:created)
      |> json(%{order: JSON.order(order)})
    end
  end

  def update_status(conn, %{"id" => id, "status" => status}) when is_binary(status) do
    with {:ok, id} <- parse_id(id),
         {:ok, order} <- Orders.get_order_for_api(id),
         {:ok, updated} <- Orders.update_status_for_api(order, status),
         {:ok, updated} <- Orders.get_order_for_api(updated.id) do
      json(conn, %{order: JSON.order(updated)})
    end
  end

  def update_status(_conn, _params), do: {:error, :invalid_status}

  def mark_paid(conn, %{"id" => id} = params) do
    paid_via = Map.get(params, "paid_via", "counter")

    settlement_opts =
      [
        paid_via: paid_via,
        settled_by_user_id: conn.assigns.current_user.id,
        settlement_source: "api"
      ]
      |> maybe_put_cash_tendered(params)

    with {:ok, id} <- parse_id(id),
         {:ok, order} <- Orders.get_order_for_api(id),
         {:ok, paid} <- Orders.mark_paid(order, settlement_opts),
         {:ok, paid} <- Orders.get_order_for_api(paid.id) do
      json(conn, %{order: JSON.order(paid)})
    end
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :not_found}
    end
  end

  defp build_create_attrs(params, user_id) do
    customer_name = params["customer_name"] || "Walk-in"
    payment_status = params["payment_status"] || "unpaid"

    attrs =
      %{
        customer_name: customer_name,
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: payment_status,
        source: :pos,
        settled_by_user_id: user_id,
        settlement_source: :api,
        notes: blank_to_nil(params["notes"])
      }
      |> maybe_put_cash_tendered(params)

    {:ok, attrs}
  end

  defp maybe_put_cash_tendered(attrs, %{"cash_tendered" => cash_tendered}) when is_list(attrs),
    do: Keyword.put(attrs, :cash_tendered, cash_tendered)

  defp maybe_put_cash_tendered(attrs, %{"cash_tendered" => cash_tendered}) when is_map(attrs),
    do: Map.put(attrs, :cash_tendered, cash_tendered)

  defp maybe_put_cash_tendered(attrs, _params), do: attrs

  defp build_lines(lines) when is_list(lines) do
    menu = Menu.list_menu()

    lines
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case line_to_cart(line, menu) do
        {:ok, cart_line} -> {:cont, {:ok, [cart_line | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, []} -> {:error, :empty_cart}
      {:ok, cart_lines} -> {:ok, Enum.reverse(cart_lines)}
      error -> error
    end
  end

  defp line_to_cart(%{"product_id" => product_id} = line, menu) do
    with {:ok, product_id} <- parse_id(product_id),
         {:ok, product, price} <- find_product_price(menu, product_id, line["price_id"]),
         {:ok, quantity} <- parse_quantity(line["quantity"]) do
      {:ok,
       %{
         product_id: product.id,
         price_id: price.id,
         name: product.name,
         size: price.size,
         quantity: quantity,
         price: price.price
       }}
    end
  end

  defp line_to_cart(_line, _menu), do: {:error, :invalid_line}

  defp find_product_price(menu, product_id, price_id) do
    menu
    |> Enum.find_value(fn category ->
      Enum.find_value(category.products, fn product ->
        if product.id == product_id do
          case select_price(product, price_id) do
            nil -> nil
            price -> {product, price}
          end
        end
      end)
    end)
    |> case do
      {product, price} -> {:ok, product, price}
      nil -> {:error, :not_found}
    end
  end

  defp select_price(product, price_id) when is_binary(price_id) or is_integer(price_id) do
    with {:ok, id} <- parse_id(price_id) do
      Enum.find(product.product_prices, &(&1.id == id))
    end
  end

  defp select_price(product, _) do
    case product.product_prices do
      [price] -> price
      _ -> nil
    end
  end

  defp parse_quantity(nil), do: {:ok, 1}
  defp parse_quantity(qty) when is_integer(qty) and qty > 0, do: {:ok, qty}

  defp parse_quantity(qty) when is_binary(qty) do
    case Integer.parse(qty) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> {:error, :invalid_line}
    end
  end

  defp parse_quantity(_), do: {:error, :invalid_line}

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

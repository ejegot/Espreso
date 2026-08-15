defmodule Espreso.Menu do
  @moduledoc """
  The Menu context for loading customer-facing menu data.
  """

  import Ecto.Query

  alias Espreso.Repo
  alias Espreso.Menu.Category

  @category_order ~w(HOT COLD FRAPPE SODA FOOD)

  @doc """
  Returns categories in menu order, each with available products and their prices.
  """
  def list_menu do
    Category
    |> preload(products: :product_prices)
    |> Repo.all()
    |> Enum.map(&filter_available_products/1)
    |> Enum.sort_by(&category_position/1)
  end

  defp filter_available_products(category) do
    products =
      category.products
      |> Enum.filter(& &1.available)
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn product ->
        prices =
          product.product_prices
          |> Enum.sort_by(&price_sort_key/1)

        %{product | product_prices: prices}
      end)

    %{category | products: products}
  end

  defp category_position(%{name: name}) do
    Enum.find_index(@category_order, &(&1 == name)) || length(@category_order)
  end

  defp price_sort_key(%{size: nil}), do: {0, ""}
  defp price_sort_key(%{size: size}), do: {1, size}

  @doc """
  Formats a price as Philippine peso.

  Whole peso amounts omit decimals (₱75). Fractional amounts use two decimals (₱75.50).
  """
  def format_price(price) do
    rounded = Decimal.round(price, 2)

    formatted =
      if Decimal.equal?(rounded, Decimal.round(rounded, 0)) do
        rounded
        |> Decimal.round(0)
        |> Decimal.to_string(:normal)
      else
        rounded
        |> Decimal.to_string(:normal)
        |> ensure_two_decimals()
      end

    "₱#{formatted}"
  end

  defp ensure_two_decimals(string) do
    case String.split(string, ".") do
      [whole] -> "#{whole}.00"
      [whole, fraction] -> "#{whole}.#{String.pad_trailing(fraction, 2, "0")}"
    end
  end
end

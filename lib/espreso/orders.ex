defmodule Espreso.Orders do
  @moduledoc """
  Cafe order placement and staff status updates.
  """

  import Ecto.Query

  alias Espreso.Repo
  alias Espreso.Orders.{Order, OrderItem}
  alias Espreso.Menu

  @doc """
  Creates an order from cart lines and checkout attrs.

  `lines` — maps with `:name`, `:size`, `:quantity`, `:price` (Decimal).
  `attrs` — `:customer_name`, `:fulfillment` (`:dine_in` | `:pickup` or strings),
  `:table_number`, `:notes`, `:payment_method` (`:counter` | `:online`).
  """
  def create_order(lines, attrs) when is_list(lines) and lines != [] do
    fulfillment =
      normalize_fulfillment(Map.get(attrs, :fulfillment) || Map.get(attrs, "fulfillment"))

    payment_method =
      normalize_payment_method(
        Map.get(attrs, :payment_method) || Map.get(attrs, "payment_method")
      )

    total =
      Enum.reduce(lines, Decimal.new(0), fn line, acc ->
        Decimal.add(acc, Decimal.mult(line.price, line.quantity))
      end)

    payment_status = if payment_method == "online", do: "unpaid", else: "unpaid"

    order_attrs = %{
      number: "TMP-" <> Integer.to_string(System.unique_integer([:positive])),
      customer_name: Map.get(attrs, :customer_name) || Map.get(attrs, "customer_name"),
      fulfillment: fulfillment,
      table_number: Map.get(attrs, :table_number) || Map.get(attrs, "table_number"),
      notes: blank_to_nil(Map.get(attrs, :notes) || Map.get(attrs, "notes")),
      payment_method: payment_method,
      payment_status: payment_status,
      status: "received",
      total: total
    }

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:order, Order.changeset(%Order{}, order_attrs))
    |> Ecto.Multi.update(:numbered, fn %{order: order} ->
      Ecto.Changeset.change(order, %{number: format_number(order.id)})
    end)
    |> Ecto.Multi.run(:items, fn repo, %{numbered: order} ->
      items =
        Enum.map(lines, fn line ->
          qty = line.quantity
          unit = line.price
          line_total = Decimal.mult(unit, qty)

          %OrderItem{}
          |> OrderItem.changeset(%{
            order_id: order.id,
            name: line.name,
            size: blank_to_nil(Map.get(line, :size)),
            quantity: qty,
            unit_price: unit,
            line_total: line_total
          })
          |> repo.insert!()
        end)

      {:ok, items}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{numbered: order, items: items}} ->
        {:ok, %{order | items: items}}

      {:error, :order, changeset, _} ->
        {:error, changeset}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  def create_order([], _attrs), do: {:error, :empty_cart}

  def get_order_by_number!(number) when is_binary(number) do
    Order
    |> where([o], o.number == ^number)
    |> preload(:items)
    |> Repo.one!()
  end

  def get_order_by_number(number) when is_binary(number) do
    Order
    |> where([o], o.number == ^number)
    |> preload(:items)
    |> Repo.one()
  end

  def list_active_orders do
    Order
    |> where([o], o.status in ^["received", "preparing"])
    |> order_by([o], asc: o.inserted_at)
    |> preload(:items)
    |> Repo.all()
  end

  def list_recent_ready(limit \\ 10) do
    Order
    |> where([o], o.status == "ready")
    |> order_by([o], desc: o.updated_at)
    |> limit(^limit)
    |> preload(:items)
    |> Repo.all()
  end

  @doc """
  Read-only order counts for the staff dashboard.

  Uses aggregate queries only (no order/item preloads).
  `todays_count` is based on UTC calendar day of `inserted_at`.
  """
  def dashboard_overview do
    active_statuses = ["received", "preparing"]
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    %{
      active_count: count_orders(status: active_statuses),
      received_count: count_orders(status: ["received"]),
      preparing_count: count_orders(status: ["preparing"]),
      unpaid_active_count: count_orders(status: active_statuses, payment_status: "unpaid"),
      todays_count: count_orders(inserted_at_gte: today_start)
    }
  end

  defp count_orders(opts) do
    Order
    |> then(fn query ->
      case Keyword.get(opts, :status) do
        statuses when is_list(statuses) -> where(query, [o], o.status in ^statuses)
        _ -> query
      end
    end)
    |> then(fn query ->
      case Keyword.get(opts, :payment_status) do
        status when is_binary(status) -> where(query, [o], o.payment_status == ^status)
        _ -> query
      end
    end)
    |> then(fn query ->
      case Keyword.get(opts, :inserted_at_gte) do
        %DateTime{} = dt -> where(query, [o], o.inserted_at >= ^dt)
        _ -> query
      end
    end)
    |> Repo.aggregate(:count, :id)
  end

  def update_status(%Order{} = order, status) when status in ["received", "preparing", "ready"] do
    order
    |> Order.status_changeset(status)
    |> Repo.update()
  end

  def mark_paid(%Order{} = order) do
    order
    |> Order.payment_changeset(%{payment_status: "paid"})
    |> Repo.update()
  end

  def format_total(%Order{total: total}), do: Menu.format_price(total)

  def fulfillment_label("dine_in"), do: "Dine-in"
  def fulfillment_label("pickup"), do: "Pickup at counter"
  def fulfillment_label(_), do: "Order"

  def status_label("received"), do: "Received"
  def status_label("preparing"), do: "Preparing"
  def status_label("ready"), do: "Ready"
  def status_label(other), do: other

  def payment_label(%Order{payment_method: "counter", payment_status: "unpaid"}),
    do: "Pay at counter"

  def payment_label(%Order{payment_method: "counter", payment_status: "paid"}),
    do: "Paid at counter"

  def payment_label(%Order{payment_method: "online", payment_status: "paid"}),
    do: "Paid online"

  def payment_label(%Order{payment_method: "online", payment_status: "unpaid"}),
    do: "Online (unpaid)"

  def payment_label(_), do: "Payment"

  defp format_number(id) when is_integer(id) do
    "CS-" <> String.pad_leading(Integer.to_string(id), 4, "0")
  end

  defp normalize_fulfillment(value) when value in [:dine_in, "dine_in"], do: "dine_in"
  defp normalize_fulfillment(value) when value in [:pickup, "pickup"], do: "pickup"
  defp normalize_fulfillment(_), do: "dine_in"

  defp normalize_payment_method(value) when value in [:online, "online"], do: "online"
  defp normalize_payment_method(_), do: "counter"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end

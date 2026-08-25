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
  `:table_number`, `:notes`, `:payment_method` (`:counter` | `:online`),
  `:source` (`:customer` | `:pos` or strings; default `"customer"`),
  optional `:payment_status` (`:unpaid` | `:paid`) — `:paid` only allowed with
  `:counter` (POS pay-at-create). Online is always unpaid. Default unpaid.
  """
  def create_order(lines, attrs) when is_list(lines) and lines != [] do
    fulfillment =
      normalize_fulfillment(Map.get(attrs, :fulfillment) || Map.get(attrs, "fulfillment"))

    payment_method =
      normalize_payment_method(
        Map.get(attrs, :payment_method) || Map.get(attrs, "payment_method")
      )

    source = normalize_source(Map.get(attrs, :source) || Map.get(attrs, "source"))

    payment_status =
      normalize_payment_status(
        payment_method,
        Map.get(attrs, :payment_status) || Map.get(attrs, "payment_status")
      )

    total =
      Enum.reduce(lines, Decimal.new(0), fn line, acc ->
        Decimal.add(acc, Decimal.mult(line.price, line.quantity))
      end)

    order_attrs = %{
      number: "TMP-" <> Integer.to_string(System.unique_integer([:positive])),
      customer_name: Map.get(attrs, :customer_name) || Map.get(attrs, "customer_name"),
      fulfillment: fulfillment,
      table_number: Map.get(attrs, :table_number) || Map.get(attrs, "table_number"),
      notes: blank_to_nil(Map.get(attrs, :notes) || Map.get(attrs, "notes")),
      payment_method: payment_method,
      payment_status: payment_status,
      source: source,
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
  Cancelled orders are excluded from operational counts.
  """
  def dashboard_overview do
    active_statuses = ["received", "preparing"]
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    %{
      active_count: count_orders(status: active_statuses),
      received_count: count_orders(status: ["received"]),
      preparing_count: count_orders(status: ["preparing"]),
      unpaid_active_count: count_orders(status: active_statuses, payment_status: "unpaid"),
      todays_count: count_orders(inserted_at_gte: today_start, exclude_cancelled: true)
    }
  end

  @doc """
  Recent orders placed today (UTC calendar day of `inserted_at`).

  Newest first. Does not preload items. Default limit is 5.
  Excludes cancelled orders.
  """
  def list_todays_orders(limit \\ 5) when is_integer(limit) and limit > 0 do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    Order
    |> where([o], o.inserted_at >= ^today_start and o.status != "cancelled")
    |> order_by([o], desc: o.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Today's paid sales for the dashboard (UTC calendar day of `inserted_at`).

  Only `payment_status == "paid"` orders are included. Uses `Order.total`
  aggregates — does not load items.
  """
  def sales_overview do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    paid_today =
      Order
      |> where([o], o.payment_status == "paid" and o.inserted_at >= ^today_start)

    total = Repo.aggregate(paid_today, :sum, :total) || Decimal.new("0")
    count = Repo.aggregate(paid_today, :count, :id)

    %{
      todays_paid_total: total,
      todays_paid_count: count
    }
  end

  @doc """
  Paid sales over the last 7 UTC calendar days (including today).

  Uses `Order.total` aggregates — does not load items.
  """
  def reports_overview do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
    period_start = DateTime.add(today_start, -6, :day)

    paid_period =
      Order
      |> where([o], o.payment_status == "paid" and o.inserted_at >= ^period_start)

    total = Repo.aggregate(paid_period, :sum, :total) || Decimal.new("0")
    count = Repo.aggregate(paid_period, :count, :id)

    %{
      period_paid_total: total,
      period_paid_count: count,
      period_days: 7
    }
  end

  @doc """
  Today's most ordered products from paid orders (UTC calendar day of `inserted_at`).

  Groups by item name and ranks by total quantity. Default limit is 5.
  """
  def popular_products(limit \\ 5) when is_integer(limit) and limit > 0 do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    from(i in OrderItem,
      join: o in assoc(i, :order),
      where: o.payment_status == "paid" and o.inserted_at >= ^today_start,
      group_by: i.name,
      order_by: [desc: sum(i.quantity), asc: i.name],
      limit: ^limit,
      select: %{name: i.name, quantity: sum(i.quantity)}
    )
    |> Repo.all()
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
    |> then(fn query ->
      if Keyword.get(opts, :exclude_cancelled, false) do
        where(query, [o], o.status != "cancelled")
      else
        query
      end
    end)
    |> Repo.aggregate(:count, :id)
  end

  def update_status(%Order{} = order, status) when status in ["received", "preparing", "ready"] do
    order
    |> Order.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Cancels an unpaid order that is still `received` or `preparing`.

  Reloads the order from the database before applying rules.
  """
  def cancel_order(%Order{id: id}) when is_integer(id) do
    case Repo.get(Order, id) do
      nil ->
        {:error, :not_found}

      %Order{} = current ->
        cond do
          current.payment_status == "paid" ->
            {:error, :paid}

          current.status not in ["received", "preparing"] ->
            {:error, :invalid_status}

          true ->
            current
            |> Order.cancel_changeset()
            |> Repo.update()
        end
    end
  end

  @doc """
  Marks an order paid. Reloads from the database first.

  Cancelled orders cannot be paid. Already-paid orders return idempotent success.
  """
  def mark_paid(%Order{id: id}) when is_integer(id) do
    case Repo.get(Order, id) do
      nil ->
        {:error, :not_found}

      %Order{status: "cancelled"} ->
        {:error, :cancelled}

      %Order{payment_status: "paid"} = current ->
        {:ok, current}

      %Order{} = current ->
        current
        |> Order.payment_changeset(%{payment_status: "paid"})
        |> Repo.update()
    end
  end

  def mark_paid(%Order{} = order), do: mark_paid(%Order{id: order.id})

  def format_total(%Order{total: total}), do: Menu.format_price(total)

  def fulfillment_label("dine_in"), do: "Dine-in"
  def fulfillment_label("pickup"), do: "Pickup at counter"
  def fulfillment_label(_), do: "Order"

  def status_label("received"), do: "Received"
  def status_label("preparing"), do: "Preparing"
  def status_label("ready"), do: "Ready"
  def status_label("cancelled"), do: "Cancelled"
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

  # Paid is only allowed for counter (POS pay-at-create). Online stays unpaid.
  defp normalize_payment_status("counter", value) when value in [:paid, "paid"], do: "paid"
  defp normalize_payment_status(_method, _value), do: "unpaid"

  defp normalize_source(value) when value in [:pos, "pos"], do: "pos"
  defp normalize_source(_), do: "customer"

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

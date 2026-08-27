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

  `lines` — maps with `:name`, `:size`, `:quantity`, `:price` (Decimal),
  and preferably `:product_id` (for availability checks).
  `attrs` — `:customer_name`, `:fulfillment` (`:dine_in` | `:pickup` or strings),
  `:table_number`, `:notes`, `:payment_method` (`:counter` | `:online`),
  `:source` (`:customer` | `:pos` or strings; default `"customer"`),
  optional `:payment_status` (`:unpaid` | `:paid`) — `:paid` only allowed with
  `:counter` (POS pay-at-create). Online is always unpaid. Default unpaid.

  Rejects the whole order with `{:error, {:unavailable, names}}` when any
  referenced product is unavailable (application-level check).
  """
  def create_order(lines, attrs) when is_list(lines) and lines != [] do
    case Menu.unavailable_for_order_lines(lines) do
      [] ->
        do_create_order(lines, attrs)

      names ->
        {:error, {:unavailable, names}}
    end
  end

  def create_order([], _attrs), do: {:error, :empty_cart}

  @order_number_chars ~c"23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
  @order_number_suffix_length 6
  @order_number_max_attempts 8

  defp do_create_order(lines, attrs, attempt \\ 1) do
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
      number: generate_order_number(),
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
    |> Ecto.Multi.run(:items, fn repo, %{order: order} ->
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
      {:ok, %{order: order, items: items}} ->
        broadcast({:ok, %{order | items: items}})

      {:error, :order, changeset, _} ->
        if unique_number_conflict?(changeset) and attempt < @order_number_max_attempts do
          do_create_order(lines, attrs, attempt + 1)
        else
          {:error, changeset}
        end

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Subscribes the current process to all order changes (staff queue).
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Espreso.PubSub, topic())
  end

  @doc """
  Subscribes the current process to changes for a single order (customer status).
  """
  def subscribe(%Order{id: id}) when is_integer(id), do: subscribe(id)

  def subscribe(order_id) when is_integer(order_id) do
    Phoenix.PubSub.subscribe(Espreso.PubSub, topic(order_id))
  end

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
  `todays_count` uses the current Asia/Manila shop day of `inserted_at`.
  Cancelled orders are excluded from operational counts.
  """
  def dashboard_overview do
    active_statuses = ["received", "preparing"]
    today_start = shop_day_start_utc()

    %{
      active_count: count_orders(status: active_statuses),
      received_count: count_orders(status: ["received"]),
      preparing_count: count_orders(status: ["preparing"]),
      unpaid_active_count: count_orders(status: active_statuses, payment_status: "unpaid"),
      todays_count: count_orders(inserted_at_gte: today_start, exclude_cancelled: true)
    }
  end

  @doc """
  Recent orders placed on the current Asia/Manila shop day.

  Newest first. Does not preload items. Default limit is 5.
  Excludes cancelled orders.
  """
  def list_todays_orders(limit \\ 5) when is_integer(limit) and limit > 0 do
    today_start = shop_day_start_utc()

    Order
    |> where([o], o.inserted_at >= ^today_start and o.status != "cancelled")
    |> order_by([o], desc: o.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Unpaid orders from the current Asia/Manila shop day.

  Includes received, preparing, ready, and completed. Excludes cancelled and paid.
  Newest first. Does not preload items.
  """
  def list_todays_unpaid do
    today_start = shop_day_start_utc()

    Order
    |> where(
      [o],
      o.inserted_at >= ^today_start and o.payment_status == "unpaid" and
        o.status in ^["received", "preparing", "ready", "completed"]
    )
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Today's paid sales for the dashboard (current Asia/Manila shop day).

  Only `payment_status == "paid"` orders are included. Uses `Order.total`
  aggregates — does not load items.
  """
  def sales_overview do
    today_start = shop_day_start_utc()

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
  Paid sales over the last 7 Asia/Manila shop days (including today).

  Uses `Order.total` aggregates — does not load items.
  """
  def reports_overview do
    today_start = shop_day_start_utc()
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
  Today's most ordered products from paid orders (current Asia/Manila shop day).

  Groups by item name and ranks by total quantity. Default limit is 5.
  """
  def popular_products(limit \\ 5) when is_integer(limit) and limit > 0 do
    today_start = shop_day_start_utc()

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

  # CoffeeSpot shop calendar is Asia/Manila. Philippines Standard Time is UTC+8
  # year-round (no DST). Timestamps stay UTC in the DB; we only shift the day window.
  @shop_utc_offset_seconds 8 * 60 * 60

  @doc false
  def shop_day_start_utc do
    manila_date =
      DateTime.utc_now()
      |> DateTime.add(@shop_utc_offset_seconds, :second)
      |> DateTime.to_date()

    manila_date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.add(-@shop_utc_offset_seconds, :second)
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
    |> broadcast()
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
            |> broadcast()
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
        |> broadcast()
    end
  end

  def mark_paid(%Order{} = order), do: mark_paid(%Order{id: order.id})

  @doc """
  Marks a ready order as picked up / completed.

  Reloads from the database first. Does not change payment_status.
  Already-completed orders return idempotent success without broadcasting.
  """
  def complete_order(%Order{id: id}) when is_integer(id) do
    case Repo.get(Order, id) do
      nil ->
        {:error, :not_found}

      %Order{status: "cancelled"} ->
        {:error, :cancelled}

      %Order{status: "completed"} = current ->
        {:ok, current}

      %Order{status: "ready"} = current ->
        current
        |> Order.complete_changeset()
        |> Repo.update()
        |> broadcast()

      %Order{} ->
        {:error, :invalid_status}
    end
  end

  def complete_order(%Order{} = order), do: complete_order(%Order{id: order.id})

  def format_total(%Order{total: total}), do: Menu.format_price(total)

  def fulfillment_label("dine_in"), do: "Dine-in"
  def fulfillment_label("pickup"), do: "Pickup at counter"
  def fulfillment_label(_), do: "Order"

  def status_label("received"), do: "Received"
  def status_label("preparing"), do: "Preparing"
  def status_label("ready"), do: "Ready"
  def status_label("completed"), do: "Picked up"
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

  def order_number_pattern, do: ~r/^CS-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$/

  defp generate_order_number do
    "CS-" <> random_order_suffix(@order_number_suffix_length)
  end

  defp random_order_suffix(length) do
    alphabet = @order_number_chars
    size = length(alphabet)

    :crypto.strong_rand_bytes(length)
    |> :binary.bin_to_list()
    |> Enum.map(fn byte ->
      <<Enum.at(alphabet, rem(byte, size))>>
    end)
    |> IO.iodata_to_binary()
  end

  defp unique_number_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.constraints, &(&1.type == :unique and &1.field == :number)) and
      Keyword.has_key?(changeset.errors, :number)
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

  defp topic, do: "orders"
  defp topic(order_id) when is_integer(order_id), do: "orders:#{order_id}"

  defp broadcast({:ok, %Order{} = order} = result) do
    message = {:order_changed, order}
    Phoenix.PubSub.broadcast(Espreso.PubSub, topic(), message)
    Phoenix.PubSub.broadcast(Espreso.PubSub, topic(order.id), message)
    result
  end

  defp broadcast(other), do: other

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

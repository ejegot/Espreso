defmodule Espreso.Orders do
  @moduledoc """
  Cafe order placement and staff status updates.
  """

  import Ecto.Query

  alias Espreso.Repo
  alias Espreso.BusinessSettings
  alias Espreso.Orders.{Order, OrderItem, PaymentReconciliation}
  alias Espreso.Menu

  @unpaid_payment_statuses ~w(unpaid awaiting_payment)
  @paid_vias ~w(cash gcash maya counter paymongo)
  # CoffeeSpot shop calendar is Asia/Manila. Philippines Standard Time is UTC+8
  # year-round (no DST). Timestamps stay UTC in the DB; we only shift the day window.
  @shop_utc_offset_seconds 8 * 60 * 60

  @doc """
  Creates an order from cart lines and checkout attrs.

  `lines` — maps with `:name`, `:size`, `:quantity`, `:price` (Decimal),
  and preferably `:product_id` (for availability checks).
  `attrs` — `:customer_name`, `:fulfillment` (`:dine_in` | `:pickup` or strings),
  `:table_number`, `:notes`, `:payment_method` (`:counter` | `:online`),
  `:source` (`:customer` | `:pos` or strings; default `"customer"`),
  optional `:payment_status` (`:unpaid` | `:awaiting_payment` | `:paid`) — `:paid` only
  allowed with `:counter` (POS pay-at-create). Online uses shop `payments_mode`.

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
        Map.get(attrs, :payment_status) || Map.get(attrs, "payment_status"),
        BusinessSettings.payments_mode()
      )

    paid_via =
      if payment_status == "paid" do
        normalize_paid_via_attr(Map.get(attrs, :paid_via) || Map.get(attrs, "paid_via"))
      else
        nil
      end

    online_wallet =
      normalize_online_wallet(Map.get(attrs, :online_wallet) || Map.get(attrs, "online_wallet"))

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
      paid_via: paid_via,
      online_wallet: online_wallet,
      source: source,
      status: if(payment_status == "paid", do: "preparing", else: "received"),
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

  @doc """
  Loads orders for the given order numbers.

  - Ignores blank/invalid numbers
  - Caps input length
  - Returns only matching rows, newest first (`inserted_at` desc)
  - Missing numbers are omitted (no error)
  """
  def list_orders_by_numbers(numbers) when is_list(numbers) do
    cleaned =
      numbers
      |> Enum.map(&normalize_lookup_number/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(40)

    if cleaned == [] do
      []
    else
      Order
      |> where([o], o.number in ^cleaned)
      |> order_by([o], desc: o.inserted_at)
      |> preload(:items)
      |> Repo.all()
    end
  end

  def list_orders_by_numbers(_), do: []

  defp normalize_lookup_number(number) when is_binary(number) do
    trimmed = String.trim(number)

    if Regex.match?(order_number_pattern(), trimmed), do: trimmed, else: nil
  end

  defp normalize_lookup_number(_), do: nil

  def list_active_orders do
    Order
    |> where([o], o.status in ^["received", "preparing"])
    |> order_by([o], asc: o.inserted_at)
    |> preload(:items)
    |> Repo.all()
  end

  @doc """
  Lists orders for the staff API.

  Supported `scope` values: `active` (default), `unpaid`, `today`.
  """
  def list_orders_for_api(scope \\ "active") when is_binary(scope) do
    orders =
      case scope do
        "unpaid" -> list_todays_unpaid()
        "today" -> list_todays_orders(100)
        _ -> list_active_orders()
      end

    Repo.preload(orders, :items)
  end

  @doc """
  Loads a single order with items for the staff API.
  """
  def get_order_for_api(id) when is_integer(id) do
    case Repo.get(Order, id) |> Repo.preload(:items) do
      nil -> {:error, :not_found}
      %Order{} = order -> {:ok, order}
    end
  end

  @doc """
  Updates order status from the staff API.

  Accepts `received`, `preparing`, `ready`, `completed`, and `cancelled`.
  """
  def update_status_for_api(%Order{} = order, status) when is_binary(status) do
    case status do
      status when status in ["received", "preparing", "ready"] ->
        update_status(order, status)

      "completed" ->
        complete_order(order)

      "cancelled" ->
        cancel_order_for_api(order)

      _ ->
        {:error, :invalid_status}
    end
  end

  defp cancel_order_for_api(%Order{payment_method: "online", paymongo_checkout_session_id: session_id} = order)
       when is_binary(session_id) and session_id != "" do
    abandon_online_payment(order)
  end

  defp cancel_order_for_api(%Order{} = order), do: cancel_order(order)

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
      unpaid_active_count:
        count_orders(status: active_statuses, payment_status: @unpaid_payment_statuses),
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
      o.inserted_at >= ^today_start and o.payment_status in ^@unpaid_payment_statuses and
        o.status in ^["received", "preparing", "ready", "completed"]
    )
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Today's paid sales broken down by `paid_via` (current Asia/Manila shop day).

  Only `payment_status == "paid"` orders are included. Cancelled orders that
  somehow remain paid are still counted if paid (cancel is unpaid-only in practice).
  Nil/`paid_via` values are rolled into `"counter"`.
  """
  def todays_paid_breakdown do
    today_start = shop_day_start_utc()

    rows =
      from(o in Order,
        where: o.payment_status == "paid" and o.inserted_at >= ^today_start,
        group_by: o.paid_via,
        select: {o.paid_via, count(o.id), sum(o.total)}
      )
      |> Repo.all()

    empty = %{total: Decimal.new("0"), count: 0}

    by_via =
      Map.new(@paid_vias, fn via -> {via, empty} end)

    by_via =
      Enum.reduce(rows, by_via, fn {via, count, total}, acc ->
        key = if via in @paid_vias, do: via, else: "counter"
        current = Map.fetch!(acc, key)

        Map.put(acc, key, %{
          count: current.count + count,
          total: Decimal.add(current.total, decimalize(total))
        })
      end)

    total =
      by_via
      |> Map.values()
      |> Enum.reduce(Decimal.new("0"), fn %{total: t}, acc -> Decimal.add(acc, t) end)

    count =
      by_via
      |> Map.values()
      |> Enum.reduce(0, fn %{count: c}, acc -> acc + c end)

    %{
      total: total,
      count: count,
      by_via: by_via,
      shop_date: shop_date_today()
    }
  end

  @doc """
  Current shop calendar date in Asia/Manila.
  """
  def shop_date_today do
    DateTime.utc_now()
    |> DateTime.add(@shop_utc_offset_seconds, :second)
    |> DateTime.to_date()
  end

  @doc """
  Today's paid sales for the dashboard (current Asia/Manila shop day).

  Only `payment_status == "paid"` orders are included. Uses `Order.total`
  aggregates — does not load items.
  """
  def sales_overview do
    breakdown = todays_paid_breakdown()

    %{
      todays_paid_total: breakdown.total,
      todays_paid_count: breakdown.count
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

  defp decimalize(%Decimal{} = value), do: value
  defp decimalize(value) when is_integer(value), do: Decimal.new(value)
  defp decimalize(value) when is_float(value), do: Decimal.from_float(value)
  defp decimalize(_), do: Decimal.new("0")

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

  # CoffeeSpot shop calendar helpers live above; kept here for call-site clarity.

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
        statuses when is_list(statuses) -> where(query, [o], o.payment_status in ^statuses)
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

  def update_status(%Order{id: id}, status)
      when is_integer(id) and status in ["received", "preparing", "ready"] do
    case Repo.get(Order, id) do
      nil ->
        {:error, :not_found}

      %Order{} = current ->
        if status == "ready" and unpaid?(current) do
          {:error, :payment_required}
        else
          current
          |> Order.status_changeset(status)
          |> Repo.update()
          |> broadcast()
        end
    end
  end

  def update_status(%Order{} = order, status) when status in ["received", "preparing", "ready"] do
    update_status(%Order{id: order.id}, status)
  end

  @doc """
  True when payment is still unpaid or awaiting payment.
  """
  def unpaid?(%Order{payment_status: status}) when status in @unpaid_payment_statuses, do: true
  def unpaid?(_order), do: false

  @doc """
  Cancels an unpaid order that is still `received` or `preparing`.

  Reloads the order from the database before applying rules.
  Orders with an attached PayMongo checkout session cannot be cancelled
  (`{:error, :checkout_in_progress}`).
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

          checkout_session_attached?(current) ->
            {:error, :checkout_in_progress}

          true ->
            atomically_cancel_order(id, :without_session)
        end
    end
  end

  @doc """
  Abandons an unpaid online order that has an attached PayMongo checkout session.

  Sets status to `cancelled` while leaving `payment_status` unpaid and preserving
  `paymongo_checkout_session_id` so a late paid webhook cannot mark the order paid
  (ESP-83 `:order_cancelled` path).

  Use this instead of `cancel_order/1` when a checkout session is attached.
  """
  def abandon_online_payment(%Order{id: id}) when is_integer(id) do
    case Repo.get(Order, id) do
      nil ->
        {:error, :not_found}

      %Order{} = current ->
        cond do
          current.payment_status == "paid" ->
            {:error, :paid}

          current.payment_method != "online" ->
            {:error, :not_online}

          current.status not in ["received", "preparing"] ->
            {:error, :invalid_status}

          not checkout_session_attached?(current) ->
            {:error, :missing_checkout_session}

          true ->
            atomically_cancel_order(id, :with_online_session)
        end
    end
  end

  def abandon_online_payment(%Order{} = order), do: abandon_online_payment(%Order{id: order.id})

  @doc """
  Marks an order paid via the staff/manual path. Reloads from the database first.

  Options:
  - `:paid_via` — `"cash"`, `"gcash"`, `"maya"`, `"counter"` (default `"counter"` for
    counter orders). PayMongo webhooks use `"paymongo"` internally.

  Cancelled orders cannot be paid. Already-paid orders return idempotent success.
  Unpaid online PayMongo orders cannot be marked paid manually
  (`{:error, :online_payment_required}`). Online `awaiting_payment` orders can be
  confirmed when shop `payments_mode` is `qrph_manual`.
  """
  def mark_paid(order, opts \\ [])
  def mark_paid(%Order{id: id}, opts) when is_integer(id) do
    paid_via = normalize_paid_via(opts)

    case Repo.get(Order, id) do
      nil ->
        {:error, :not_found}

      %Order{status: "cancelled"} ->
        {:error, :cancelled}

      %Order{payment_status: "paid"} = current ->
        {:ok, current}

      %Order{payment_method: "online", payment_status: "awaiting_payment"} = current ->
        if BusinessSettings.qrph_manual?() do
          apply_paid(current, paid_via)
        else
          {:error, :online_payment_required}
        end

      %Order{payment_method: "online"} ->
        {:error, :online_payment_required}

      %Order{} = current ->
        apply_paid(current, paid_via)
    end
  end

  def mark_paid(%Order{} = order, opts), do: mark_paid(%Order{id: order.id}, opts)

  @doc """
  Stores the PayMongo checkout session id on an order after session creation.

  Attaching the same session id again to the same order is idempotent.
  A session id already stored on another order is rejected by the unique
  database constraint (returned as an Ecto changeset error).
  Cancelled orders cannot receive a session (`{:error, :cancelled}`).
  """
  def attach_paymongo_session(%Order{id: id}, session_id) when is_binary(session_id) do
    case Repo.get(Order, id) do
      nil ->
        {:error, :not_found}

      %Order{status: "cancelled"} ->
        {:error, :cancelled}

      %Order{paymongo_checkout_session_id: ^session_id} = order ->
        {:ok, order}

      %Order{} = order ->
        order
        |> Order.payment_changeset(%{paymongo_checkout_session_id: session_id})
        |> Repo.update()
    end
  end

  @doc """
  Marks an order paid from a PayMongo webhook using the order number reference.

  Bypasses the staff/manual online restriction on `mark_paid/1`.
  """
  def mark_paid_from_paymongo(reference_number, _session_id \\ nil)
      when is_binary(reference_number) do
    case Repo.get_by(Order, number: reference_number) do
      nil ->
        {:error, :not_found}

      %Order{} = order ->
        apply_paid(order, "paymongo")
    end
  end

  @doc """
  Marks an order paid from a PayMongo webhook using the checkout session id.

  Bypasses the staff/manual online restriction on `mark_paid/2`.
  """
  def mark_paid_from_paymongo_session(session_id) when is_binary(session_id) do
    case Repo.get_by(Order, paymongo_checkout_session_id: session_id) do
      nil -> {:error, :not_found}
      %Order{} = order -> apply_paid(order, "paymongo")
    end
  end

  @doc """
  Marks a ready order as picked up / completed.

  Reloads from the database first. Does not change payment_status.
  Unpaid orders cannot be completed (`{:error, :payment_required}`).
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
        if unpaid?(current) do
          {:error, :payment_required}
        else
          current
          |> Order.complete_changeset()
          |> Repo.update()
          |> broadcast()
        end

      %Order{} ->
        {:error, :invalid_status}
    end
  end

  def complete_order(%Order{} = order), do: complete_order(%Order{id: order.id})

  @doc """
  Records a verified PayMongo payment that could not be applied because the
  order was already cancelled. Idempotent on `paymongo_checkout_session_id`.
  """
  def record_paymongo_reconciliation(attrs) when is_map(attrs) do
    session_id = Map.fetch!(attrs, :paymongo_checkout_session_id)

    case %PaymentReconciliation{}
         |> PaymentReconciliation.changeset(attrs)
         |> Repo.insert(on_conflict: :nothing, conflict_target: :paymongo_checkout_session_id) do
      {:ok, %PaymentReconciliation{id: id}} when is_integer(id) ->
        {:ok, Repo.get!(PaymentReconciliation, id)}

      {:ok, _} ->
        case Repo.get_by(PaymentReconciliation, paymongo_checkout_session_id: session_id) do
          %PaymentReconciliation{} = record -> {:ok, record}
          nil -> {:error, :not_persisted}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Lists all open PayMongo payment reconciliation records, newest first.
  """
  def list_open_paymongo_reconciliations do
    PaymentReconciliation
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  def format_reconciliation_amount(centavos) when is_integer(centavos) do
    centavos
    |> Decimal.new()
    |> Decimal.div(100)
    |> Menu.format_price()
  end

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

  def payment_label(%Order{payment_method: "counter", payment_status: "paid", paid_via: paid_via})
      when paid_via in ["gcash", "maya"] do
    "Paid via #{wallet_brand_label(paid_via)}"
  end

  def payment_label(%Order{payment_method: "counter", payment_status: "paid"}),
    do: "Paid at counter"

  def payment_label(%Order{
        payment_method: "online",
        payment_status: "awaiting_payment",
        online_wallet: wallet
      })
      when wallet in ["gcash", "maya"] do
    "Awaiting #{wallet_brand_label(wallet)} payment"
  end

  def payment_label(%Order{payment_method: "online", payment_status: "awaiting_payment"}),
    do: "Awaiting QR payment"

  def payment_label(%Order{payment_method: "online", payment_status: "paid", paid_via: paid_via})
      when paid_via in ["gcash", "maya"] do
    "Paid via #{wallet_brand_label(paid_via)}"
  end

  def payment_label(%Order{payment_method: "online", payment_status: "paid"}),
    do: "Paid online"

  def payment_label(%Order{payment_method: "online", payment_status: "unpaid"}),
    do: "Awaiting online payment"

  def payment_label(_), do: "Payment"

  def wallet_brand_label("gcash"), do: "GCash"
  def wallet_brand_label("maya"), do: "Maya"
  def wallet_brand_label(_), do: "Online"

  def paid_via_label("cash"), do: "Cash"
  def paid_via_label("gcash"), do: "GCash"
  def paid_via_label("maya"), do: "Maya"
  def paid_via_label("counter"), do: "Counter"
  def paid_via_label("paymongo"), do: "PayMongo"
  def paid_via_label(_), do: "Other"

  def paid_via_rows(%{by_via: by_via}) when is_map(by_via) do
    Enum.map(~w(cash gcash maya counter paymongo), fn via ->
      entry = Map.get(by_via, via, %{total: Decimal.new("0"), count: 0})
      %{via: via, label: paid_via_label(via), total: entry.total, count: entry.count}
    end)
  end

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

  # Paid is only allowed for counter (POS pay-at-create).
  defp normalize_payment_status("counter", value, _mode) when value in [:paid, "paid"],
    do: "paid"

  defp normalize_payment_status("counter", _value, _mode), do: "unpaid"

  defp normalize_payment_status("online", _value, "qrph_manual"), do: "awaiting_payment"
  defp normalize_payment_status("online", _value, _mode), do: "unpaid"

  defp normalize_paid_via(opts) when is_list(opts) do
    case Keyword.get(opts, :paid_via) do
      value when value in @paid_vias -> value
      value when is_atom(value) -> value |> Atom.to_string() |> normalize_paid_via_value()
      _ -> "counter"
    end
  end

  defp normalize_paid_via_value(value) when value in @paid_vias, do: value
  defp normalize_paid_via_value(_), do: "counter"

  defp normalize_paid_via_attr(value) when value in @paid_vias, do: value

  defp normalize_paid_via_attr(value) when is_atom(value) do
    value |> Atom.to_string() |> normalize_paid_via_attr()
  end

  defp normalize_paid_via_attr(_), do: "cash"

  defp normalize_online_wallet(value) when value in ["gcash", "maya"], do: value

  defp normalize_online_wallet(value) when value in [:gcash, :maya],
    do: value |> Atom.to_string()

  defp normalize_online_wallet(_), do: nil

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

  # Verified PayMongo path — does not enforce the staff/manual online restriction.
  defp apply_paid(%Order{id: order_id}, paid_via) do
    invoke_apply_paid_barrier!()

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    paid_via = normalize_paid_via_value(paid_via)

    # Confirm payment advances New → Preparing so staff skip an extra tap.
    # Do not regress preparing / ready / completed.
    {count, _} =
      from(o in Order,
        where: o.id == ^order_id and o.status != "cancelled" and o.payment_status != "paid",
        update: [
          set: [
            payment_status: "paid",
            paid_via: ^paid_via,
            status:
              fragment("CASE WHEN status = 'received' THEN 'preparing' ELSE status END"),
            updated_at: ^now
          ]
        ]
      )
      |> Repo.update_all([])

    case count do
      1 ->
        order = Repo.get!(Order, order_id)
        broadcast({:ok, order})

      0 ->
        case Repo.get(Order, order_id) do
          nil ->
            {:error, :not_found}

          %Order{payment_status: "paid"} = order ->
            {:ok, order}

          %Order{status: "cancelled"} ->
            {:error, :cancelled}

          %Order{} = order ->
            {:error, {:unexpected_apply_paid_state, order}}
        end

      _ ->
        {:error, :unexpected_update_count}
    end
  end

  defp atomically_cancel_order(order_id, scope)
       when is_integer(order_id) and scope in [:without_session, :with_online_session] do
    invoke_cancel_barrier!()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    base_query =
      from o in Order,
        where:
          o.id == ^order_id and o.status in ["received", "preparing"] and
            o.payment_status != "paid"

    scoped_query =
      case scope do
        :without_session -> without_checkout_session(base_query)
        :with_online_session -> with_online_checkout_session(base_query)
      end

    {count, _} =
      scoped_query
      |> update([o], set: [status: "cancelled", updated_at: ^now])
      |> Repo.update_all([])

    case count do
      1 ->
        order = Repo.get!(Order, order_id)
        broadcast({:ok, order})

      0 ->
        case Repo.get(Order, order_id) do
          nil ->
            {:error, :not_found}

          %Order{payment_status: "paid"} ->
            {:error, :paid}

          %Order{status: status} when status not in ["received", "preparing"] ->
            {:error, :invalid_status}

          %Order{} = order ->
            interpret_cancel_conflict(order, scope)
        end

      _ ->
        {:error, :unexpected_update_count}
    end
  end

  defp interpret_cancel_conflict(%Order{} = order, :with_online_session) do
    cond do
      order.payment_method != "online" ->
        {:error, :not_online}

      not checkout_session_attached?(order) ->
        {:error, :missing_checkout_session}

      true ->
        {:error, :invalid_status}
    end
  end

  defp interpret_cancel_conflict(%Order{} = order, :without_session) do
    if checkout_session_attached?(order) do
      {:error, :checkout_in_progress}
    else
      {:error, :invalid_status}
    end
  end

  defp without_checkout_session(query) do
    from o in query,
      where: is_nil(o.paymongo_checkout_session_id) or o.paymongo_checkout_session_id == ""
  end

  defp with_online_checkout_session(query) do
    from o in query,
      where: o.payment_method == "online",
      where: not is_nil(o.paymongo_checkout_session_id) and o.paymongo_checkout_session_id != ""
  end

  defp invoke_apply_paid_barrier! do
    case Application.get_env(:espreso, :orders_apply_paid_barrier) do
      fun when is_function(fun, 0) -> fun.()
      _ -> :ok
    end
  end

  defp invoke_cancel_barrier! do
    case Application.get_env(:espreso, :orders_cancel_barrier) do
      fun when is_function(fun, 0) -> fun.()
      _ -> :ok
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp checkout_session_attached?(%Order{paymongo_checkout_session_id: session_id})
       when is_binary(session_id) and session_id != "" do
    true
  end

  defp checkout_session_attached?(_order), do: false
end

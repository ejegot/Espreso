defmodule Espreso.Orders do
  @moduledoc """
  Cafe order placement and staff status updates.
  """

  import Ecto.Query
  require Logger

  alias Espreso.Repo
  alias Espreso.BusinessSettings
  alias Espreso.Loyalty
  alias Espreso.Orders.{Order, OrderItem, PaymentReconciliation}
  alias Espreso.Menu
  alias Espreso.Menu.ProductPrice
  alias Espreso.StaffShifts.StaffShift

  @unpaid_payment_statuses ~w(unpaid awaiting_payment)
  @paid_vias ~w(cash gcash maya counter paymongo)
  # CoffeeSpot shop calendar is Asia/Manila. Philippines Standard Time is UTC+8
  # year-round (no DST). Timestamps stay UTC in the DB; we only shift the day window.
  @shop_utc_offset_seconds 8 * 60 * 60
  # Staff Transactions list page size (keyset). Summary remains unpaginated.
  @transaction_page_size 50
  # Staff Orders reconciliation drawer — exception/audit rows, newest first.
  @paymongo_reconciliation_list_limit 50

  @doc """
  Creates an order from cart lines and checkout attrs.

  `lines` — maps with `:name`, `:size`, `:quantity`, `:price` (Decimal),
  and preferably `:product_id` (for availability checks). POS lines must also
  include `:price_id`; their expected prices are checked against locked,
  authoritative product-price rows before the order is inserted.
  `attrs` — `:customer_name`, `:fulfillment` (`:dine_in` | `:pickup` or strings),
  `:table_number`, `:notes`, `:payment_method` (`:counter` | `:online`),
  `:source` (`:customer` | `:pos` or strings; default `"customer"`),
  optional `:customer_id`, optional `:loyalty_free_amount_centavos` (default 0),
  optional `:payment_status` (`:unpaid` | `:awaiting_payment` | `:paid`) — `:paid` only
  allowed with `:counter` (POS pay-at-create). Online uses shop `payments_mode`.
  optional `:skip_loyalty_earn` — when true, caller owns loyalty earning (redemption Multi).
  optional `:skip_authoritative_prices` — when true, POS catalog price lock is skipped
  (loyalty reward lines charge upgrade-only amounts).

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
        paid_via_attr(attrs)
      else
        nil
      end

    payment_intent =
      normalize_payment_intent(
        Map.get(attrs, :payment_intent) || Map.get(attrs, "payment_intent")
      )

    case validate_paid_at_create(payment_status, payment_method, payment_intent, paid_via) do
      {:ok, _validation} ->
        persist_order(
          lines,
          attrs,
          attempt,
          fulfillment,
          payment_method,
          payment_status,
          paid_via,
          payment_intent,
          source
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp persist_order(
         lines,
         attrs,
         attempt,
         fulfillment,
         payment_method,
         payment_status,
         paid_via,
         payment_intent,
         source
       ) do
    total =
      Enum.reduce(lines, Decimal.new(0), fn line, acc ->
        Decimal.add(acc, Decimal.mult(line.price, line.quantity))
      end)

    with {:ok, settlement_attrs} <-
           build_settlement_attrs(payment_status, paid_via, total, attrs,
             default_source: if(source == "pos", do: "pos", else: "manual")
           ) do
      customer_id = Map.get(attrs, :customer_id) || Map.get(attrs, "customer_id")

      loyalty_free =
        case Map.get(attrs, :loyalty_free_amount_centavos) ||
               Map.get(attrs, "loyalty_free_amount_centavos") do
          nil -> 0
          n when is_integer(n) and n >= 0 -> n
          other -> Loyalty.to_centavos(other)
        end

      order_attrs =
        %{
          number: generate_order_number(),
          customer_name: Map.get(attrs, :customer_name) || Map.get(attrs, "customer_name"),
          fulfillment: fulfillment,
          table_number: Map.get(attrs, :table_number) || Map.get(attrs, "table_number"),
          notes: blank_to_nil(Map.get(attrs, :notes) || Map.get(attrs, "notes")),
          payment_method: payment_method,
          payment_status: payment_status,
          paid_via: paid_via,
          payment_intent: payment_intent,
          source: source,
          status: if(payment_status == "paid", do: "preparing", else: "received"),
          total: total,
          customer_id: customer_id,
          loyalty_free_amount_centavos: loyalty_free
        }
        |> Map.merge(settlement_attrs)

      skip_prices? =
        Map.get(attrs, :skip_authoritative_prices) == true or
          Map.get(attrs, "skip_authoritative_prices") == true

      skip_earn? =
        Map.get(attrs, :skip_loyalty_earn) == true or
          Map.get(attrs, "skip_loyalty_earn") == true

      Ecto.Multi.new()
      |> Ecto.Multi.run(:prices, fn repo, _changes ->
        if skip_prices? do
          {:ok, :skipped}
        else
          validate_authoritative_prices(repo, lines, source)
        end
      end)
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
          order = %{order | items: items}

          _ =
            if payment_status == "paid" and not skip_earn? do
              attempt_loyalty_earn(order)
            else
              {:ok, :skipped}
            end

          broadcast({:ok, order})

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
  end

  defp validate_authoritative_prices(_repo, _lines, source) when source != "pos",
    do: {:ok, :skip}

  defp validate_authoritative_prices(repo, lines, "pos") do
    price_ids =
      lines
      |> Enum.map(&Map.get(&1, :price_id))
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    prices_by_id =
      ProductPrice
      |> where([price], price.id in ^price_ids)
      |> lock("FOR SHARE")
      |> repo.all()
      |> Map.new(&{&1.id, &1})

    changed_names =
      lines
      |> Enum.reject(&authoritative_price?(&1, prices_by_id))
      |> Enum.map(&(Map.get(&1, :name) || "Item"))
      |> Enum.uniq()

    if changed_names == [] do
      {:ok, :validated}
    else
      {:error, {:price_changed, changed_names}}
    end
  end

  defp authoritative_price?(line, prices_by_id) do
    with product_id when is_integer(product_id) <- Map.get(line, :product_id),
         price_id when is_integer(price_id) <- Map.get(line, :price_id),
         %Decimal{} = expected_price <- Map.get(line, :price),
         %ProductPrice{product_id: ^product_id, price: authoritative_price} <-
           Map.get(prices_by_id, price_id) do
      Decimal.equal?(expected_price, authoritative_price)
    else
      _ -> false
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

  @doc """
  Lists paid receipt transactions for one Asia/Manila shop day.

  Supported filters are `date`, `search`, `payment`, `status`, and `source`.
  Results are newest-settled first (`settled_at DESC`, `id DESC`).

  Optional `opts`:
  - `:limit` — page size (default #{@transaction_page_size}, clamped 1..100)
  - `:cursor` — `%{settled_at: DateTime.t(), id: integer()}` from the previous
    page's last row; fetches strictly older rows in the same order

  Returns `%{orders, filters, has_next_page, next_cursor}`.
  `transaction_summary/1` is intentionally separate and unpaginated.
  """
  def list_transactions(filters \\ %{}, opts \\ [])

  def list_transactions(filters, opts) when is_map(filters) and is_list(opts) do
    {query, normalized} = transaction_query(filters)

    limit =
      opts
      |> Keyword.get(
        :limit,
        Application.get_env(:espreso, :transaction_page_size, @transaction_page_size)
      )
      |> transaction_page_limit()

    cursor = normalize_transaction_cursor(Keyword.get(opts, :cursor))

    query =
      query
      |> apply_transaction_cursor(cursor)
      |> order_by([o], desc: o.settled_at, desc: o.id)
      |> limit(^(limit + 1))
      |> preload([:items, :settled_by_user])

    rows = Repo.all(query)
    has_next_page? = length(rows) > limit
    orders = Enum.take(rows, limit)

    next_cursor =
      if has_next_page? do
        case List.last(orders) do
          %{settled_at: %DateTime{} = settled_at, id: id} when is_integer(id) ->
            %{settled_at: settled_at, id: id}

          _ ->
            nil
        end
      else
        nil
      end

    %{
      orders: orders,
      filters: normalized,
      has_next_page: has_next_page?,
      next_cursor: next_cursor
    }
  end

  defp transaction_page_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, 100)
  defp transaction_page_limit(_), do: @transaction_page_size

  defp normalize_transaction_cursor(%{settled_at: %DateTime{} = settled_at, id: id})
       when is_integer(id) and id > 0 do
    %{settled_at: DateTime.truncate(settled_at, :second), id: id}
  end

  defp normalize_transaction_cursor(%{"settled_at" => settled_at, "id" => id}) do
    normalize_transaction_cursor(%{settled_at: settled_at, id: id})
  end

  defp normalize_transaction_cursor(_), do: nil

  defp apply_transaction_cursor(query, nil), do: query

  defp apply_transaction_cursor(query, %{settled_at: settled_at, id: id}) do
    from(o in query,
      where:
        o.settled_at < ^settled_at or
          (o.settled_at == ^settled_at and o.id < ^id)
    )
  end

  @doc """
  Returns exact paid count, total, and payment-method breakdown for transaction filters.
  """
  def transaction_summary(filters \\ %{}) when is_map(filters) do
    {query, normalized} = transaction_query(filters)

    rows =
      query
      |> group_by([o], o.paid_via)
      |> select([o], {o.paid_via, count(o.id), sum(o.total)})
      |> Repo.all()

    empty = %{total: Decimal.new("0"), count: 0}
    by_via = Map.new(@paid_vias, &{&1, empty})

    by_via =
      Enum.reduce(rows, by_via, fn {via, count, total}, acc ->
        key = if via in @paid_vias, do: via, else: "counter"
        current = Map.fetch!(acc, key)

        Map.put(acc, key, %{
          count: current.count + count,
          total: Decimal.add(current.total, decimalize(total))
        })
      end)

    %{
      filters: normalized,
      count: Enum.reduce(by_via, 0, fn {_via, row}, acc -> acc + row.count end),
      total:
        Enum.reduce(by_via, Decimal.new("0"), fn {_via, row}, acc ->
          Decimal.add(acc, row.total)
        end),
      by_via: by_via
    }
  end

  @doc """
  Loads one paid receipt transaction with its items and settlement staff.
  """
  def get_transaction(id) when is_integer(id) do
    Order
    |> where([o], o.id == ^id and o.payment_status == "paid" and not is_nil(o.settled_at))
    |> preload([:items, :settled_by_user])
    |> Repo.one()
  end

  def get_transaction(_), do: nil

  @doc """
  Paid POS sales attributed to one staff attendance shift.

  Credit belongs to the settler (`settled_by_user_id`) for orders with
  `source == "pos"` whose `settled_at` falls in the half-open window
  `[started_at, ended_at)`. Open shifts (`ended_at` nil) have no upper bound.

  Does not filter by `settlement_source` or `paid_via`. Customer / PayMongo
  orders are excluded via `source != "pos"`.
  """
  def sales_summary_for_staff_shift(%StaffShift{} = shift) do
    query =
      from(o in Order,
        where:
          o.payment_status == "paid" and o.source == "pos" and
            o.settled_by_user_id == ^shift.user_id and not is_nil(o.settled_at) and
            o.settled_at >= ^shift.started_at
      )

    query =
      case shift.ended_at do
        nil -> query
        ended_at -> from(o in query, where: o.settled_at < ^ended_at)
      end

    {count, total} =
      Repo.one(from(o in query, select: {count(o.id), sum(o.total)})) || {0, nil}

    %{order_count: count, total: decimalize(total)}
  end

  defp normalize_lookup_number(number) when is_binary(number) do
    trimmed = String.trim(number)

    if Regex.match?(order_number_pattern(), trimmed), do: trimmed, else: nil
  end

  defp normalize_lookup_number(_), do: nil

  defp transaction_query(filters) do
    normalized = normalize_transaction_filters(filters)
    {day_start, day_end} = shop_day_bounds_utc(normalized.date)

    query =
      from(o in Order,
        where:
          o.payment_status == "paid" and not is_nil(o.settled_at) and
            o.settled_at >= ^day_start and o.settled_at < ^day_end
      )
      |> filter_transaction_search(normalized.search)
      |> filter_transaction_value(:paid_via, normalized.payment)
      |> filter_transaction_value(:status, normalized.status)
      |> filter_transaction_value(:settlement_source, normalized.source)

    {query, normalized}
  end

  defp normalize_transaction_filters(filters) do
    %{
      date: normalize_transaction_date(filter_value(filters, :date)),
      search: normalize_transaction_search(filter_value(filters, :search)),
      payment:
        normalize_transaction_filter(
          filter_value(filters, :payment),
          @paid_vias
        ),
      status:
        normalize_transaction_filter(
          filter_value(filters, :status),
          ~w(received preparing ready completed)
        ),
      source:
        normalize_transaction_filter(
          filter_value(filters, :source),
          Order.settlement_sources()
        )
    }
  end

  defp filter_value(filters, key) do
    case Map.fetch(filters, key) do
      {:ok, value} -> value
      :error -> Map.get(filters, Atom.to_string(key))
    end
  end

  defp normalize_transaction_date(%Date{} = date), do: date

  defp normalize_transaction_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> shop_date_today()
    end
  end

  defp normalize_transaction_date(_), do: shop_date_today()

  defp normalize_transaction_search(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, 60)
  end

  defp normalize_transaction_search(_), do: ""

  defp normalize_transaction_filter(value, allowed) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_transaction_filter(allowed)

  defp normalize_transaction_filter(value, allowed) when is_binary(value) do
    if value in allowed, do: value, else: "all"
  end

  defp normalize_transaction_filter(_, _allowed), do: "all"

  defp filter_transaction_search(query, ""), do: query

  defp filter_transaction_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [o],
      ilike(o.number, ^pattern) or
        ilike(fragment("COALESCE(?, '')", o.customer_name), ^pattern)
    )
  end

  defp filter_transaction_value(query, _field, "all"), do: query

  defp filter_transaction_value(query, field_name, value),
    do: where(query, [o], field(o, ^field_name) == ^value)

  def list_active_orders do
    Order
    |> where([o], o.status in ^["received", "preparing"])
    |> order_by([o], asc: o.inserted_at, asc: o.id)
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

  defp cancel_order_for_api(
         %Order{payment_method: "online", paymongo_checkout_session_id: session_id} = order
       )
       when is_binary(session_id) and session_id != "" do
    abandon_online_payment(order)
  end

  defp cancel_order_for_api(%Order{} = order), do: cancel_order(order)

  def list_recent_ready(limit \\ 10) do
    Order
    |> where([o], o.status == "ready")
    |> order_by([o], desc: o.updated_at, desc: o.id)
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
    todays_unpaid_query()
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> Repo.all()
  end

  @doc """
  Count of today's unpaid orders (same filters as `list_todays_unpaid/0`).

  Database aggregate only — does not load order rows.
  """
  def count_todays_unpaid do
    todays_unpaid_query()
    |> Repo.aggregate(:count, :id)
  end

  defp todays_unpaid_query do
    today_start = shop_day_start_utc()

    from(o in Order,
      where:
        o.inserted_at >= ^today_start and o.payment_status in ^@unpaid_payment_statuses and
          o.status in ^["received", "preparing", "ready", "completed"]
    )
  end

  @doc """
  Recent orders linked to a customer via `customer_id`.

  Newest first. Default limit is 25. Preloads items for a compact staff summary.
  Does not include anonymous / name-only orders (`customer_id` nil).
  """
  def list_orders_for_customer(customer_id, opts \\ [])

  def list_orders_for_customer(customer_id, opts)
      when is_integer(customer_id) and is_list(opts) do
    limit =
      case Keyword.get(opts, :limit, 25) do
        n when is_integer(n) and n > 0 -> min(n, 100)
        _ -> 25
      end

    Order
    |> where([o], o.customer_id == ^customer_id)
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(^limit)
    |> preload(:items)
    |> Repo.all()
  end

  def list_orders_for_customer(_, _), do: []

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
        where: o.payment_status == "paid" and o.settled_at >= ^today_start,
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
  UTC half-open time range for an Asia/Manila shop date.
  """
  def shop_day_bounds_utc(%Date{} = date) do
    day_start =
      date
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      |> DateTime.add(-@shop_utc_offset_seconds, :second)

    {day_start, DateTime.add(day_start, 1, :day)}
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
      |> where([o], o.payment_status == "paid" and o.settled_at >= ^period_start)

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
      where: o.payment_status == "paid" and o.settled_at >= ^today_start,
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
        if status in ["preparing", "ready"] and unpaid?(current) do
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
    case mark_paid_with_transition(%Order{id: id}, opts) do
      {:ok, _transition, order} -> {:ok, order}
      {:error, _reason} = error -> error
    end
  end

  def mark_paid(%Order{} = order, opts), do: mark_paid(%Order{id: order.id}, opts)

  @doc """
  Marks an order paid through the staff/manual path and reports whether this
  caller performed the atomic unpaid-to-paid transition.

  Existing callers should continue to use `mark_paid/2` unless they must own
  side effects that are authorized only for the transition winner.
  """
  def mark_paid_with_transition(order, opts \\ [])

  def mark_paid_with_transition(%Order{id: id}, opts) when is_integer(id) do
    paid_via = Keyword.get(opts, :paid_via, "counter")

    case Repo.get(Order, id) do
      nil ->
        {:error, :not_found}

      %Order{status: "cancelled"} ->
        {:error, :cancelled}

      %Order{payment_status: "paid"} = current ->
        # Best-effort loyalty retry for staff already-paid replays (same as
        # do_apply_paid count=0 / PayMongo duplicate path). Never affects paid status.
        _ = attempt_loyalty_earn(current)
        {:ok, :already_paid, current}

      %Order{payment_method: "online", payment_status: "awaiting_payment"} = current ->
        if BusinessSettings.qrph_manual?() do
          apply_paid(current, paid_via, :manual, opts)
        else
          {:error, :online_payment_required}
        end

      %Order{payment_method: "online"} ->
        {:error, :online_payment_required}

      %Order{} = current ->
        apply_paid(current, paid_via, :manual, opts)
    end
  end

  def mark_paid_with_transition(%Order{} = order, opts),
    do: mark_paid_with_transition(%Order{id: order.id}, opts)

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
        apply_paid(order, "paymongo", :paymongo, settlement_source: "paymongo")
        |> collapse_paid_transition()
    end
  end

  @doc """
  Marks an order paid from a PayMongo webhook using the checkout session id.

  Bypasses the staff/manual online restriction on `mark_paid/2`.
  """
  def mark_paid_from_paymongo_session(session_id) when is_binary(session_id) do
    case Repo.get_by(Order, paymongo_checkout_session_id: session_id) do
      nil ->
        {:error, :not_found}

      %Order{} = order ->
        apply_paid(order, "paymongo", :paymongo, settlement_source: "paymongo")
        |> collapse_paid_transition()
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
  Lists PayMongo payment reconciliation records for the Staff Orders drawer.

  Newest first (`inserted_at`, then `id`). Hard-capped at
  #{@paymongo_reconciliation_list_limit} rows — these are permanent exception/audit
  records with no open/closed workflow.
  """
  def list_open_paymongo_reconciliations do
    PaymentReconciliation
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(@paymongo_reconciliation_list_limit)
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
  def fulfillment_label("pickup"), do: "Takeout"
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
        payment_intent: wallet
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

  defp paid_via_attr(attrs) do
    result =
      case Map.fetch(attrs, :paid_via) do
        :error -> Map.fetch(attrs, "paid_via")
        result -> result
      end

    case result do
      :error -> "cash"
      {:ok, value} when is_atom(value) -> Atom.to_string(value)
      {:ok, value} -> value
    end
  end

  defp normalize_paid_via_value(value) when value in @paid_vias, do: {:ok, value}

  defp normalize_paid_via_value(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_paid_via_value()

  defp normalize_paid_via_value(_), do: {:error, :invalid_paid_via}

  defp validate_paid_at_create("paid", payment_method, payment_intent, paid_via) do
    case validate_payment_settlement(
           payment_method,
           payment_intent,
           paid_via,
           :paid_at_create
         ) do
      :ok -> {:ok, :valid}
      {:error, _reason} = error -> error
    end
  end

  defp validate_paid_at_create(_status, _payment_method, _payment_intent, _paid_via),
    do: {:ok, :not_paid}

  defp validate_payment_settlement(payment_method, payment_intent, paid_via, context) do
    with {:ok, paid_via} <- normalize_paid_via_value(paid_via) do
      cond do
        paid_via == "paymongo" and context != :paymongo ->
          {:error, :paymongo_authority_required}

        context == :paymongo and paid_via != "paymongo" ->
          {:error, :paymongo_authority_required}

        paid_via == "paymongo" and payment_method != "online" ->
          {:error, :payment_channel_mismatch}

        paid_via == "paymongo" and payment_intent in [nil, "gcash", "maya"] ->
          :ok

        paid_via == "counter" and payment_method == "counter" and
            is_nil(payment_intent) ->
          :ok

        paid_via == "counter" ->
          {:error, :payment_channel_mismatch}

        paid_via in ["cash", "gcash", "maya"] and is_nil(payment_intent) ->
          :ok

        paid_via in ["cash", "gcash", "maya"] and paid_via == payment_intent ->
          :ok

        paid_via in ["cash", "gcash", "maya"] ->
          {:error, {:payment_intent_mismatch, payment_intent, paid_via}}

        true ->
          {:error, :payment_channel_mismatch}
      end
    end
  end

  defp normalize_payment_intent(value) when value in ["cash", "gcash", "maya"], do: value

  defp normalize_payment_intent(value) when value in [:cash, :gcash, :maya],
    do: value |> Atom.to_string()

  defp normalize_payment_intent(_), do: nil

  defp build_settlement_attrs(status, _paid_via, _total, _attrs, _opts)
       when status != "paid",
       do: {:ok, %{}}

  defp build_settlement_attrs("paid", paid_via, total, attrs, opts) do
    default_source = Keyword.fetch!(opts, :default_source)

    with {:ok, source} <-
           normalize_settlement_source(
             settlement_value(attrs, :settlement_source),
             default_source
           ),
         {:ok, user_id} <-
           normalize_settled_by_user_id(settlement_value(attrs, :settled_by_user_id)),
         {:ok, cash_tendered, change_due} <-
           normalize_cash_settlement(
             paid_via,
             settlement_value(attrs, :cash_tendered),
             total
           ) do
      {:ok,
       %{
         settled_at: DateTime.utc_now() |> DateTime.truncate(:second),
         settled_by_user_id: user_id,
         settlement_source: source,
         cash_tendered: cash_tendered,
         change_due: change_due,
         settlement_time_estimated: false
       }}
    end
  end

  defp settlement_value(attrs, key) when is_list(attrs), do: Keyword.get(attrs, key)

  defp settlement_value(attrs, key) when is_map(attrs) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key))
    end
  end

  defp settlement_value(_, _), do: nil

  defp normalize_settlement_source(nil, default), do: normalize_settlement_source(default, nil)

  defp normalize_settlement_source(source, _default) when is_atom(source),
    do: source |> Atom.to_string() |> normalize_settlement_source(nil)

  defp normalize_settlement_source(source, _default)
       when source in ["pos", "staff_orders", "api", "paymongo", "manual", "legacy"],
       do: {:ok, source}

  defp normalize_settlement_source(_, _), do: {:error, :invalid_settlement_source}

  defp normalize_settled_by_user_id(nil), do: {:ok, nil}
  defp normalize_settled_by_user_id(id) when is_integer(id) and id > 0, do: {:ok, id}
  defp normalize_settled_by_user_id(_), do: {:error, :invalid_settled_by_user}

  defp normalize_cash_settlement(paid_via, nil, _total)
       when paid_via in ["cash", "counter"],
       do: {:ok, nil, nil}

  defp normalize_cash_settlement(paid_via, cash_tendered, total)
       when paid_via in ["cash", "counter"] do
    with {:ok, cash_tendered} <- normalize_money(cash_tendered),
         true <- Decimal.compare(cash_tendered, total) in [:eq, :gt] do
      {:ok, cash_tendered, Decimal.sub(cash_tendered, total) |> Decimal.round(2)}
    else
      false -> {:error, :cash_tender_too_low}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_cash_settlement(_paid_via, nil, _total), do: {:ok, nil, nil}

  defp normalize_cash_settlement(_paid_via, _cash_tendered, _total),
    do: {:error, :cash_metadata_not_applicable}

  defp normalize_money(%Decimal{} = value), do: {:ok, Decimal.round(value, 2)}
  defp normalize_money(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  defp normalize_money(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> {:ok, Decimal.round(decimal, 2)}
      _ -> {:error, :invalid_cash_tendered}
    end
  end

  defp normalize_money(_), do: {:error, :invalid_cash_tendered}

  defp default_settlement_source(:paymongo), do: "paymongo"
  defp default_settlement_source(_), do: "manual"

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

  # Loyalty is a side-effect of payment truth. Failures must not undo paid status.
  # Pending work is durable as: paid + customer_id + no earn ledger row.
  defp attempt_loyalty_earn(%Order{} = order) do
    case Loyalty.ensure_earn_for_paid_order(order) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.warning(
          "loyalty earn deferred order_id=#{order.id} customer_id=#{inspect(order.customer_id)} reason=#{inspect(reason)}"
        )

        if is_integer(order.customer_id) do
          Espreso.Loyalty.EarnReconciler.nudge(order.id)
        end

        {:error, reason}
    end
  end

  defp apply_paid(%Order{} = order, paid_via, settlement_context, opts) do
    with {:ok, paid_via} <- normalize_paid_via_value(paid_via),
         :ok <-
           validate_payment_settlement(
             order.payment_method,
             order.payment_intent,
             paid_via,
             settlement_context
           ),
         {:ok, settlement_attrs} <-
           build_settlement_attrs("paid", paid_via, order.total, opts,
             default_source: default_settlement_source(settlement_context)
           ) do
      do_apply_paid(order, paid_via, settlement_context, settlement_attrs)
    end
  end

  # Verified PayMongo path uses the same atomic writer as staff settlement.
  defp do_apply_paid(
         %Order{id: order_id} = order,
         paid_via,
         settlement_context,
         settlement_attrs
       ) do
    invoke_apply_paid_barrier!()

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    settled_at = Map.fetch!(settlement_attrs, :settled_at)
    settled_by_user_id = Map.get(settlement_attrs, :settled_by_user_id)
    settlement_source = Map.fetch!(settlement_attrs, :settlement_source)
    cash_tendered = Map.get(settlement_attrs, :cash_tendered)
    change_due = Map.get(settlement_attrs, :change_due)

    # Confirm payment advances New → Preparing so staff skip an extra tap.
    # Do not regress preparing / ready / completed.
    payment_query =
      from(o in Order,
        where:
          o.id == ^order_id and o.status != "cancelled" and o.payment_status != "paid" and
            o.payment_method == ^order.payment_method
      )

    payment_query =
      if is_nil(order.payment_intent) do
        where(payment_query, [o], is_nil(o.payment_intent))
      else
        where(payment_query, [o], o.payment_intent == ^order.payment_intent)
      end

    {count, _} =
      payment_query
      |> update([o],
        set: [
          payment_status: "paid",
          paid_via: ^paid_via,
          settled_at: ^settled_at,
          settled_by_user_id: ^settled_by_user_id,
          settlement_source: ^settlement_source,
          cash_tendered: ^cash_tendered,
          change_due: ^change_due,
          settlement_time_estimated: false,
          status: fragment("CASE WHEN status = 'received' THEN 'preparing' ELSE status END"),
          updated_at: ^now
        ]
      )
      |> Repo.update_all([])

    case count do
      1 ->
        order = Repo.get!(Order, order_id)
        _ = attempt_loyalty_earn(order)

        case broadcast({:ok, order}) do
          {:ok, broadcasted} -> {:ok, :transitioned, broadcasted}
        end

      0 ->
        case Repo.get(Order, order_id) do
          nil ->
            {:error, :not_found}

          %Order{payment_status: "paid"} = order ->
            # Safe retry path for loyalty that failed after a prior successful pay.
            _ = attempt_loyalty_earn(order)
            {:ok, :already_paid, order}

          %Order{status: "cancelled"} ->
            {:error, :cancelled}

          %Order{} = order ->
            case validate_payment_settlement(
                   order.payment_method,
                   order.payment_intent,
                   paid_via,
                   settlement_context
                 ) do
              :ok -> {:error, {:unexpected_apply_paid_state, order}}
              {:error, _reason} = error -> error
            end
        end

      _ ->
        {:error, :unexpected_update_count}
    end
  end

  defp collapse_paid_transition({:ok, _transition, order}), do: {:ok, order}
  defp collapse_paid_transition({:error, _reason} = error), do: error

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

defmodule Espreso.Loyalty do
  @moduledoc """
  Digital points loyalty: earn on paid orders, redeem free HOT/COLD coffee at POS.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Espreso.Customers.Customer
  alias Espreso.Loyalty.LedgerEntry
  alias Espreso.Menu
  alias Espreso.Menu.{Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo

  @point_threshold_centavos 20_000
  @redeem_points 10
  @reward_categories ~w(HOT COLD)

  @doc "Centavos required per 1 point."
  def point_threshold_centavos, do: @point_threshold_centavos

  @doc "Points deducted for one free coffee reward."
  def redeem_cost, do: @redeem_points

  @doc "Category names eligible for free coffee redemption."
  def reward_category_names, do: @reward_categories

  @doc """
  Converts a money `Decimal` (or integer/float/string) to integer centavos.
  """
  def to_centavos(%Decimal{} = amount) do
    amount
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  def to_centavos(amount) when is_integer(amount), do: amount * 100

  def to_centavos(amount) when is_binary(amount) or is_float(amount) do
    amount |> Decimal.new() |> to_centavos()
  end

  @doc """
  Awards points for a paid order when it has a customer.

  Idempotent: one earn ledger row per order. Safe to call on `:transitioned`,
  `:already_paid` retries, POS create-already-paid, and reconciler sweeps.
  No-ops when `customer_id` is nil.
  """
  def earn_for_paid_order(%Order{payment_status: "paid"} = order) do
    case invoke_earn_barrier() do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        do_earn_for_paid_order(order)
    end
  end

  def earn_for_paid_order(%Order{}), do: {:error, :not_paid}

  @doc """
  Idempotent ensure helper used by payment paths and the reconciler.
  """
  def ensure_earn_for_paid_order(%Order{} = order), do: earn_for_paid_order(order)

  @doc """
  True when a paid customer order still has no earn ledger row.
  """
  def earn_pending?(%Order{payment_status: "paid", customer_id: customer_id} = order)
      when is_integer(customer_id) do
    not earn_exists?(Repo, order.id)
  end

  def earn_pending?(%Order{}), do: false

  @doc """
  Paid orders with a customer and no earn ledger row yet (durable pending work).
  """
  def list_pending_earn_orders(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    earned_order_ids =
      from(e in LedgerEntry,
        where: e.kind == "earn" and not is_nil(e.order_id),
        select: e.order_id
      )

    from(o in Order,
      where: o.payment_status == "paid" and not is_nil(o.customer_id),
      where: o.id not in subquery(earned_order_ids),
      order_by: [asc: o.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp do_earn_for_paid_order(%Order{customer_id: nil}), do: {:ok, :no_customer}

  defp do_earn_for_paid_order(%Order{customer_id: customer_id} = order)
       when is_integer(customer_id) do
    Multi.new()
    |> Multi.run(:earn, fn repo, _ ->
      do_earn(repo, customer_id, order)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{earn: result}} -> {:ok, result}
      {:error, :earn, reason, _} -> {:error, reason}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp invoke_earn_barrier do
    case Application.get_env(:espreso, :loyalty_earn_barrier) do
      fun when is_function(fun, 0) ->
        case fun.() do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
          other -> {:error, {:unexpected_loyalty_barrier, other}}
        end

      _ ->
        :ok
    end
  end

  defp do_earn(repo, customer_id, %Order{} = order) do
    customer =
      Customer
      |> where([c], c.id == ^customer_id)
      |> lock("FOR UPDATE")
      |> repo.one()

    cond do
      is_nil(customer) ->
        {:error, :customer_not_found}

      earn_exists?(repo, order.id) ->
        {:ok, {:already_earned, customer}}

      true ->
        free = order.loyalty_free_amount_centavos || 0
        total = to_centavos(order.total)
        # order.total = amount charged/collected (free catalog value is NOT in total).
        # Approved formula uses gross final bill then subtracts free:
        #   final_paid_amount (gross) = collected + free
        #   qualifying = gross - free == collected
        final_paid_amount = total + free
        qualifying = max(final_paid_amount - free, 0)
        pool = customer.spend_remainder_centavos + qualifying
        points = div(pool, @point_threshold_centavos)
        remainder = rem(pool, @point_threshold_centavos)

        entry_attrs = %{
          customer_id: customer.id,
          order_id: order.id,
          points: points,
          qualifying_amount_centavos: qualifying,
          metadata: %{
            "order_total_centavos" => total,
            "loyalty_free_amount_centavos" => free,
            "previous_remainder_centavos" => customer.spend_remainder_centavos,
            "new_remainder_centavos" => remainder
          }
        }

        with {:ok, entry} <-
               %LedgerEntry{}
               |> LedgerEntry.earn_changeset(entry_attrs)
               |> repo.insert(),
             {:ok, updated} <-
               customer
               |> Customer.changeset(%{
                 points_balance: customer.points_balance + points,
                 spend_remainder_centavos: remainder
               })
               |> repo.update() do
          {:ok, %{customer: updated, entry: entry, points: points}}
        else
          {:error, %Ecto.Changeset{} = changeset} ->
            if earn_unique_conflict?(changeset) do
              {:ok, {:already_earned, repo.get!(Customer, customer.id)}}
            else
              {:error, changeset}
            end
        end
    end
  end

  defp earn_exists?(repo, order_id) do
    repo.exists?(from(e in LedgerEntry, where: e.order_id == ^order_id and e.kind == "earn"))
  end

  defp earn_unique_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:order_id, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  @doc """
  Lists available HOT/COLD products with prices for POS redemption.
  """
  def list_reward_menu do
    Menu.list_menu()
    |> Enum.filter(&(&1.name in @reward_categories))
  end

  @doc """
  Computes free base (cheapest size) and upgrade charge for a selected price id.
  """
  def quote_reward(price_id) when is_integer(price_id) do
    case reward_price_with_product(price_id) do
      {:ok, %{price: selected, product: product, category_name: category}} ->
        base = cheapest_price(product)
        selected_dec = selected.price
        upgrade = max_decimal(Decimal.sub(selected_dec, base), Decimal.new(0))

        {:ok,
         %{
           product: product,
           category_name: category,
           selected_price: selected,
           base_price: base,
           upgrade_amount: upgrade,
           loyalty_free_amount_centavos: to_centavos(base),
           amount_due: upgrade
         }}

      {:error, _} = error ->
        error
    end
  end

  def quote_reward(_), do: {:error, :invalid_price}

  defp reward_price_with_product(price_id) do
    case Repo.get(ProductPrice, price_id) do
      nil ->
        {:error, :ineligible_product}

      %ProductPrice{} = price ->
        product = Repo.preload(price, product: :category).product

        cond do
          is_nil(product) ->
            {:error, :ineligible_product}

          not product.available ->
            {:error, :ineligible_product}

          product.category.name not in @reward_categories ->
            {:error, :ineligible_product}

          true ->
            {:ok, %{price: price, product: product, category_name: product.category.name}}
        end
    end
  end

  defp cheapest_price(%Product{} = product) do
    product = Repo.preload(product, :product_prices)

    product.product_prices
    |> Enum.map(& &1.price)
    |> Enum.min(Decimal)
  end

  defp max_decimal(%Decimal{} = a, %Decimal{} = b) do
    if Decimal.compare(a, b) == :lt, do: b, else: a
  end

  @doc """
  Redeems one free HOT/COLD coffee at the counter.

  Creates a POS order for the reward (amount due = upgrade only), records a
  redeem ledger entry (−10), and stores `loyalty_free_amount_centavos` on the
  order. When the order is created already-paid, earning runs once for any
  upgrade amount paid.
  """
  def redeem_at_pos(customer_id, price_id, order_attrs)
      when is_integer(customer_id) and is_integer(price_id) and is_map(order_attrs) do
    Multi.new()
    |> Multi.run(:quote, fn _repo, _ -> quote_reward(price_id) end)
    |> Multi.run(:customer, fn repo, _ ->
      case Customer |> where([c], c.id == ^customer_id) |> lock("FOR UPDATE") |> repo.one() do
        nil ->
          {:error, :customer_not_found}

        %Customer{points_balance: balance} = customer when balance >= @redeem_points ->
          {:ok, customer}

        %Customer{} ->
          {:error, :insufficient_points}
      end
    end)
    |> Multi.run(:order, fn _repo, %{quote: quote, customer: customer} ->
      create_reward_order(quote, customer, order_attrs)
    end)
    |> Multi.run(:redeem_entry, fn repo, %{customer: customer, order: order, quote: quote} ->
      %LedgerEntry{}
      |> LedgerEntry.redeem_changeset(%{
        customer_id: customer.id,
        order_id: order.id,
        metadata: %{
          "product_id" => quote.product.id,
          "price_id" => quote.selected_price.id,
          "base_price" => Decimal.to_string(quote.base_price),
          "upgrade_amount" => Decimal.to_string(quote.upgrade_amount),
          "loyalty_free_amount_centavos" => quote.loyalty_free_amount_centavos
        }
      })
      |> repo.insert()
    end)
    |> Multi.run(:debit, fn repo, %{customer: customer} ->
      customer
      |> Customer.changeset(%{points_balance: customer.points_balance - @redeem_points})
      |> repo.update()
    end)
    |> Multi.run(:earn, fn _repo, %{order: order} ->
      order = Repo.get!(Order, order.id)

      if order.payment_status == "paid" do
        case earn_for_paid_order(order) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      else
        {:ok, :deferred}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order, debit: customer, quote: quote}} ->
        order = Repo.preload(order, :items)
        {:ok, %{order: order, customer: customer, quote: quote}}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp create_reward_order(quote, customer, order_attrs) do
    line = %{
      product_id: quote.product.id,
      price_id: quote.selected_price.id,
      name: quote.product.name,
      size: quote.selected_price.size,
      quantity: 1,
      # Amount charged = upgrade only (free base excluded from total/revenue).
      price: quote.upgrade_amount
    }

    call_name =
      Map.get(order_attrs, :customer_name) ||
        Map.get(order_attrs, "customer_name") ||
        customer.name ||
        "Loyalty"

    attrs =
      order_attrs
      |> Map.put(:customer_name, call_name)
      |> Map.put(:customer_id, customer.id)
      |> Map.put(:loyalty_free_amount_centavos, quote.loyalty_free_amount_centavos)
      |> Map.put(:source, Map.get(order_attrs, :source) || Map.get(order_attrs, "source") || :pos)
      |> Map.put(
        :payment_method,
        Map.get(order_attrs, :payment_method) || Map.get(order_attrs, "payment_method") ||
          :counter
      )
      |> Map.put(:skip_loyalty_earn, true)
      |> Map.put(:skip_authoritative_prices, true)

    case Orders.create_order([line], attrs) do
      {:ok, order} -> {:ok, order}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Append-only loyalty ledger activity for one customer.

  Newest first. Default limit is 50. Preloads the associated order for staff
  display (order number). Does not recalculate history from orders.
  """
  def list_activity_for_customer(customer_id, opts \\ [])

  def list_activity_for_customer(customer_id, opts)
      when is_integer(customer_id) and is_list(opts) do
    limit =
      case Keyword.get(opts, :limit, 50) do
        n when is_integer(n) and n > 0 -> min(n, 100)
        _ -> 50
      end

    LedgerEntry
    |> where([e], e.customer_id == ^customer_id)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^limit)
    |> preload(:order)
    |> Repo.all()
  end

  def list_activity_for_customer(_, _), do: []

  @doc false
  def eligible_reward?(name) when is_binary(name), do: name in @reward_categories
end

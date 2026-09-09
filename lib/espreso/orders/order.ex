defmodule Espreso.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Accounts.User
  alias Espreso.Orders.OrderItem

  @statuses ~w(received preparing ready completed cancelled)
  @payment_methods ~w(counter online)
  @payment_statuses ~w(unpaid awaiting_payment paid)
  @paid_vias ~w(cash gcash maya counter paymongo)
  @payment_intents ~w(cash gcash maya)
  @fulfillments ~w(dine_in pickup)
  @sources ~w(customer pos)
  @settlement_sources ~w(pos staff_orders api paymongo manual legacy)

  schema "orders" do
    field :number, :string
    field :customer_name, :string
    field :fulfillment, :string, default: "dine_in"
    field :table_number, :string
    field :notes, :string
    field :status, :string, default: "received"
    field :payment_method, :string, default: "counter"
    field :payment_status, :string, default: "unpaid"
    field :paid_via, :string
    field :payment_intent, :string
    field :source, :string, default: "customer"
    field :paymongo_checkout_session_id, :string
    field :total, :decimal
    field :settled_at, :utc_datetime
    field :settlement_source, :string
    field :cash_tendered, :decimal
    field :change_due, :decimal
    field :settlement_time_estimated, :boolean, default: false

    has_many :items, OrderItem
    belongs_to :settled_by_user, User

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def payment_methods, do: @payment_methods
  def payment_statuses, do: @payment_statuses
  def paid_vias, do: @paid_vias
  def payment_intents, do: @payment_intents
  def fulfillments, do: @fulfillments
  def sources, do: @sources
  def settlement_sources, do: @settlement_sources

  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :number,
      :customer_name,
      :fulfillment,
      :table_number,
      :notes,
      :status,
      :payment_method,
      :payment_status,
      :paid_via,
      :payment_intent,
      :source,
      :paymongo_checkout_session_id,
      :total,
      :settled_at,
      :settled_by_user_id,
      :settlement_source,
      :cash_tendered,
      :change_due,
      :settlement_time_estimated
    ])
    |> validate_required([
      :customer_name,
      :fulfillment,
      :status,
      :payment_method,
      :payment_status,
      :source,
      :total
    ])
    |> update_change(:customer_name, &String.trim/1)
    |> validate_length(:customer_name, min: 2, max: 60)
    |> validate_inclusion(:fulfillment, @fulfillments)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_inclusion(:payment_status, @payment_statuses)
    |> validate_paid_via()
    |> validate_payment_intent()
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:settlement_source, @settlement_sources)
    |> validate_fulfillment_table()
    |> validate_number(:total, greater_than_or_equal_to: 0)
    |> validate_number(:cash_tendered, greater_than_or_equal_to: 0)
    |> validate_number(:change_due, greater_than_or_equal_to: 0)
    |> unique_constraint(:number)
    |> foreign_key_constraint(:settled_by_user_id)
    |> check_constraint(:settled_at, name: :paid_orders_have_settlement_time)
    |> check_constraint(:settlement_source, name: :paid_orders_have_settlement_source)
    |> check_constraint(:cash_tendered, name: :cash_tendered_is_nonnegative)
    |> check_constraint(:change_due, name: :change_due_is_nonnegative)
  end

  def status_changeset(order, status) when status in @statuses do
    order
    |> change(%{status: status})
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Sets status to cancelled. Callers must enforce business rules in the context.
  """
  def cancel_changeset(order) do
    status_changeset(order, "cancelled")
  end

  @doc """
  Sets status to completed. Callers must enforce business rules in the context.
  """
  def complete_changeset(order) do
    status_changeset(order, "completed")
  end

  def payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:payment_status, :payment_method, :paymongo_checkout_session_id, :paid_via])
    |> validate_inclusion(:payment_status, @payment_statuses)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_paid_via()
    |> unique_constraint(:paymongo_checkout_session_id)
  end

  defp validate_paid_via(changeset) do
    case get_change(changeset, :paid_via) do
      nil -> changeset
      _value -> validate_inclusion(changeset, :paid_via, @paid_vias)
    end
  end

  defp validate_payment_intent(changeset) do
    case get_change(changeset, :payment_intent) do
      nil -> changeset
      _value -> validate_inclusion(changeset, :payment_intent, @payment_intents)
    end
  end

  defp validate_fulfillment_table(changeset) do
    case get_field(changeset, :fulfillment) do
      "dine_in" ->
        table = changeset |> get_field(:table_number) |> to_string() |> String.trim()

        cond do
          table == "" ->
            put_change(changeset, :table_number, nil)

          match?({n, ""} when n in 1..99, Integer.parse(table)) ->
            {n, ""} = Integer.parse(table)
            put_change(changeset, :table_number, Integer.to_string(n))

          true ->
            # Table UI is retired for now — ignore invalid leftovers.
            put_change(changeset, :table_number, nil)
        end

      "pickup" ->
        put_change(changeset, :table_number, nil)

      _ ->
        changeset
    end
  end
end

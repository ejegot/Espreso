defmodule Espreso.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Orders.OrderItem

  @statuses ~w(received preparing ready completed cancelled)
  @payment_methods ~w(counter online)
  @payment_statuses ~w(unpaid paid)
  @fulfillments ~w(dine_in pickup)
  @sources ~w(customer pos)

  schema "orders" do
    field :number, :string
    field :customer_name, :string
    field :fulfillment, :string, default: "dine_in"
    field :table_number, :string
    field :notes, :string
    field :status, :string, default: "received"
    field :payment_method, :string, default: "counter"
    field :payment_status, :string, default: "unpaid"
    field :source, :string, default: "customer"
    field :total, :decimal

    has_many :items, OrderItem

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def payment_methods, do: @payment_methods
  def payment_statuses, do: @payment_statuses
  def fulfillments, do: @fulfillments
  def sources, do: @sources

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
      :source,
      :total
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
    |> validate_inclusion(:source, @sources)
    |> validate_fulfillment_table()
    |> validate_number(:total, greater_than_or_equal_to: 0)
    |> unique_constraint(:number)
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
    |> cast(attrs, [:payment_status, :payment_method])
    |> validate_inclusion(:payment_status, @payment_statuses)
    |> validate_inclusion(:payment_method, @payment_methods)
  end

  defp validate_fulfillment_table(changeset) do
    case get_field(changeset, :fulfillment) do
      "dine_in" ->
        table = changeset |> get_field(:table_number) |> to_string() |> String.trim()

        case Integer.parse(table) do
          {n, ""} when n in 1..99 ->
            put_change(changeset, :table_number, Integer.to_string(n))

          _ ->
            add_error(changeset, :table_number, "must be between 1 and 99")
        end

      "pickup" ->
        put_change(changeset, :table_number, nil)

      _ ->
        changeset
    end
  end
end

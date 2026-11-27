defmodule Espreso.Shifts.ShopSessionAdjustment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Accounts.User
  alias Espreso.Orders.Order
  alias Espreso.Shifts.ShopDayOpen

  @kinds ~w(refund duplicate_void)
  @payment_methods ~w(cash gcash maya counter paymongo split)

  schema "shop_session_adjustments" do
    field :kind, :string
    field :reason, :string
    field :payment_method, :string
    field :payment_breakdown, :map, default: %{}
    field :sales_impact, :decimal
    field :drawer_impact, :decimal, default: Decimal.new("0")

    belongs_to :original_order, Order
    belongs_to :shop_session, ShopDayOpen
    belongs_to :recorded_by_user, User
    belongs_to :tenant, Espreso.Tenancy.Tenant
    belongs_to :branch, Espreso.Tenancy.Branch

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(adjustment, attrs) do
    adjustment
    |> cast(attrs, [
      :kind,
      :reason,
      :payment_method,
      :payment_breakdown,
      :sales_impact,
      :drawer_impact,
      :original_order_id,
      :shop_session_id,
      :recorded_by_user_id,
      :tenant_id,
      :branch_id
    ])
    |> validate_required([
      :kind,
      :reason,
      :payment_method,
      :payment_breakdown,
      :sales_impact,
      :drawer_impact,
      :original_order_id,
      :shop_session_id,
      :recorded_by_user_id
    ])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_length(:reason, min: 2, max: 500)
    |> validate_number(:sales_impact, less_than: 0)
    |> validate_number(:drawer_impact, less_than_or_equal_to: 0)
    |> unique_constraint(:original_order_id,
      name: :shop_session_adjustments_one_per_original_order
    )
    |> foreign_key_constraint(:original_order_id)
    |> foreign_key_constraint(:shop_session_id)
    |> foreign_key_constraint(:recorded_by_user_id)
    |> Espreso.Tenancy.put_ids()
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:branch_id)
    |> check_constraint(:sales_impact, name: :shop_session_adjustments_negative_sales_impact)
    |> check_constraint(:drawer_impact, name: :shop_session_adjustments_nonpositive_drawer_impact)
  end
end

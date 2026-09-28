defmodule Espreso.CustomerPush.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Orders.Order

  schema "order_push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string

    belongs_to :order, Order
    belongs_to :tenant, Espreso.Tenancy.Tenant
    belongs_to :branch, Espreso.Tenancy.Branch

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:order_id, :endpoint, :p256dh, :auth, :tenant_id, :branch_id])
    |> validate_required([:order_id, :endpoint, :p256dh, :auth])
    |> update_change(:endpoint, &String.trim/1)
    |> update_change(:p256dh, &String.trim/1)
    |> update_change(:auth, &String.trim/1)
    |> validate_length(:endpoint, min: 20, max: 2048)
    |> validate_length(:p256dh, min: 20, max: 200)
    |> validate_length(:auth, min: 8, max: 64)
    |> validate_format(:endpoint, ~r/^https:\/\//i)
    |> unique_constraint([:order_id, :endpoint])
    |> Espreso.Tenancy.put_ids()
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:branch_id)
  end
end

defmodule Espreso.Accounts.Authorization do
  @moduledoc """
  Role-based permissions for staff accounts.

  Roles in the database: `barista` (Staff), `manager`, `owner`.

  Authorization must be checked server-side on every protected
  route and action — UI hiding alone is not enough.
  """

  alias Espreso.Accounts.User

  @type permission ::
          :dashboard
          | :view_menu
          | :edit_menu
          | :product_availability
          | :orders
          | :reports
          | :user_management
          | :business_settings

  @permissions %{
    dashboard: ~w(barista manager owner),
    view_menu: ~w(barista manager owner),
    edit_menu: ~w(manager owner),
    product_availability: ~w(manager owner),
    orders: ~w(barista manager owner),
    reports: ~w(manager owner),
    user_management: ~w(owner),
    business_settings: ~w(owner)
  }

  @doc """
  Returns true when an active user may perform `permission`.
  """
  def can?(%User{active: true, role: role}, permission) when is_atom(permission) do
    role in Map.get(@permissions, permission, [])
  end

  def can?(_, _), do: false

  @doc """
  Returns `:ok` or `{:error, :unauthorized}`.
  """
  def authorize(%User{} = user, permission) when is_atom(permission) do
    if can?(user, permission), do: :ok, else: {:error, :unauthorized}
  end

  def authorize(_, _), do: {:error, :unauthorized}

  def permissions, do: Map.keys(@permissions)
end

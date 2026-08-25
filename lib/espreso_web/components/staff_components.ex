defmodule EspresoWeb.StaffComponents do
  @moduledoc """
  Shared staff chrome for the CoffeeSpot operations UI.
  """
  use Phoenix.Component

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User

  use EspresoWeb, :verified_routes

  attr :current, :atom, required: true, doc: "active nav key, e.g. :orders"
  attr :current_user, :map, required: true
  attr :page_title, :string, required: true

  slot :inner_block, required: true
  slot :tools

  def staff_shell(assigns) do
    assigns = assign(assigns, :nav_items, nav_items(assigns.current_user))

    ~H"""
    <div class="staff-app site-page">
      <header class="staff-shell" id="staff-shell">
        <div class="staff-shell-bar">
          <div class="staff-shell-brand-block">
            <p class="staff-shell-brand">CoffeeSpot</p>
            <div class="staff-shell-heading">
              <h1 class="staff-shell-title">{@page_title}</h1>
              <p class="staff-shell-user">
                {@current_user.name} · {User.role_label(@current_user.role)}
              </p>
            </div>
          </div>

          <div class="staff-shell-tools">
            {render_slot(@tools)}
            <.link href={~p"/logout"} method="delete" class="staff-shell-logout">
              Log out
            </.link>
          </div>
        </div>

        <nav class="staff-shell-nav" aria-label="Staff">
          <.link
            :for={item <- @nav_items}
            navigate={item.path}
            class={["staff-shell-nav-link", @current == item.key && "is-active"]}
            id={"staff-nav-#{item.key}"}
            aria-current={if(@current == item.key, do: "page", else: nil)}
          >
            {item.label}
          </.link>
        </nav>
      </header>

      <div class="staff-shell-body">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp nav_items(%User{} = user) do
    [
      %{key: :orders, label: "Orders", path: ~p"/orders", show?: Authorization.can?(user, :orders)},
      %{key: :pos, label: "POS", path: ~p"/pos", show?: Authorization.can?(user, :orders)},
      %{
        key: :dashboard,
        label: "Dashboard",
        path: ~p"/dashboard",
        show?: user.role in ["manager", "owner"]
      },
      %{
        key: :availability,
        label: "Availability",
        path: ~p"/admin/availability",
        show?: Authorization.can?(user, :product_availability)
      },
      %{
        key: :reports,
        label: "Reports",
        path: ~p"/dashboard#dashboard-panel-reports",
        show?: Authorization.can?(user, :reports)
      },
      %{
        key: :staff,
        label: "Staff",
        path: ~p"/admin/users",
        show?: Authorization.can?(user, :user_management)
      },
      %{
        key: :settings,
        label: "Settings",
        path: ~p"/admin/settings",
        show?: Authorization.can?(user, :business_settings)
      }
    ]
    |> Enum.filter(& &1.show?)
  end
end

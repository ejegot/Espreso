defmodule EspresoWeb.StaffComponents do
  @moduledoc """
  Shared staff chrome for the CoffeeSpot operations UI.
  """
  use Phoenix.Component

  import EspresoWeb.CoreComponents, only: [icon: 1]

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User

  use EspresoWeb, :verified_routes

  @primary_nav_keys [:home, :orders, :pos]

  attr :current, :atom, required: true, doc: "active nav key, e.g. :orders"
  attr :current_user, :map, required: true
  attr :page_title, :string, required: true
  attr :chrome, :atom, default: :top, values: [:top, :rail]

  slot :inner_block, required: true
  slot :tools

  def staff_shell(assigns) do
    items = nav_items(assigns.current_user)
    primary = Enum.filter(items, &(&1.key in @primary_nav_keys))
    more = Enum.reject(items, &(&1.key in @primary_nav_keys))

    assigns =
      assigns
      |> assign(:primary_nav, primary)
      |> assign(:more_nav, more)
      |> assign(:more_active?, assigns.current not in @primary_nav_keys)

    ~H"""
    <div class={["staff-app site-page", @chrome == :rail && "staff-app--rail"]}>
      <%= if @chrome == :rail do %>
        <aside class="staff-pos-rail staff-pos-rail--icons" id="staff-pos-rail" aria-label="Staff">
          <div class="staff-pos-rail-brand" title="CoffeeSpot">
            <span class="staff-pos-rail-mark" aria-hidden="true">C</span>
            <span class="sr-only">CoffeeSpot · {@page_title}</span>
          </div>

          <nav class="staff-pos-rail-nav">
            <.link
              :for={item <- @primary_nav}
              navigate={item.path}
              class={["staff-pos-rail-link", @current == item.key && "is-active"]}
              id={"staff-nav-#{item.key}"}
              aria-label={item.label}
              title={item.label}
              aria-current={if(@current == item.key, do: "page", else: nil)}
            >
              <.icon name={item.icon} class="staff-pos-rail-icon" />
              <span class="sr-only">{item.label}</span>
            </.link>
          </nav>

          <div class="staff-pos-rail-more">
            <.link
              :for={item <- @more_nav}
              navigate={item.path}
              class={[
                "staff-pos-rail-link staff-pos-rail-link--more",
                @current == item.key && "is-active"
              ]}
              id={"staff-nav-#{item.key}"}
              aria-label={item.label}
              title={item.label}
              aria-current={if(@current == item.key, do: "page", else: nil)}
            >
              <.icon name={item.icon} class="staff-pos-rail-icon" />
              <span class="sr-only">{item.label}</span>
            </.link>
            <.link
              href={~p"/logout"}
              method="delete"
              class="staff-pos-rail-link staff-pos-rail-link--more staff-pos-rail-logout"
              id="staff-nav-logout"
              aria-label="Log out"
              title="Log out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="staff-pos-rail-icon" />
              <span class="sr-only">Log out</span>
            </.link>
          </div>

          <div class="staff-pos-rail-footer">
            <div
              class="staff-pos-rail-avatar"
              title={"#{@current_user.name} · #{User.role_label(@current_user.role)}"}
              aria-label={"#{@current_user.name}, #{User.role_label(@current_user.role)}"}
            >
              {staff_initials(@current_user.name)}
            </div>
            <.live_component
              module={EspresoWeb.StaffNotificationsComponent}
              id="staff-notifications"
            />
          </div>
        </aside>

        <div class="staff-shell-body staff-shell-body--rail">
          <h1 class="sr-only staff-shell-title">{@page_title}</h1>
          {render_slot(@inner_block)}
        </div>
      <% else %>
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
              <.live_component
                module={EspresoWeb.StaffNotificationsComponent}
                id="staff-notifications"
              />
              {render_slot(@tools)}
            </div>
          </div>

          <nav class="staff-shell-nav" aria-label="Staff">
            <.link
              :for={item <- @primary_nav}
              navigate={item.path}
              class={["staff-shell-nav-link", @current == item.key && "is-active"]}
              id={"staff-nav-#{item.key}"}
              aria-current={if(@current == item.key, do: "page", else: nil)}
            >
              {item.label}
            </.link>

            <details
              class={["staff-shell-more", @more_active? && "is-active"]}
              id="staff-shell-more"
            >
              <summary class="staff-shell-more-summary" id="staff-nav-more">More</summary>
              <div class="staff-shell-more-panel" role="menu" aria-label="More staff tools">
                <.link
                  :for={item <- @more_nav}
                  navigate={item.path}
                  class={[
                    "staff-shell-more-link",
                    @current == item.key && "is-active"
                  ]}
                  id={"staff-nav-#{item.key}"}
                  role="menuitem"
                  aria-current={if(@current == item.key, do: "page", else: nil)}
                >
                  {item.label}
                </.link>
                <.link
                  href={~p"/logout"}
                  method="delete"
                  class="staff-shell-more-link staff-shell-logout"
                  id="staff-nav-logout"
                  role="menuitem"
                >
                  Log out
                </.link>
              </div>
            </details>
          </nav>
        </header>

        <div class="staff-shell-body">
          {render_slot(@inner_block)}
        </div>
      <% end %>
    </div>
    """
  end

  defp staff_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp staff_initials(_), do: "?"

  defp nav_items(%User{} = user) do
    [
      %{key: :home, label: "Home", icon: "hero-home", path: ~p"/staff", show?: true},
      %{
        key: :orders,
        label: "Orders",
        icon: "hero-clipboard-document-list",
        path: ~p"/orders",
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :pos,
        label: "POS",
        icon: "hero-shopping-bag",
        path: ~p"/pos",
        show?: Authorization.can?(user, :orders)
      },
      %{
        key: :dashboard,
        label: "Dashboard",
        icon: "hero-chart-bar",
        path: ~p"/dashboard",
        show?: user.role in ["manager", "owner"]
      },
      %{
        key: :availability,
        label: "Availability",
        icon: "hero-cube",
        path: ~p"/admin/availability",
        show?: Authorization.can?(user, :product_availability)
      },
      %{
        key: :reports,
        label: "Reports",
        icon: "hero-document-chart-bar",
        path: ~p"/dashboard#dashboard-panel-reports",
        show?: Authorization.can?(user, :reports)
      },
      %{
        key: :staff,
        label: "Staff",
        icon: "hero-users",
        path: ~p"/admin/users",
        show?: Authorization.can?(user, :user_management)
      },
      %{
        key: :settings,
        label: "Settings",
        icon: "hero-cog-6-tooth",
        path: ~p"/admin/settings",
        show?: Authorization.can?(user, :business_settings)
      }
    ]
    |> Enum.filter(& &1.show?)
  end
end

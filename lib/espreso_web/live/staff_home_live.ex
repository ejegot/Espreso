defmodule EspresoWeb.StaffHomeLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    overview = Orders.dashboard_overview()

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:shortcuts, shortcuts_for(user, overview))
     |> assign(:overview, overview), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:home} current_user={@current_user} page_title="Home">
      <main class="staff-home-main staff-home-hub">
        <p class="staff-home-lede">
          Good shift, {@current_user.name}. Choose where to go.
        </p>

        <div class="staff-home-grid staff-home-hub-grid" id="staff-home-shortcuts">
          <.link
            :for={item <- @shortcuts}
            navigate={item.path}
            class={["staff-home-card", "staff-home-hub-card", item[:class]]}
            id={"staff-home-#{item.id}"}
          >
            <span class="staff-home-card-eyebrow">{item.eyebrow}</span>
            <span class="staff-home-card-title">{item.title}</span>
            <span class="staff-home-card-body">{item.body}</span>
          </.link>
        </div>
      </main>
    </.staff_shell>
    """
  end

  defp shortcuts_for(%User{} = user, overview) do
    role = user.role

    base = [
      %{
        id: "orders",
        eyebrow: "Kitchen",
        title: "Orders",
        body: orders_body(overview),
        path: ~p"/orders",
        show?: true
      },
      %{
        id: "pos",
        eyebrow: "Counter",
        title: "POS",
        body: "Walk-in orders and pay-at-create.",
        path: ~p"/pos",
        show?: true
      }
    ]

    manager =
      if role in ["manager", "owner"] do
        [
          %{
            id: "dashboard",
            eyebrow: "Overview",
            title: "Dashboard",
            body: "Sales, reports, and today’s activity.",
            path: ~p"/dashboard",
            show?: true
          },
          %{
            id: "availability",
            eyebrow: "Menu",
            title: "Availability",
            body: "Mark items sold out or back in stock.",
            path: ~p"/admin/availability",
            show?: Authorization.can?(user, :product_availability)
          }
        ]
      else
        []
      end

    owner =
      if role == "owner" do
        [
          %{
            id: "staff",
            eyebrow: "Team",
            title: "Staff",
            body: "Accounts, roles, and PINs.",
            path: ~p"/admin/users",
            show?: true,
            class: "staff-home-card-owner"
          },
          %{
            id: "settings",
            eyebrow: "Shop",
            title: "Settings",
            body: "Payments mode, QR codes, and contact info.",
            path: ~p"/admin/settings",
            show?: true,
            class: "staff-home-card-owner"
          }
        ]
      else
        []
      end

    (base ++ manager ++ owner)
    |> Enum.filter(& &1.show?)
  end

  defp shortcuts_for(_, _), do: []

  defp orders_body(overview) do
    "#{overview.active_count} active · #{overview.unpaid_active_count} unpaid in kitchen"
  end
end

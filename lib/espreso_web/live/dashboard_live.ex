defmodule EspresoWeb.DashboardLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User
  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:order_overview, Orders.dashboard_overview()), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-home-page dashboard-page">
      <header class="staff-orders-top">
        <div>
          <p class="staff-orders-brand">CoffeeSpot</p>
          <h1 class="staff-orders-title">Dashboard</h1>
          <p class="staff-orders-user">
            {@current_user.name} · {User.role_label(@current_user.role)}
          </p>
        </div>
        <div class="staff-top-actions">
          <.link navigate={~p"/staff"} class="staff-refresh">Staff workspace</.link>
          <.link href={~p"/logout"} method="delete" class="staff-refresh">Log out</.link>
        </div>
      </header>

      <main class="staff-home-main">
        <p class="staff-home-lede">
          {dashboard_lede(@current_user.role)}
        </p>

        <div class="staff-home-grid" id="dashboard-panels">
          <%= for panel <- panels_for(@current_user.role, @order_overview) do %>
            <%= if panel[:to] do %>
              <.link navigate={panel.to} class="staff-home-card" id={"dashboard-panel-#{panel.id}"}>
                <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                <span class="staff-home-card-title">{panel.title}</span>
                <span class="staff-home-card-body">{panel.body}</span>
              </.link>
            <% else %>
              <div class="staff-home-card staff-home-card-soon" id={"dashboard-panel-#{panel.id}"}>
                <span class="staff-home-card-eyebrow">{panel.eyebrow}</span>
                <span class="staff-home-card-title">{panel.title}</span>
                <span class="staff-home-card-body">{panel.body}</span>
              </div>
            <% end %>
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  defp dashboard_lede("owner"), do: "Shop overview — sales, team, and settings."
  defp dashboard_lede("manager"), do: "Day-to-day operations — orders, availability, and reports."
  defp dashboard_lede(_), do: "Your shift overview — today’s orders."

  defp panels_for("owner", overview) do
    [
      %{
        id: "sales",
        eyebrow: "Overview",
        title: "Sales",
        body: "Sales overview will appear here.",
        to: nil
      },
      orders_panel(overview),
      %{
        id: "popular-products",
        eyebrow: "Menu",
        title: "Popular Products",
        body: "Popular products will appear here.",
        to: nil
      },
      %{
        id: "staff-activity",
        eyebrow: "Team",
        title: "Staff Activity",
        body: "Staff activity will appear here.",
        to: nil
      },
      %{
        id: "users",
        eyebrow: "Owner",
        title: "Users",
        body: "Manage staff accounts.",
        to: ~p"/admin/users"
      },
      %{
        id: "settings",
        eyebrow: "Owner",
        title: "Settings",
        body: "Business settings will appear here.",
        to: nil
      }
    ]
  end

  defp panels_for("manager", overview) do
    [
      %{
        id: "sales",
        eyebrow: "Overview",
        title: "Sales",
        body: "Sales overview will appear here.",
        to: nil
      },
      orders_panel(overview),
      %{
        id: "availability",
        eyebrow: "Menu",
        title: "Availability",
        body: "Product availability will appear here.",
        to: nil
      },
      %{
        id: "reports",
        eyebrow: "Insights",
        title: "Reports",
        body: "Reports will appear here.",
        to: nil
      }
    ]
  end

  defp panels_for(_staff, overview) do
    [
      %{
        id: "todays-orders",
        eyebrow: "Kitchen",
        title: "Today’s Orders",
        body: todays_orders_body(overview),
        to: ~p"/orders"
      }
    ]
  end

  defp orders_panel(overview) do
    %{
      id: "orders",
      eyebrow: "Kitchen",
      title: "Orders",
      body: orders_body(overview),
      to: ~p"/orders"
    }
  end

  defp orders_body(overview) do
    "#{overview.active_count} active · #{overview.received_count} received · #{overview.preparing_count} preparing · #{overview.unpaid_active_count} unpaid"
  end

  defp todays_orders_body(overview) do
    "#{overview.todays_count} today · #{overview.active_count} active"
  end
end

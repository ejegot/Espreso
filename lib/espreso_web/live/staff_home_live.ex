defmodule EspresoWeb.StaffHomeLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Staff")
     |> assign(:pos_ready?, false), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-home-page">
      <header class="staff-orders-top">
        <div>
          <p class="staff-orders-brand">CoffeeSpot Staff</p>
          <h1 class="staff-orders-title">Home</h1>
          <p class="staff-orders-user">
            {@current_user.name} · {User.role_label(@current_user.role)}
          </p>
        </div>
        <div class="staff-top-actions">
          <.link href={~p"/logout"} method="delete" class="staff-refresh">Log out</.link>
        </div>
      </header>

      <main class="staff-home-main">
        <p class="staff-home-lede">One tablet — pick Orders or POS.</p>

        <div class="staff-home-grid">
          <.link navigate={~p"/orders"} class="staff-home-card">
            <span class="staff-home-card-eyebrow">Kitchen</span>
            <span class="staff-home-card-title">Orders</span>
            <span class="staff-home-card-body">Active queue — preparing & ready</span>
          </.link>

          <%= if @pos_ready? do %>
            <.link navigate={~p"/pos"} class="staff-home-card">
              <span class="staff-home-card-eyebrow">Cashier</span>
              <span class="staff-home-card-title">POS</span>
              <span class="staff-home-card-body">Walk-in orders at the counter</span>
            </.link>
          <% else %>
            <.link navigate={~p"/pos"} class="staff-home-card staff-home-card-soon">
              <span class="staff-home-card-eyebrow">Cashier</span>
              <span class="staff-home-card-title">POS</span>
              <span class="staff-home-card-body">Coming next — counter sales</span>
              <span class="staff-home-soon-pill">Soon</span>
            </.link>
          <% end %>

          <.link
            :if={User.can?(@current_user, :user_management)}
            navigate={~p"/admin/users"}
            class="staff-home-card staff-home-card-owner"
          >
            <span class="staff-home-card-eyebrow">Owner</span>
            <span class="staff-home-card-title">Staff accounts</span>
            <span class="staff-home-card-body">Create staff & manager logins</span>
          </.link>
        </div>
      </main>
    </div>
    """
  end
end

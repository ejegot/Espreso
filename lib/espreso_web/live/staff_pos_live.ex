defmodule EspresoWeb.StaffPosLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "POS"), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-pos-page">
      <header class="staff-orders-top">
        <div>
          <p class="staff-orders-brand">CoffeeSpot Staff</p>
          <h1 class="staff-orders-title">POS</h1>
          <p class="staff-orders-user">
            {@current_user.name} · {User.role_label(@current_user.role)}
          </p>
        </div>
        <div class="staff-top-actions">
          <.link navigate={~p"/staff"} class="staff-refresh">Home</.link>
          <.link href={~p"/logout"} method="delete" class="staff-refresh">Log out</.link>
        </div>
      </header>

      <main class="staff-home-main">
        <section class="staff-auth-card staff-pos-placeholder">
          <p class="staff-home-card-eyebrow">Cashier</p>
          <h2 class="staff-orders-title">Coming soon</h2>
          <p class="staff-auth-lede">
            Counter POS (walk-in orders, cash, receipt printer, cash drawer) is next.
            For now use <strong>Orders</strong> for the kitchen queue.
          </p>
          <.link navigate={~p"/orders"} class="menu-basket-checkout">Go to Orders</.link>
        </section>
      </main>
    </div>
    """
  end
end

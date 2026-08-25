defmodule EspresoWeb.AdminAvailabilityLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User
  alias Espreso.Menu

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Availability")
     |> assign(:categories, Menu.list_products_for_availability())
     |> assign(:flash_note, nil), layout: false}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    product_id = String.to_integer(id)

    product =
      socket.assigns.categories
      |> Enum.flat_map(& &1.products)
      |> Enum.find(&(&1.id == product_id))

    case product do
      nil ->
        {:noreply, assign(socket, :flash_note, "Product not found.")}

      product ->
        case Menu.update_availability_as(actor, product.id, !product.available) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> assign(:categories, Menu.list_products_for_availability())
             |> assign(
               :flash_note,
               if(product.available,
                 do: "#{product.name} marked unavailable.",
                 else: "#{product.name} marked available."
               )
             )}

          {:error, :unauthorized} ->
            {:noreply,
             assign(socket, :flash_note, "You don’t have permission to change availability.")}

          {:error, _} ->
            {:noreply, assign(socket, :flash_note, "Could not update availability.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="menu-page-brune site-page staff-admin-page">
      <header class="staff-orders-top">
        <div>
          <p class="staff-orders-brand">CoffeeSpot</p>
          <h1 class="staff-orders-title">Availability</h1>
          <p class="staff-orders-user">
            {@current_user.name} · {User.role_label(@current_user.role)}
          </p>
        </div>
        <div class="staff-top-actions">
          <.link navigate={~p"/dashboard"} class="staff-refresh">Dashboard</.link>
          <.link navigate={~p"/staff"} class="staff-refresh">Home</.link>
          <.link href={~p"/logout"} method="delete" class="staff-refresh">Log out</.link>
        </div>
      </header>

      <main class="staff-orders-main staff-admin-main">
        <p :if={@flash_note} class="staff-admin-note" id="availability-flash">{@flash_note}</p>
        <p class="staff-auth-lede">
          Mark items unavailable when sold out (86). Unavailable items stay listed so you can restore them.
        </p>

        <section
          :for={category <- @categories}
          class="staff-orders-section"
          id={"availability-category-#{category.name}"}
        >
          <h2>{category.name}</h2>

          <article
            :for={product <- category.products}
            class="staff-order-card"
            id={"availability-product-#{product.id}"}
          >
            <header class="staff-order-head">
              <div>
                <p class="staff-order-number">{product.name}</p>
                <p class="staff-order-meta">
                  {if product.available, do: "Available", else: "Unavailable"}
                </p>
              </div>
              <div class="staff-order-badges">
                <span class={"staff-badge staff-badge--pay-#{if product.available, do: "paid", else: "unpaid"}"}>
                  {if product.available, do: "Available", else: "Unavailable"}
                </span>
              </div>
            </header>

            <div class="staff-order-actions">
              <button
                type="button"
                class="staff-action"
                phx-click="toggle"
                phx-value-id={product.id}
                id={"availability-toggle-#{product.id}"}
              >
                {if product.available, do: "Mark unavailable", else: "Mark available"}
              </button>
            </div>
          </article>
        </section>
      </main>
    </div>
    """
  end
end

defmodule EspresoWeb.AdminAvailabilityLive do
  use EspresoWeb, :live_view

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
    <.staff_shell
      current={:availability}
      current_user={@current_user}
      page_title="Availability"
      chrome={:bar}
    >
      <main class="staff-admin-main staff-availability" id="staff-availability">
        <p :if={@flash_note} class="staff-admin-note" id="availability-flash">{@flash_note}</p>
        <header class="staff-availability-head">
          <p class="staff-availability-eyebrow">Menu</p>
          <h2 class="staff-availability-title">Availability</h2>
          <p class="staff-availability-lede">
            Mark items unavailable when sold out (86). Unavailable items stay listed so you can restore them.
          </p>
        </header>

        <section
          :for={category <- @categories}
          class="staff-availability-category"
          id={"availability-category-#{category.name}"}
        >
          <h2>{category.name}</h2>

          <div class="staff-availability-grid">
            <article
              :for={product <- category.products}
              class={[
                "staff-availability-item",
                !product.available && "is-unavailable"
              ]}
              id={"availability-product-#{product.id}"}
            >
              <div class="staff-availability-copy">
                <p class="staff-availability-name">{product.name}</p>
                <p class="staff-availability-state">
                  {if product.available, do: "Available", else: "Unavailable"}
                </p>
              </div>
              <button
                type="button"
                class="staff-availability-toggle"
                phx-click="toggle"
                phx-value-id={product.id}
                id={"availability-toggle-#{product.id}"}
              >
                {if product.available, do: "Mark unavailable", else: "Mark available"}
              </button>
            </article>
          </div>
        </section>
      </main>
    </.staff_shell>
    """
  end
end

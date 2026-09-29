defmodule EspresoWeb.AdminTenantsLive do
  use EspresoWeb, :live_view

  alias Espreso.Tenancy
  alias Espreso.Tenancy.Tenants

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tenants")
     |> assign(:form, to_form(blank_form(), as: :tenant))
     |> assign(:flash_note, nil)
     |> refresh_tenants(), layout: false}
  end

  @impl true
  def handle_event("save", %{"tenant" => params}, socket) do
    actor = socket.assigns.current_user

    case Tenants.create_as(actor, params) do
      {:ok, %{tenant: tenant}} ->
        {:noreply,
         socket
         |> assign(:form, to_form(blank_form(), as: :tenant))
         |> assign(
           :flash_note,
           "#{tenant.name} is ready. Guest menu #{Tenants.guest_menu_path(tenant)}. Owner PIN login #{Tenants.guest_login_path(tenant)}."
         )
         |> refresh_tenants()}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "Only CoffeeSpot can add a tenant.")}

      {:error, :invalid_name} ->
        {:noreply, assign(socket, :flash_note, "Enter a café name (at least 2 characters).")}

      {:error, :invalid_owner_name} ->
        {:noreply, assign(socket, :flash_note, "Enter the owner’s name (at least 2 characters).")}

      {:error, :pin_mismatch} ->
        {:noreply, assign(socket, :flash_note, "PIN and confirmation must match.")}

      {:error, :invalid_pin_format} ->
        {:noreply, assign(socket, :flash_note, "PIN must be 4–6 digits.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, assign(socket, :flash_note, "Could not add that café. Try a different name.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:tenants} current_user={@current_user} page_title="Tenants" chrome={:bar}>
      <main class="staff-admin-main staff-settings" id="staff-tenants">
        <p :if={@flash_note} class="staff-admin-note" id="tenants-flash">{@flash_note}</p>
        <header class="staff-settings-head">
          <p class="staff-settings-eyebrow">Elilai</p>
          <h2 class="staff-settings-title">Tenants</h2>
          <p class="staff-settings-lede">
            A new café gets its own owner PIN, menu, and guest URL. Their guests never land on Lilac
            /menu. Extra CoffeeSpot shops stay under Branches.
          </p>
        </header>

        <section class="staff-settings-card" id="tenant-list">
          <h2 class="staff-settings-card-title">Cafés</h2>
          <ul class="staff-branch-list">
            <li :for={tenant <- @tenants} class="staff-branch-row" id={"tenant-row-#{tenant.id}"}>
              <div>
                <p class="staff-branch-name">
                  {tenant.name}
                  <span :if={tenant.slug == Tenancy.coffeespot_slug()} class="staff-branch-pill">
                    CoffeeSpot
                  </span>
                </p>
                <p class="staff-branch-meta">Guest menu {Tenants.guest_menu_path(tenant)}</p>
                <p :if={tenant.slug != Tenancy.coffeespot_slug()} class="staff-branch-meta">
                  Owner login {Tenants.guest_login_path(tenant)}
                </p>
              </div>
            </li>
          </ul>
        </section>

        <.form for={@form} id="admin-tenant-form" phx-submit="save" class="staff-settings-form">
          <section class="staff-settings-card" aria-labelledby="tenant-add-title">
            <h2 class="staff-settings-card-title" id="tenant-add-title">Add a café</h2>
            <p class="staff-settings-card-note">
              You open the door. They run their shop. No billing in this step.
            </p>
            <.input
              field={@form[:name]}
              type="text"
              label="Café name"
              required
              placeholder="e.g. Kape ni Juan"
            />
            <.input
              field={@form[:owner_name]}
              type="text"
              label="Owner name"
              required
              placeholder="Their name on the PIN login"
            />
            <.input field={@form[:address]} type="text" label="Address" placeholder="Street, city" />
            <.input
              field={@form[:pin]}
              type="password"
              label="Owner PIN"
              required
              placeholder="4–6 digits"
            />
            <.input
              field={@form[:pin_confirmation]}
              type="password"
              label="Confirm PIN"
              required
              placeholder="Same PIN"
            />
            <div class="staff-settings-save">
              <button type="submit" class="staff-settings-save-btn">Add tenant</button>
            </div>
          </section>
        </.form>
      </main>
    </.staff_shell>
    """
  end

  defp refresh_tenants(socket) do
    assign(socket, :tenants, Tenancy.list_tenants())
  end

  defp blank_form do
    %{"name" => "", "owner_name" => "", "address" => "", "pin" => "", "pin_confirmation" => ""}
  end
end

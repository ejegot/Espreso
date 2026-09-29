defmodule EspresoWeb.AdminBranchesLive do
  use EspresoWeb, :live_view

  alias Espreso.Tenancy
  alias Espreso.Tenancy.Branches

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Branches")
     |> assign(:form, to_form(blank_form(), as: :branch))
     |> assign(:flash_note, nil)
     |> refresh_branches(), layout: false}
  end

  @impl true
  def handle_event("save", %{"branch" => params}, socket) do
    actor = socket.assigns.current_user

    case Branches.create_as(actor, params) do
      {:ok, branch} ->
        {:noreply,
         socket
         |> assign(:form, to_form(blank_form(), as: :branch))
         |> assign(
           :flash_note,
           "#{branch.name} is ready. Switch to it, then add the menu and staff. Guest QR: #{Branches.guest_menu_path(branch)}"
         )
         |> refresh_branches()}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to add a branch.")}

      {:error, :invalid_name} ->
        {:noreply, assign(socket, :flash_note, "Enter a branch name (at least 2 characters).")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: :branch))
         |> assign(:flash_note, "Could not add that branch. Try a different name.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:branches} current_user={@current_user} page_title="Branches" chrome={:bar}>
      <main class="staff-admin-main staff-settings" id="staff-branches">
        <p :if={@flash_note} class="staff-admin-note" id="branches-flash">{@flash_note}</p>
        <header class="staff-settings-head">
          <p class="staff-settings-eyebrow">CoffeeSpot</p>
          <h2 class="staff-settings-title">Branches</h2>
          <p class="staff-settings-lede">
            Each branch has its own menu, staff PINs, drawer, and guest QR. Printer stays on that shop’s LAN — use Test print on Home after you switch.
          </p>
        </header>

        <section class="staff-settings-card" id="branch-list">
          <h2 class="staff-settings-card-title">Shops</h2>
          <ul class="staff-branch-list">
            <li :for={branch <- @branches} class="staff-branch-row" id={"branch-row-#{branch.id}"}>
              <div>
                <p class="staff-branch-name">
                  {branch.name}
                  <span :if={branch.main} class="staff-branch-pill">Main</span>
                  <span :if={branch.id == @current_branch_id} class="staff-branch-pill">
                    This session
                  </span>
                </p>
                <p :if={branch.address} class="staff-branch-meta">{branch.address}</p>
                <p class="staff-branch-meta">Guest menu {Branches.guest_menu_path(branch)}</p>
              </div>
            </li>
          </ul>
        </section>

        <.form for={@form} id="admin-branch-form" phx-submit="save" class="staff-settings-form">
          <section class="staff-settings-card" aria-labelledby="branch-add-title">
            <h2 class="staff-settings-card-title" id="branch-add-title">Add a CoffeeSpot branch</h2>
            <p class="staff-settings-card-note">
              They create categories and items. You open the door. No travel required.
            </p>
            <.input
              field={@form[:name]}
              type="text"
              label="Branch name"
              required
              placeholder="e.g. Ortigas"
            />
            <.input field={@form[:address]} type="text" label="Address" placeholder="Street, city" />
            <div class="staff-settings-save">
              <button type="submit" class="staff-settings-save-btn">Add branch</button>
            </div>
          </section>
        </.form>
      </main>
    </.staff_shell>
    """
  end

  defp refresh_branches(socket) do
    tenant_id = socket.assigns.current_tenant_id
    assign(socket, :branches, Tenancy.list_branches(tenant_id))
  end

  defp blank_form do
    %{"name" => "", "address" => ""}
  end
end

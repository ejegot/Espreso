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
     |> assign(:adding?, false)
     |> assign(:flash_note, nil)
     |> refresh_branches(), layout: false}
  end

  @impl true
  def handle_event("toggle_add", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding?, !socket.assigns.adding?)
     |> assign(:form, to_form(blank_form(), as: :branch))
     |> assign(:flash_note, nil)}
  end

  def handle_event("save", %{"branch" => params}, socket) do
    actor = socket.assigns.current_user

    case Branches.create_as(actor, params) do
      {:ok, branch} ->
        {:noreply,
         socket
         |> assign(:form, to_form(blank_form(), as: :branch))
         |> assign(:adding?, false)
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
         |> assign(:adding?, true)
         |> assign(:form, to_form(changeset, as: :branch))
         |> assign(:flash_note, "Could not add that branch. Try a different name.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:branches} current_user={@current_user} page_title="Branches" chrome={:bar}>
      <main class="staff-admin-main staff-settings" id="staff-branches">
        <header class="staff-places-head">
          <p class="staff-places-scope" id="staff-branches-scope">
            Each branch has its own menu, staff PINs, drawer, and guest QR. Printer stays on that shop’s LAN — use Test print on Home after you switch.
          </p>
          <button type="button" class="staff-places-add" id="branch-add-toggle" phx-click="toggle_add">
            {if(@adding?, do: "Close", else: "Add branch")}
          </button>
        </header>

        <p :if={@flash_note && !@adding?} class="staff-places-note" id="branches-flash">
          {@flash_note}
        </p>

        <section id="branch-list" aria-label="Shops">
          <div class="staff-places-section-head">
            <h2 class="staff-places-section-title">Shops</h2>
          </div>
          <article :for={branch <- @branches} class="staff-places-card" id={"branch-row-#{branch.id}"}>
            <p class="staff-places-name">
              {branch.name}
              <span :if={branch.main} class="staff-branch-pill">Main</span>
              <span :if={branch.id == @current_branch_id} class="staff-branch-pill">
                This session
              </span>
            </p>
            <p :if={branch.address} class="staff-places-meta">{branch.address}</p>
            <p class="staff-places-meta">Guest menu {Branches.guest_menu_path(branch)}</p>
          </article>
        </section>

        <.modal
          :if={@adding?}
          id="staff-branch-add-modal"
          show
          click_away={false}
          autofocus={false}
          on_cancel={JS.push("toggle_add")}
        >
          <section class="staff-places-dialog" id="branch-add" aria-label="Add branch">
            <h3 class="staff-confirm-dialog-title" id="branch-add-title">Add branch</h3>
            <p class="staff-confirm-dialog-copy">
              They create categories and items. You open the door. No travel required.
            </p>
            <p :if={@flash_note} class="staff-places-note" id="branches-flash">{@flash_note}</p>
            <.form for={@form} id="admin-branch-form" phx-submit="save" class="staff-team-form">
              <.input
                field={@form[:name]}
                type="text"
                label="Branch name"
                required
                placeholder="e.g. Ortigas"
              />
              <.input field={@form[:address]} type="text" label="Address" placeholder="Street, city" />
              <div class="staff-confirm-dialog-actions">
                <button type="submit" class="staff-team-btn staff-team-btn--primary">
                  Add branch
                </button>
                <button type="button" class="staff-team-btn" phx-click="toggle_add">
                  Cancel
                </button>
              </div>
            </.form>
          </section>
        </.modal>
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

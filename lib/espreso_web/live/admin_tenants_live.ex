defmodule EspresoWeb.AdminTenantsLive do
  use EspresoWeb, :live_view

  alias Espreso.Marketing
  alias Espreso.Tenancy
  alias Espreso.Tenancy.Tenants

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tenants")
     |> assign(:form, to_form(blank_form(), as: :tenant))
     |> assign(:adding?, false)
     |> assign(:flash_note, nil)
     |> refresh(), layout: false}
  end

  @impl true
  def handle_event("toggle_add", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding?, !socket.assigns.adding?)
     |> assign(:form, to_form(blank_form(), as: :tenant))
     |> assign(:flash_note, nil)}
  end

  def handle_event("fill_waitlist", %{"id" => id}, socket) do
    case Marketing.get_shop_request(id) do
      %{status: "pending"} = request ->
        {:noreply,
         socket
         |> assign(:adding?, true)
         |> assign(:form, to_form(form_from_request(request), as: :tenant))
         |> assign(
           :flash_note,
           "Waitlist: #{request.cafe_name}. Set their owner PIN, then add tenant."
         )}

      _ ->
        {:noreply, assign(socket, :flash_note, "That waitlist request is no longer pending.")}
    end
  end

  def handle_event("dismiss_waitlist", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    case Marketing.get_shop_request(id) do
      nil ->
        {:noreply, assign(socket, :flash_note, "That waitlist request is gone.")}

      request ->
        case Marketing.dismiss_as(actor, request) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:flash_note, "#{request.cafe_name} was dismissed from the waitlist.")
             |> refresh()}

          {:error, :unauthorized} ->
            {:noreply, assign(socket, :flash_note, "Only CoffeeSpot can manage the waitlist.")}

          {:error, :not_pending} ->
            {:noreply, assign(socket, :flash_note, "That waitlist request is no longer pending.")}
        end
    end
  end

  def handle_event("save", %{"tenant" => params}, socket) do
    actor = socket.assigns.current_user

    case Tenants.create_as(actor, params) do
      {:ok, %{tenant: tenant}} ->
        {:noreply,
         socket
         |> assign(:form, to_form(blank_form(), as: :tenant))
         |> assign(:adding?, false)
         |> assign(
           :flash_note,
           "#{tenant.name} is ready. Guest menu #{Tenants.guest_menu_path(tenant)}. Owner PIN login #{Tenants.guest_login_path(tenant)}."
         )
         |> refresh()}

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

      {:error, :request_not_pending} ->
        {:noreply, assign(socket, :flash_note, "That waitlist request is no longer pending.")}

      {:error, :request_not_found} ->
        {:noreply, assign(socket, :flash_note, "That waitlist request is gone.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, assign(socket, :flash_note, "Could not add that café. Try a different name.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:tenants} current_user={@current_user} page_title="Tenants" chrome={:bar}>
      <main class="staff-admin-main staff-settings" id="staff-tenants">
        <header class="staff-places-head">
          <p class="staff-places-scope" id="staff-tenants-scope">
            Waitlist from /product lands here. You open the door with an owner PIN. Their guests never
            land on Lilac /menu. Extra CoffeeSpot shops stay under Branches.
          </p>
          <button type="button" class="staff-places-add" id="tenant-add-toggle" phx-click="toggle_add">
            {if(@adding?, do: "Close", else: "Add café")}
          </button>
        </header>

        <p :if={@flash_note && !@adding?} class="staff-places-note" id="tenants-flash">
          {@flash_note}
        </p>

        <section id="waitlist" aria-label="Waitlist">
          <div class="staff-places-section-head">
            <h2 class="staff-places-section-title">Waitlist</h2>
          </div>
          <p :if={@waitlist == []} class="staff-places-empty" id="waitlist-empty">
            No pending café requests.
          </p>
          <article
            :for={request <- @waitlist}
            class="staff-places-card"
            id={"waitlist-row-#{request.id}"}
          >
            <p class="staff-places-name">{request.cafe_name}</p>
            <p class="staff-places-meta">
              {request.contact_name} · {request.city} · {request.email} · {request.phone_e164}
            </p>
            <p :if={request.note} class="staff-places-meta">{request.note}</p>
            <div class="staff-places-actions">
              <button
                type="button"
                class="staff-places-btn staff-places-btn--primary"
                phx-click="fill_waitlist"
                phx-value-id={request.id}
                id={"waitlist-open-#{request.id}"}
              >
                Open café
              </button>
              <button
                type="button"
                class="staff-places-btn"
                phx-click="dismiss_waitlist"
                phx-value-id={request.id}
                id={"waitlist-dismiss-#{request.id}"}
              >
                Dismiss
              </button>
            </div>
          </article>
        </section>

        <section id="tenant-list" aria-label="Cafés">
          <div class="staff-places-section-head">
            <h2 class="staff-places-section-title">Cafés</h2>
          </div>
          <article :for={tenant <- @tenants} class="staff-places-card" id={"tenant-row-#{tenant.id}"}>
            <p class="staff-places-name">
              {tenant.name}
              <span :if={tenant.slug == Tenancy.coffeespot_slug()} class="staff-branch-pill">
                CoffeeSpot
              </span>
            </p>
            <p class="staff-places-meta">Guest menu {Tenants.guest_menu_path(tenant)}</p>
            <p :if={tenant.slug != Tenancy.coffeespot_slug()} class="staff-places-meta">
              Owner login {Tenants.guest_login_path(tenant)}
            </p>
          </article>
        </section>

        <.modal
          :if={@adding?}
          id="staff-tenant-add-modal"
          show
          click_away={false}
          autofocus={false}
          on_cancel={JS.push("toggle_add")}
        >
          <section class="staff-places-dialog" id="tenant-add" aria-label="Add café">
            <h3 class="staff-confirm-dialog-title" id="tenant-add-title">Add café</h3>
            <p class="staff-confirm-dialog-copy">
              You open the door. They run their shop. No billing in this step.
            </p>
            <p :if={@flash_note} class="staff-places-note" id="tenants-flash">{@flash_note}</p>
            <.form for={@form} id="admin-tenant-form" phx-submit="save" class="staff-team-form">
              <input
                type="hidden"
                name="tenant[shop_request_id]"
                value={@form[:shop_request_id].value || ""}
              />
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
              <div class="staff-confirm-dialog-actions">
                <button type="submit" class="staff-team-btn staff-team-btn--primary">
                  Add tenant
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

  defp refresh(socket) do
    socket
    |> assign(:tenants, Tenancy.list_tenants())
    |> assign(:waitlist, Marketing.list_pending_shop_requests())
  end

  defp blank_form do
    %{
      "name" => "",
      "owner_name" => "",
      "address" => "",
      "pin" => "",
      "pin_confirmation" => "",
      "shop_request_id" => ""
    }
  end

  defp form_from_request(request) do
    %{
      "name" => request.cafe_name,
      "owner_name" => request.contact_name,
      "address" => request.city,
      "pin" => "",
      "pin_confirmation" => "",
      "shop_request_id" => to_string(request.id)
    }
  end
end

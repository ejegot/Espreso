defmodule EspresoWeb.AdminSettingsLive do
  use EspresoWeb, :live_view

  alias Espreso.BusinessSettings

  @impl true
  def mount(_params, _session, socket) do
    settings = BusinessSettings.get()

    {:ok,
     socket
     |> assign(:page_title, "Business settings")
     |> assign(:settings, settings)
     |> assign(:form, to_form(BusinessSettings.change(settings), as: :settings))
     |> assign(:flash_note, nil), layout: false}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    actor = socket.assigns.current_user

    case BusinessSettings.update_as(actor, params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(:settings, settings)
         |> assign(:form, to_form(BusinessSettings.change(settings), as: :settings))
         |> assign(:flash_note, "Business settings saved.")}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to edit settings.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :settings))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:settings} current_user={@current_user} page_title="Settings">
      <main class="staff-orders-main staff-admin-main">
        <p :if={@flash_note} class="staff-admin-note" id="settings-flash">{@flash_note}</p>
        <p class="staff-auth-lede">
          Signed in as {@current_user.name} (Owner). Update public contact, hours, and social links.
        </p>

        <section class="staff-auth-card staff-admin-form-card">
          <h2 class="staff-admin-heading">Shop details</h2>
          <.form for={@form} id="admin-settings-form" phx-submit="save" class="staff-auth-form">
            <.input field={@form[:business_name]} type="text" label="Business name" required />
            <.input field={@form[:address]} type="text" label="Address" required />
            <.input field={@form[:phone]} type="text" label="Phone" required />
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input
              field={@form[:hours_text]}
              type="textarea"
              label="Hours (one line per entry)"
              required
            />
            <.input field={@form[:instagram_url]} type="url" label="Instagram URL" required />
            <.input field={@form[:facebook_url]} type="url" label="Facebook URL" required />
            <.input field={@form[:tiktok_url]} type="url" label="TikTok URL" required />
            <button type="submit" class="menu-basket-checkout">Save settings</button>
          </.form>
        </section>
      </main>
    </.staff_shell>
    """
  end
end

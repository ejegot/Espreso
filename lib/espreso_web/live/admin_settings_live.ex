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
    <.staff_shell current={:settings} current_user={@current_user} page_title="Settings" chrome={:bar}>
      <main class="staff-admin-main staff-settings" id="staff-settings">
        <p :if={@flash_note} class="staff-admin-note" id="settings-flash">{@flash_note}</p>
        <header class="staff-settings-head">
          <p class="staff-settings-eyebrow">Shop</p>
          <h2 class="staff-settings-title">Settings</h2>
          <p class="staff-settings-lede">
            Signed in as {@current_user.name} (Owner). Update public contact, hours, and social links.
          </p>
        </header>

        <.form for={@form} id="admin-settings-form" phx-submit="save" class="staff-settings-form">
          <section
            class="staff-settings-card"
            id="settings-shop"
            aria-labelledby="settings-shop-title"
          >
            <h2 class="staff-settings-card-title" id="settings-shop-title">Shop</h2>
            <.input field={@form[:business_name]} type="text" label="Business name" required />
            <.input field={@form[:address]} type="text" label="Address" required />
            <.input field={@form[:phone]} type="text" label="Phone" required />
            <.input field={@form[:email]} type="email" label="Email" required />
          </section>

          <section
            class="staff-settings-card"
            id="settings-hours"
            aria-labelledby="settings-hours-title"
          >
            <h2 class="staff-settings-card-title" id="settings-hours-title">Hours</h2>
            <.input
              field={@form[:hours_text]}
              type="textarea"
              label="Hours (one line per entry)"
              required
            />
          </section>

          <section
            class="staff-settings-card"
            id="settings-social"
            aria-labelledby="settings-social-title"
          >
            <h2 class="staff-settings-card-title" id="settings-social-title">Social</h2>
            <.input field={@form[:instagram_url]} type="url" label="Instagram URL" required />
            <.input field={@form[:facebook_url]} type="url" label="Facebook URL" required />
            <.input field={@form[:tiktok_url]} type="url" label="TikTok URL" required />
          </section>

          <section
            class="staff-settings-card"
            id="settings-payments"
            aria-labelledby="settings-payments-title"
          >
            <h2 class="staff-settings-card-title" id="settings-payments-title">Payments</h2>
            <p class="staff-settings-card-note">
              Counter-only hides online pay on the menu. QRPh manual shows GCash/Maya QR codes — upload images to
              <code>priv/static</code>
              and enter their public paths below.
            </p>
            <.input
              field={@form[:payments_mode]}
              type="select"
              label="Payments mode"
              options={payments_mode_options()}
            />
            <.input
              field={@form[:gcash_qrph_path]}
              type="text"
              label="GCash QRPh image path"
              placeholder="/images/gcash-qrph.png"
            />
            <.input
              field={@form[:maya_qrph_path]}
              type="text"
              label="Maya QRPh image path"
              placeholder="/images/maya-qrph.png"
            />
          </section>

          <div class="staff-settings-save">
            <button type="submit" class="menu-basket-checkout">Save settings</button>
          </div>
        </.form>
      </main>
    </.staff_shell>
    """
  end

  defp payments_mode_options do
    [
      {"Counter only (pay at counter)", "counter_only"},
      {"QRPh manual (GCash / Maya QR)", "qrph_manual"},
      {"PayMongo online checkout", "paymongo"}
    ]
  end
end

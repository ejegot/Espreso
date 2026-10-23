defmodule EspresoWeb.AdminSettingsLive do
  use EspresoWeb, :live_view

  alias Espreso.BusinessSettings

  @impl true
  def mount(_params, _session, socket) do
    settings = BusinessSettings.get()
    gcash_qr = BusinessSettings.get_gcash_qr()

    upload_socket =
      allow_upload(
        socket,
        :gcash_qr,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 2_000_000
      )

    {:ok,
     upload_socket
     |> assign(:gcash_qr, gcash_qr)
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
  def handle_event("upload_gcash_qr", _params, socket) do
    actor = socket.assigns.current_user

    results =
      consume_uploaded_entries(socket, :gcash_qr, fn %{path: path}, entry ->
        with {:ok, binary} <- File.read(path),
             {:ok, qr} <-
               BusinessSettings.save_gcash_qr_as(actor, binary, entry.client_type) do
          {:ok, {:ok, qr}}
        else
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case results do
      [{:ok, %Espreso.BusinessSettings.GcashQr{} = qr}] ->
        {:noreply,
         socket
         |> assign(:gcash_qr, qr)
         |> assign(:flash_note, "GCash QR uploaded successfully.")}

      _ ->
        {:noreply,
         assign(socket, :flash_note, "GCash QR upload failed. Check the image and try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:settings} current_user={@current_user} page_title="Settings" chrome={:bar}>
      <main class="staff-admin-main staff-settings" id="staff-settings">
        <p :if={@flash_note} class="staff-admin-note" id="settings-flash">{@flash_note}</p>
        <header class="staff-settings-head">
          <p class="staff-settings-scope" id="staff-settings-scope">
            Update the public contact, hours, and how guests pay.
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
              Counter-only hides online pay on the menu. QRPh manual enables GCash/Maya QR payments. Upload the GCash QR image here; the Maya QR image path remains configurable below.
            </p>
            <.input
              field={@form[:payments_mode]}
              type="select"
              label="Payments mode"
              options={payments_mode_options()}
            />
            <div id="gcash-qr-upload">
              <label for="gcash-qr-file">GCash QR image</label>
              <img
                :if={@gcash_qr}
                src={"/media/business/gcash-qr?v=#{DateTime.to_unix(@gcash_qr.updated_at)}"}
                alt="Current GCash QR"
                style="display:block;max-width:240px;max-height:240px;object-fit:contain"
              />
              <p :if={!@gcash_qr} class="staff-settings-card-note">
                No uploaded GCash QR yet. The existing image path will remain in use until you upload one.
              </p>
              <div phx-feedback-for="gcash_qr">
                <.live_file_input upload={@uploads.gcash_qr} id="gcash-qr-file" />
                <p :for={entry <- @uploads.gcash_qr.entries}>
                  {entry.client_name}
                  <span :for={err <- upload_errors(@uploads.gcash_qr, entry)}>
                    {upload_error_message(err)}
                  </span>
                </p>
                <button type="button" phx-click="upload_gcash_qr" class="staff-settings-save-btn">
                  Upload GCash QR
                </button>
              </div>
            </div>
            <.input
              field={@form[:maya_qrph_path]}
              type="text"
              label="Maya QRPh image path"
              placeholder="/images/maya-qrph.png"
            />
          </section>

          <div class="staff-settings-save">
            <button type="submit" class="staff-settings-save-btn" id="settings-save">
              Save settings
            </button>
          </div>
        </.form>
      </main>
    </.staff_shell>
    """
  end

  defp upload_error_message(:too_large), do: "Image must be 2 MB or smaller."
  defp upload_error_message(:not_accepted), do: "Use JPG, PNG, or WebP."
  defp upload_error_message(_), do: "Invalid image."

  defp payments_mode_options do
    [
      {"Counter only (pay at counter)", "counter_only"},
      {"QRPh manual (GCash / Maya QR)", "qrph_manual"},
      {"PayMongo online checkout", "paymongo"}
    ]
  end
end

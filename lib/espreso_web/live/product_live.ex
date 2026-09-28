defmodule EspresoWeb.ProductLive do
  @moduledoc """
  Public Espreso product page and café setup waitlist.
  """

  use EspresoWeb, :live_view

  alias Espreso.Marketing

  @features [
    %{
      id: :home,
      title: "Staff home",
      body: "Paid sales, drawer, and payment mix for the shift."
    },
    %{
      id: :pos,
      title: "Counter POS",
      body: "Walk-in tickets with loyalty, notes, and discounts."
    },
    %{
      id: :qr,
      title: "QR guest menu",
      body: "Customers order on their phone. You run the ticket."
    },
    %{
      id: :kitchen,
      title: "Kitchen board",
      body: "NEW → PREPARING → READY, built for a busy pass."
    },
    %{
      id: :pay,
      title: "Cash, GCash, Maya",
      body: "Pay at the counter or online with PayMongo wallets."
    },
    %{
      id: :shift,
      title: "Open → Close",
      body: "Shop day start, selling, then a proper close."
    },
    %{
      id: :roles,
      title: "Owner, manager, barista",
      body: "PINs and permissions that match how a café actually works."
    },
    %{
      id: :pwa,
      title: "Tablet PWA",
      body: "Add to Home Screen. No separate staff app to install."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Elilai Kafe")
     |> assign(:submitted?, false)
     |> assign(:form, to_form(Marketing.change_shop_request()))}
  end

  @impl true
  def handle_event("request_access", %{"shop_request" => params}, socket) do
    case Marketing.create_shop_request(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:submitted?, true)
         |> assign(:form, to_form(Marketing.change_shop_request()))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :features, @features)

    ~H"""
    <div class="espreso-product">
      <section
        class="espreso-product-panel espreso-product-panel--story"
        aria-labelledby="espreso-product-headline"
      >
        <header class="espreso-product-brand">
          <div class="espreso-product-brand-lockup">
            <img
              src={~p"/images/elilai-kafe/elilai-kafe-mark-product.png"}
              alt="Elilai Kafe"
              class="espreso-product-logo"
              width="493"
              height="615"
              decoding="async"
            />
            <div class="espreso-product-brand-text">
              <p class="espreso-product-wordmark">Elilai Kafe</p>
              <p class="espreso-product-kicker-sub">Café management system</p>
            </div>
          </div>
        </header>

        <h1 id="espreso-product-headline" class="espreso-product-headline">
          Run the café as one shift.
        </h1>
        <p class="espreso-product-lede">
          POS, kitchen, and QR menu — built here, for the counter.
        </p>

        <ul class="espreso-product-features">
          <li :for={feature <- @features} class="espreso-product-feature">
            <span class="espreso-product-feature-icon" aria-hidden="true">
              <.feature_icon id={feature.id} />
            </span>
            <div class="espreso-product-feature-copy">
              <p class="espreso-product-feature-title">{feature.title}</p>
              <p class="espreso-product-feature-body">{feature.body}</p>
            </div>
          </li>
        </ul>

        <div class="espreso-product-soon">
          <p class="espreso-product-soon-title">More later</p>
          <p class="espreso-product-soon-body">
            Claim screen for guests, and ingredient stock. We do not sell those yet.
          </p>
        </div>

        <p class="espreso-product-price">Setup with us · not self-serve</p>
      </section>

      <section class="espreso-product-panel espreso-product-panel--form">
        <div class="espreso-product-tabs" role="tablist" aria-label="Elilai Kafe access">
          <.link navigate={~p"/login"} class="espreso-product-tab" id="product-tab-signin">
            Sign In
          </.link>
          <span class="espreso-product-tab is-active" id="product-tab-request" aria-current="page">
            Request access
          </span>
        </div>

        <div :if={!@submitted?} class="espreso-product-card">
          <h2 id="espreso-product-request-title" class="espreso-product-card-title">
            Request a café setup
          </h2>
          <p class="espreso-product-card-lede">
            We set up each shop ourselves. This is not an instant account.
          </p>

          <.form
            for={@form}
            id="product-request-form"
            class="espreso-product-form"
            phx-submit="request_access"
          >
            <div class="espreso-product-honeypot" aria-hidden="true">
              <label for={@form[:company_url].id}>Company website</label>
              <input
                type="text"
                id={@form[:company_url].id}
                name={@form[:company_url].name}
                value={Phoenix.HTML.Form.normalize_value("text", @form[:company_url].value)}
                tabindex="-1"
                autocomplete="off"
              />
            </div>

            <label class="espreso-product-field">
              <span>Your name</span>
              <input
                type="text"
                id={@form[:contact_name].id}
                name={@form[:contact_name].name}
                value={Phoenix.HTML.Form.normalize_value("text", @form[:contact_name].value)}
                required
                autocomplete="name"
              />
              <p :if={msg = field_error(@form, :contact_name)} class="espreso-product-error">{msg}</p>
            </label>

            <label class="espreso-product-field">
              <span>Café name</span>
              <input
                type="text"
                id={@form[:cafe_name].id}
                name={@form[:cafe_name].name}
                value={Phoenix.HTML.Form.normalize_value("text", @form[:cafe_name].value)}
                required
                autocomplete="organization"
              />
              <p :if={msg = field_error(@form, :cafe_name)} class="espreso-product-error">{msg}</p>
            </label>

            <label class="espreso-product-field">
              <span>City</span>
              <input
                type="text"
                id={@form[:city].id}
                name={@form[:city].name}
                value={Phoenix.HTML.Form.normalize_value("text", @form[:city].value)}
                required
                autocomplete="address-level2"
              />
              <p :if={msg = field_error(@form, :city)} class="espreso-product-error">{msg}</p>
            </label>

            <label class="espreso-product-field">
              <span>Email</span>
              <input
                type="email"
                id={@form[:email].id}
                name={@form[:email].name}
                value={Phoenix.HTML.Form.normalize_value("email", @form[:email].value)}
                required
                autocomplete="email"
              />
              <p :if={msg = field_error(@form, :email)} class="espreso-product-error">{msg}</p>
            </label>

            <label class="espreso-product-field">
              <span>Mobile</span>
              <input
                type="tel"
                id={@form[:mobile].id}
                name={@form[:mobile].name}
                value={Phoenix.HTML.Form.normalize_value("tel", @form[:mobile].value)}
                required
                inputmode="tel"
                autocomplete="tel"
                placeholder="09XXXXXXXXX"
              />
              <p :if={msg = field_error(@form, :mobile)} class="espreso-product-error">{msg}</p>
            </label>

            <label class="espreso-product-field">
              <span>Note <em>(optional)</em></span>
              <textarea id={@form[:note].id} name={@form[:note].name} rows="2">{Phoenix.HTML.Form.normalize_value("textarea", @form[:note].value)}</textarea>
              <p :if={msg = field_error(@form, :note)} class="espreso-product-error">{msg}</p>
            </label>

            <button type="submit" class="espreso-product-submit" id="product-request-submit">
              Request access
            </button>
          </.form>
        </div>

        <div
          :if={@submitted?}
          class="espreso-product-card espreso-product-card--done"
          id="product-request-thanks"
        >
          <h2 class="espreso-product-card-title">We have your request</h2>
          <p class="espreso-product-card-lede">
            Thank you. We will reach out when we can set up another café. This is not an
            instant account.
          </p>
        </div>
      </section>
    </div>
    """
  end

  attr :id, :atom, required: true

  defp feature_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      aria-hidden="true"
    >
      <%= case @id do %>
        <% :home -> %>
          <rect x="4" y="10" width="16" height="10" rx="1.5" />
          <path d="M4 10 12 4l8 6" />
        <% :pos -> %>
          <rect x="5" y="4" width="14" height="16" rx="2" />
          <path d="M8 8h8M8 12h5" />
        <% :qr -> %>
          <rect x="4" y="4" width="7" height="7" rx="1" />
          <rect x="13" y="4" width="7" height="7" rx="1" />
          <rect x="4" y="13" width="7" height="7" rx="1" />
          <path d="M14 14h2v2h-2zM18 14h2v6h-6v-2h4v-4z" />
        <% :kitchen -> %>
          <path d="M4 7h16M7 7v13M17 7v13M7 20h10" />
        <% :pay -> %>
          <rect x="3" y="6" width="18" height="12" rx="2" />
          <path d="M3 10h18" />
        <% :shift -> %>
          <circle cx="12" cy="12" r="8" />
          <path d="M12 8v4l3 2" />
        <% :roles -> %>
          <circle cx="9" cy="8" r="3" />
          <circle cx="16" cy="9" r="2.4" />
          <path d="M4 19c.6-3 2.8-5 5-5s4.4 2 5 5M14 14.2c1.7.3 3.4 1.8 4 4.8" />
        <% :pwa -> %>
          <rect x="5" y="3" width="14" height="18" rx="2" />
          <path d="M10 18h4" />
      <% end %>
    </svg>
    """
  end

  defp field_error(form, field) do
    errors =
      case form[field] do
        %{errors: errors} -> errors
        _ -> []
      end

    case errors do
      [{msg, opts} | _] -> translate_error({msg, opts})
      [msg | _] when is_binary(msg) -> msg
      _ -> nil
    end
  end
end

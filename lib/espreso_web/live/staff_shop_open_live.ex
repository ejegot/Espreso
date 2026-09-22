defmodule EspresoWeb.StaffShopOpenLive do
  @moduledoc """
  Opening cash for the Manila shop day. One record per day; not Time In.
  """
  use EspresoWeb, :live_view

  alias Espreso.Menu
  alias Espreso.Shifts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Shifts.can_access_open?(user) do
      {:ok, assign_open_state(socket), layout: false}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don’t have access to open the shop day.")
       |> push_navigate(to: ~p"/staff"), layout: false}
    end
  end

  @impl true
  def handle_event("validate", %{"open" => params}, socket) do
    {:noreply,
     socket
     |> assign(:opening_cash, Map.get(params, "opening_cash", ""))
     |> assign(:form_error, nil)}
  end

  def handle_event("record_open", %{"open" => params}, socket) do
    if socket.assigns.already_open? or socket.assigns.already_closed? do
      {:noreply, socket}
    else
      case Shifts.record_open(socket.assigns.current_user, params) do
        {:ok, open} ->
          {:noreply,
           socket
           |> put_flash(:info, "Opening cash recorded · #{Menu.format_price(open.opening_cash)}")
           |> assign_open_state()}

        {:error, :already_open} ->
          {:noreply, assign_open_state(socket)}

        {:error, :already_closed} ->
          {:noreply,
           socket
           |> assign_open_state()
           |> assign(:form_error, "This shop day is already closed.")}

        {:error, :opening_cash_required} ->
          {:noreply, assign(socket, :form_error, "Enter the opening cash in the drawer.")}

        {:error, :unauthorized} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don’t have access to open the shop day.")
           |> push_navigate(to: ~p"/staff")}

        {:error, %Ecto.Changeset{}} ->
          {:noreply, assign(socket, :form_error, "Enter a valid opening cash amount.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell
      current={:open_shop}
      current_user={@current_user}
      page_title="Open shop"
      chrome={:bar}
    >
      <main class="staff-shift-close" id="staff-shop-open">
        <header class="staff-shift-close-head">
          <p class="staff-shift-close-eyebrow">Shop day</p>
          <h2>Opening cash</h2>
          <p>
            Count the drawer once at the start of the day. Mid and close shifts do not enter this again.
          </p>
        </header>

        <p class="staff-shift-close-status" id="staff-shop-open-status">
          <%= cond do %>
            <% @already_closed? -> %>
              Closed
            <% @already_open? -> %>
              Opened
            <% true -> %>
              Not opened
          <% end %>
        </p>

        <section :if={@open} class="staff-shift-close-done" id="staff-shop-open-done">
          <p class="staff-shift-close-section-label">Opening cash</p>
          <p class="staff-shift-close-cash-value">{Menu.format_price(@open.opening_cash)}</p>
          <p class="staff-shift-close-section-hint">
            Recorded {Shifts.format_closed_at(@open.opened_at)}
            <span :if={@open.opened_by_user}>· {@open.opened_by_user.name}</span>
          </p>
        </section>

        <p :if={@already_closed? and is_nil(@open)} class="staff-shift-close-section-hint">
          This shop day is already closed. Opening cash was not recorded.
        </p>

        <form
          :if={!@already_open? and !@already_closed?}
          id="staff-shop-open-form"
          phx-change="validate"
          phx-submit="record_open"
          class="staff-shift-close-form"
        >
          <label class="staff-shift-close-field" id="staff-shop-open-cash-field">
            <span>Opening cash</span>
            <div class="staff-shift-close-input-wrap">
              <span class="staff-shift-close-currency" aria-hidden="true">₱</span>
              <input
                type="text"
                name="open[opening_cash]"
                value={@opening_cash}
                inputmode="decimal"
                placeholder="0.00"
                class="staff-shift-close-input"
                id="staff-shop-open-cash"
              />
            </div>
            <span class="staff-shift-close-section-hint">
              Required — cash in the drawer before the first sale.
            </span>
          </label>

          <p :if={@form_error} class="staff-shift-close-error" id="staff-shop-open-error">
            {@form_error}
          </p>

          <button type="submit" class="staff-shift-close-submit" id="staff-shop-open-submit">
            Record opening cash
          </button>
        </form>
      </main>
    </.staff_shell>
    """
  end

  defp assign_open_state(socket) do
    open = Shifts.get_todays_open()
    close = Shifts.get_todays_close()

    socket
    |> assign(:page_title, "Open shop")
    |> assign(:open, open)
    |> assign(:already_open?, not is_nil(open))
    |> assign(:already_closed?, not is_nil(close))
    |> assign(:opening_cash, "")
    |> assign(:form_error, nil)
  end
end

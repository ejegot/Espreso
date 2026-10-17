defmodule EspresoWeb.StaffPettyCashLive do
  use EspresoWeb, :live_view

  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.PettyCash
  alias Espreso.PettyCash.PettyCashEntry
  alias Espreso.Shifts
  alias Espreso.StaffShifts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if PettyCash.can_access?(user) do
      {:ok, assign_state(socket), layout: false}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don’t have access to Petty Cash.")
       |> push_navigate(to: ~p"/staff"), layout: false}
    end
  end

  @impl true
  def handle_event("validate", %{"petty_cash" => params}, socket) do
    {:noreply,
     socket
     |> assign(:amount, Map.get(params, "amount", ""))
     |> assign(:category, Map.get(params, "category", ""))
     |> assign(:note, Map.get(params, "note", ""))
     |> assign(:form_error, nil)}
  end

  def handle_event("create", %{"petty_cash" => params}, socket) do
    if socket.assigns.blocked? do
      {:noreply, socket}
    else
      case PettyCash.create_entry(socket.assigns.current_user, params) do
        {:ok, entry} ->
          {:noreply,
           socket
           |> put_flash(:info, "Petty-cash purchase recorded.")
           |> assign(:amount, "")
           |> assign(:category, "")
           |> assign(:note, "")
           |> assign(:form_error, nil)
           |> assign(:last_recorded, entry)
           |> reload_entries()}

        {:error, :not_on_shift} ->
          {:noreply,
           assign(socket, :form_error, "You need an open staff shift to record a purchase.")}

        {:error, :shop_not_open} ->
          {:noreply, assign(socket, :form_error, Shifts.selling_blocked_message(:shop_not_open))}

        {:error, :shop_day_closed} ->
          {:noreply, assign(socket, :form_error, "This shop day is already closed.")}

        {:error, :insufficient_petty_cash} ->
          {:noreply,
           socket
           |> reload_entries()
           |> assign(:form_error, "That amount is more than the remaining petty-cash balance.")}

        {:error, :unauthorized} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don’t have access to Petty Cash.")
           |> push_navigate(to: ~p"/staff")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form_error, entry_error(changeset))}
      end
    end
  end

  def handle_event("ask_void", %{"entry_id" => id}, socket) do
    entry = Enum.find(socket.assigns.entries, &("#{&1.id}" == id))

    if PettyCash.can_void?(socket.assigns.current_user) and entry &&
         entry.status == "recorded" and not socket.assigns.shop_day_closed? do
      {:noreply,
       socket
       |> assign(:voiding, entry)
       |> assign(:void_reason, "")
       |> assign(:void_error, nil)}
    else
      {:noreply, put_flash(socket, :error, "Unable to void that petty-cash entry.")}
    end
  end

  def handle_event("cancel_void", _params, socket) do
    {:noreply, clear_voiding(socket)}
  end

  def handle_event("void", %{"entry_id" => id, "reason" => reason}, socket) do
    user = socket.assigns.current_user
    entry = Enum.find(socket.assigns.entries, &("#{&1.id}" == id))

    if PettyCash.can_void?(user) and match?(%PettyCashEntry{}, entry) do
      case PettyCash.void_entry(entry, user, reason) do
        {:ok, _voided} ->
          {:noreply,
           socket
           |> put_flash(:info, "Petty-cash entry voided.")
           |> clear_voiding()
           |> reload_entries()}

        {:error, :shop_day_closed} ->
          {:noreply,
           socket
           |> clear_voiding()
           |> put_flash(:error, "This shop day is already closed.")}

        {:error, :already_voided} ->
          {:noreply,
           socket
           |> clear_voiding()
           |> put_flash(:error, "That entry is already voided.")}

        {:error, %Ecto.Changeset{}} ->
          {:noreply, assign(socket, :void_error, "Enter a reason to void this entry.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Unable to void that petty-cash entry.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell
      current={:petty_cash}
      current_user={@current_user}
      page_title="Petty cash"
      chrome={:bar}
    >
      <main class="staff-cash-out" id="staff-petty-cash">
        <header class="staff-cash-out-head">
          <p class="staff-cash-out-scope">
            Record purchases paid from the separate petty-cash box. Do not use Cash Out for these purchases.
          </p>
        </header>

        <section class="staff-cash-out-today" id="staff-petty-cash-balance">
          <p class="staff-cash-out-section-label">Petty-cash float</p>
          <p class="staff-cash-out-total">{Menu.format_price(@remaining)}</p>
          <p class="staff-cash-out-history-hint">
            Starts at {Menu.format_price(PettyCash.float())}; purchases are replenished from the drawer at closing.
          </p>
        </section>

        <section :if={@blocked?} class="staff-cash-out-blocked" id="staff-petty-cash-blocked">
          <p class="staff-cash-out-blocked-title">Cannot record a purchase</p>
          <p class="staff-cash-out-blocked-copy">{@block_message}</p>
          <.link navigate={~p"/staff"} class="staff-shell-tool">Back to Home</.link>
        </section>

        <section :if={@last_recorded} class="staff-cash-out-confirm" role="status">
          <p class="staff-cash-out-confirm-title">Purchase recorded</p>
          <p class="staff-cash-out-confirm-amount">{Menu.format_price(@last_recorded.amount)}</p>
          <p class="staff-cash-out-confirm-meta">
            {@last_recorded.category} · {@last_recorded.note}
          </p>
        </section>

        <form
          :if={!@blocked?}
          id="staff-petty-cash-form"
          phx-change="validate"
          phx-submit="create"
          class="staff-cash-out-form"
        >
          <label class="staff-cash-out-field">
            <span>Amount paid</span>
            <div class="staff-cash-out-input-wrap">
              <span class="staff-cash-out-currency" aria-hidden="true">₱</span>
              <input
                type="text"
                name="petty_cash[amount]"
                value={@amount}
                inputmode="decimal"
                placeholder="0.00"
                class="staff-cash-out-input"
                required
              />
            </div>
          </label>

          <label class="staff-cash-out-field">
            <span>Category</span>
            <select name="petty_cash[category]" class="staff-cash-out-select" required>
              <option value="">Choose a category</option>
              <option
                :for={category <- PettyCashEntry.categories()}
                value={category}
                selected={@category == category}
              >
                {category}
              </option>
            </select>
          </label>

          <label class="staff-cash-out-field">
            <span>What was purchased?</span>
            <textarea
              name="petty_cash[note]"
              rows="2"
              maxlength="500"
              placeholder="Required — e.g. bag of ice"
              class="staff-cash-out-input staff-cash-out-input--notes"
              required
            >{@note}</textarea>
          </label>

          <p :if={@form_error} class="staff-cash-out-error" id="staff-petty-cash-error">
            {@form_error}
          </p>

          <button type="submit" class="staff-cash-out-submit" phx-disable-with="Recording…">
            Record petty-cash purchase
          </button>
        </form>

        <section class="staff-cash-out-today" aria-label="Today's petty-cash purchases">
          <div class="staff-cash-out-today-head">
            <div>
              <p class="staff-cash-out-section-label">Today’s purchases</p>
              <p class="staff-cash-out-total" id="staff-petty-cash-total">
                {Menu.format_price(@total)}
              </p>
            </div>
            <p class="staff-cash-out-count">{length(@recorded_entries)} purchases</p>
          </div>

          <ul :if={@entries != []} class="staff-cash-out-list" id="staff-petty-cash-list">
            <li
              :for={entry <- @entries}
              class={["staff-cash-out-row", entry.status == "voided" && "staff-cash-out-row--voided"]}
              id={"staff-petty-cash-entry-#{entry.id}"}
            >
              <div class="staff-cash-out-row-main">
                <p class="staff-cash-out-row-amount">{Menu.format_price(entry.amount)}</p>
                <p class="staff-cash-out-row-category">{entry.category}</p>
                <p class="staff-cash-out-row-note">{entry.note}</p>
                <p class="staff-cash-out-row-meta">
                  Today · {format_shop_time(entry.recorded_at)}
                  <span :if={entry.created_by_user}>· {entry.created_by_user.name}</span>
                </p>
                <p :if={entry.status == "voided"} class="staff-cash-out-void-badge">
                  VOIDED · {entry.void_reason}
                </p>
              </div>
              <button
                :if={@can_void? and entry.status == "recorded" and not @shop_day_closed?}
                type="button"
                class="staff-shell-tool staff-shell-tool--quiet"
                phx-click="ask_void"
                phx-value-entry_id={entry.id}
              >
                Void
              </button>
            </li>
          </ul>
          <p :if={@entries == []} class="staff-cash-out-empty">
            No petty-cash purchases recorded today.
          </p>
        </section>

        <section class="staff-cash-out-history" id="staff-petty-cash-history">
          <div class="staff-cash-out-history-head">
            <p class="staff-cash-out-section-label">Recent history</p>
            <p class="staff-cash-out-history-hint">Previous 30 shop days · up to 100 entries.</p>
          </div>
          <ul :if={@history_entries != []} class="staff-cash-out-list">
            <li
              :for={entry <- @history_entries}
              class={[
                "staff-cash-out-row",
                entry.status == "voided" && "staff-cash-out-row--voided"
              ]}
              id={"staff-petty-cash-history-entry-#{entry.id}"}
            >
              <div class="staff-cash-out-row-main">
                <p class="staff-cash-out-row-amount">{Menu.format_price(entry.amount)}</p>
                <p class="staff-cash-out-row-category">
                  {Calendar.strftime(entry.shop_date, "%b %-d, %Y")} · {entry.category}
                </p>
                <p class="staff-cash-out-row-note">{entry.note}</p>
                <p class="staff-cash-out-row-meta">
                  <span :if={entry.created_by_user}>{entry.created_by_user.name}</span>
                  <span :if={entry.status == "voided"} class="staff-cash-out-void-badge">
                    VOIDED · {entry.void_reason}
                  </span>
                </p>
              </div>
            </li>
          </ul>
          <p :if={@history_entries == []} class="staff-cash-out-empty">
            No petty-cash history from previous shop days.
          </p>
        </section>

        <.modal
          :if={@voiding}
          id="staff-petty-cash-void-modal"
          show
          click_away={false}
          autofocus={false}
          on_cancel={JS.push("cancel_void")}
        >
          <div class="staff-cash-out-void-form">
            <p class="staff-cash-out-confirm-title">Void petty-cash entry?</p>
            <p>{Menu.format_price(@voiding.amount)} · {@voiding.note}</p>
            <form phx-submit="void">
              <input type="hidden" name="entry_id" value={@voiding.id} />
              <label class="staff-cash-out-field">
                <span>Reason</span>
                <textarea name="reason" rows="2" maxlength="500" required>{@void_reason}</textarea>
              </label>
              <p :if={@void_error} class="staff-cash-out-error">{@void_error}</p>
              <button type="submit" class="staff-cash-out-submit">Void entry</button>
              <button type="button" class="staff-shell-tool" phx-click="cancel_void">Cancel</button>
            </form>
          </div>
        </.modal>
      </main>
    </.staff_shell>
    """
  end

  defp assign_state(socket) do
    user = socket.assigns.current_user
    shop_date = Orders.shop_date_today()
    shop_day_closed? = not is_nil(Shifts.get_close_for_date(shop_date))

    {blocked?, block_message} =
      cond do
        shop_day_closed? ->
          {true, "This shop day is already closed."}

        Shifts.shop_day_status() == :not_open ->
          {true, Shifts.selling_blocked_message(:shop_not_open)}

        user.role == "barista" and is_nil(StaffShifts.get_open_shift(user)) ->
          {true, "You need an open staff shift to record a purchase."}

        true ->
          {false, nil}
      end

    load_entries(socket, shop_date)
    |> assign(:page_title, "Petty cash")
    |> assign(:shop_date, shop_date)
    |> assign(:shop_day_closed?, shop_day_closed?)
    |> assign(:blocked?, blocked?)
    |> assign(:block_message, block_message)
    |> assign(:can_void?, PettyCash.can_void?(user))
    |> assign(:amount, "")
    |> assign(:category, "")
    |> assign(:note, "")
    |> assign(:form_error, nil)
    |> assign(:last_recorded, nil)
    |> assign(:voiding, nil)
    |> assign(:void_reason, "")
    |> assign(:void_error, nil)
    |> assign(:history_entries, PettyCash.list_recent_history())
  end

  defp load_entries(socket, shop_date) do
    entries = PettyCash.list_for_shop_date(shop_date)
    recorded = Enum.filter(entries, &(&1.status == "recorded"))
    total = PettyCash.total_for_shop_date(shop_date)

    socket
    |> assign(:entries, entries)
    |> assign(:recorded_entries, recorded)
    |> assign(:total, total)
    |> assign(:remaining, Decimal.max(Decimal.sub(PettyCash.float(), total), Decimal.new("0")))
  end

  defp reload_entries(socket), do: load_entries(socket, socket.assigns.shop_date)

  defp clear_voiding(socket) do
    socket
    |> assign(:voiding, nil)
    |> assign(:void_reason, "")
    |> assign(:void_error, nil)
  end

  defp format_shop_time(%DateTime{} = at) do
    at
    |> DateTime.add(8 * 60 * 60, :second)
    |> Calendar.strftime("%-I:%M %p")
  end

  defp entry_error(changeset) do
    cond do
      Keyword.has_key?(changeset.errors, :amount) -> "Enter an amount greater than zero."
      Keyword.has_key?(changeset.errors, :category) -> "Choose a category."
      Keyword.has_key?(changeset.errors, :note) -> "Enter what was purchased."
      true -> "Could not record the purchase. Check the details and try again."
    end
  end
end

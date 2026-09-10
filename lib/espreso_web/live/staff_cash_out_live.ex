defmodule EspresoWeb.StaffCashOutLive do
  @moduledoc """
  Staff Cash Out — record physical drawer withdrawals for shop expenses.
  """
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User
  alias Espreso.CashOuts
  alias Espreso.CashOuts.CashOut
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.StaffShifts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if CashOuts.can_access?(user) do
      {:ok, assign_cash_out_state(socket), layout: false}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don’t have access to Cash Out.")
       |> push_navigate(to: ~p"/staff"), layout: false}
    end
  end

  @impl true
  def handle_event("validate", %{"cash_out" => params}, socket) do
    {:noreply,
     socket
     |> assign(:amount, Map.get(params, "amount", ""))
     |> assign(:category, Map.get(params, "category", ""))
     |> assign(:note, Map.get(params, "note", ""))
     |> assign(:form_error, nil)}
  end

  def handle_event("create", %{"cash_out" => params}, socket) do
    if socket.assigns.blocked? do
      {:noreply, socket}
    else
      case CashOuts.create_cash_out(socket.assigns.current_user, params) do
        {:ok, cash_out} ->
          {:noreply,
           socket
           |> put_flash(:info, "Cash Out recorded · #{Menu.format_price(cash_out.amount)}")
           |> assign(:amount, "")
           |> assign(:category, "")
           |> assign(:note, "")
           |> assign(:form_error, nil)
           |> assign(:last_recorded, cash_out)
           |> reload_list()}

        {:error, :not_on_shift} ->
          {:noreply,
           socket
           |> assign_cash_out_state()
           |> assign(:form_error, "You need an open staff shift to record a Cash Out.")}

        {:error, :shop_day_closed} ->
          {:noreply,
           socket
           |> assign_cash_out_state()
           |> assign(
             :form_error,
             "This shop day is already closed. Cash Out transactions can no longer be changed."
           )}

        {:error, :unauthorized} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don’t have access to Cash Out.")
           |> push_navigate(to: ~p"/staff")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form_error, create_error(changeset))}
      end
    end
  end

  def handle_event("void", %{"cash_out_id" => id, "reason" => reason}, socket) do
    user = socket.assigns.current_user

    with true <- CashOuts.can_void?(user),
         %CashOut{} = cash_out <- Enum.find(socket.assigns.cash_outs, &("#{&1.id}" == id)) do
      case CashOuts.void_cash_out(cash_out, user, reason) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Cash Out voided")
           |> reload_list()}

        {:error, :shop_day_closed} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "This shop day is already closed. Cash Out transactions can no longer be changed."
           )}

        {:error, :already_voided} ->
          {:noreply, put_flash(socket, :error, "That Cash Out is already voided.")}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, "You don’t have permission to void Cash Outs.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, put_flash(socket, :error, void_error(changeset))}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Unable to void that Cash Out.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:cash_out} current_user={@current_user} page_title="Cash Out">
      <main class="staff-cash-out" id="staff-cash-out">
        <header class="staff-cash-out-head">
          <p class="staff-home-desk-eyebrow">Drawer</p>
          <h2 class="staff-home-desk-title">Cash Out</h2>
          <p class="staff-home-lede">
            Record money taken from the cash drawer for legitimate shop expenses.
            This is not a sale.
          </p>
        </header>

        <section
          :if={@blocked?}
          class="staff-cash-out-blocked"
          id="staff-cash-out-blocked"
          role="status"
        >
          <p class="staff-cash-out-blocked-title">Cannot record Cash Out</p>
          <p class="staff-cash-out-blocked-copy" id="staff-cash-out-blocked-copy">
            {@block_message}
          </p>
          <.link navigate={~p"/staff"} class="staff-shell-tool">Back to Home</.link>
        </section>

        <section
          :if={@last_recorded}
          class="staff-cash-out-confirm"
          id="staff-cash-out-confirm"
          role="status"
        >
          <p class="staff-cash-out-confirm-title">Cash Out recorded</p>
          <p class="staff-cash-out-confirm-amount">
            {Menu.format_price(@last_recorded.amount)}
          </p>
          <p class="staff-cash-out-confirm-meta">
            {@last_recorded.category}
            <span :if={@last_recorded.note}>· {@last_recorded.note}</span>
          </p>
        </section>

        <form
          :if={!@blocked?}
          id="staff-cash-out-form"
          phx-change="validate"
          phx-submit="create"
          class="staff-cash-out-form"
        >
          <label class="staff-cash-out-field">
            <span>Amount</span>
            <div class="staff-cash-out-input-wrap">
              <span class="staff-cash-out-currency" aria-hidden="true">₱</span>
              <input
                type="text"
                name="cash_out[amount]"
                value={@amount}
                inputmode="decimal"
                placeholder="0.00"
                required
                class="staff-cash-out-input"
                id="staff-cash-out-amount"
              />
            </div>
          </label>

          <label class="staff-cash-out-field">
            <span>Category</span>
            <select
              name="cash_out[category]"
              required
              class="staff-cash-out-input staff-cash-out-select"
              id="staff-cash-out-category"
            >
              <option value="">Select category</option>
              <option
                :for={category <- CashOut.categories()}
                value={category}
                selected={@category == category}
              >
                {category}
              </option>
            </select>
          </label>

          <label class="staff-cash-out-field">
            <span>Note</span>
            <textarea
              name="cash_out[note]"
              rows="2"
              maxlength="500"
              placeholder="Optional — what was purchased"
              class="staff-cash-out-input staff-cash-out-input--notes"
              id="staff-cash-out-note"
            >{@note}</textarea>
          </label>

          <p :if={@form_error} class="staff-cash-out-error" id="staff-cash-out-error">
            {@form_error}
          </p>

          <button
            type="submit"
            class="staff-cash-out-submit"
            id="staff-cash-out-submit"
            phx-disable-with="Recording…"
          >
            Record Cash Out
          </button>
        </form>

        <section class="staff-cash-out-today" id="staff-cash-out-today" aria-label="Today's Cash Outs">
          <div class="staff-cash-out-today-head">
            <div>
              <p class="staff-cash-out-section-label">Today’s Cash Out</p>
              <p class="staff-cash-out-total" id="staff-cash-out-total">
                {Menu.format_price(@total)}
              </p>
            </div>
            <p class="staff-cash-out-count" id="staff-cash-out-count">
              {length(@recorded_cash_outs)} Cash Outs
            </p>
          </div>

          <ul :if={@cash_outs != []} class="staff-cash-out-list" id="staff-cash-out-list">
            <li
              :for={entry <- @cash_outs}
              class={[
                "staff-cash-out-row",
                entry.status == "voided" && "staff-cash-out-row--voided"
              ]}
              id={"staff-cash-out-row-#{entry.id}"}
            >
              <div class="staff-cash-out-row-main">
                <p class="staff-cash-out-row-amount">{Menu.format_price(entry.amount)}</p>
                <p class="staff-cash-out-row-category">{entry.category}</p>
                <p :if={entry.note} class="staff-cash-out-row-note">{entry.note}</p>
                <p class="staff-cash-out-row-meta">
                  Today · {format_shop_time(entry.recorded_at)}
                  <span :if={entry.created_by_user}>
                    · Recorded by {entry.created_by_user.name}
                  </span>
                </p>
                <p
                  :if={entry.status == "voided"}
                  class="staff-cash-out-void-badge"
                  id={"staff-cash-out-voided-#{entry.id}"}
                >
                  VOIDED <span :if={entry.void_reason}>· {entry.void_reason}</span>
                </p>
              </div>

              <form
                :if={@can_void? and entry.status == "recorded" and not @shop_day_closed?}
                id={"staff-cash-out-void-form-#{entry.id}"}
                phx-submit="void"
                class="staff-cash-out-void-form"
              >
                <input type="hidden" name="cash_out_id" value={entry.id} />
                <input
                  type="text"
                  name="reason"
                  required
                  maxlength="500"
                  placeholder="Void reason"
                  class="staff-cash-out-input staff-cash-out-void-reason"
                  id={"staff-cash-out-void-reason-#{entry.id}"}
                />
                <button
                  type="submit"
                  class="staff-shell-tool staff-shell-tool--quiet"
                  id={"staff-cash-out-void-#{entry.id}"}
                  phx-disable-with="Voiding…"
                >
                  Void
                </button>
              </form>
            </li>
          </ul>

          <p :if={@cash_outs == []} class="staff-cash-out-empty" id="staff-cash-out-empty">
            No Cash Outs recorded today.
          </p>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp assign_cash_out_state(socket) do
    user = socket.assigns.current_user
    shop_date = Orders.shop_date_today()
    shop_day_closed? = not is_nil(Espreso.Shifts.get_close_for_date(shop_date))

    {blocked?, block_message} =
      cond do
        shop_day_closed? ->
          {true,
           "This shop day is already closed. Cash Out transactions can no longer be changed."}

        barista?(user) and is_nil(StaffShifts.get_open_shift(user)) ->
          {true, "You need an open staff shift to record a Cash Out."}

        true ->
          {false, nil}
      end

    cash_outs = CashOuts.list_cash_outs_for_shop_date(shop_date)
    recorded = Enum.filter(cash_outs, &(&1.status == "recorded"))

    socket
    |> assign(:page_title, "Cash Out")
    |> assign(:shop_date, shop_date)
    |> assign(:shop_day_closed?, shop_day_closed?)
    |> assign(:blocked?, blocked?)
    |> assign(:block_message, block_message)
    |> assign(:can_void?, CashOuts.can_void?(user))
    |> assign(:cash_outs, cash_outs)
    |> assign(:recorded_cash_outs, recorded)
    |> assign(:total, CashOuts.total_for_shop_date(shop_date))
    |> assign(:amount, "")
    |> assign(:category, "")
    |> assign(:note, "")
    |> assign(:form_error, nil)
    |> assign(:last_recorded, nil)
  end

  defp reload_list(socket) do
    shop_date = socket.assigns.shop_date
    cash_outs = CashOuts.list_cash_outs_for_shop_date(shop_date)
    recorded = Enum.filter(cash_outs, &(&1.status == "recorded"))

    socket
    |> assign(:cash_outs, cash_outs)
    |> assign(:recorded_cash_outs, recorded)
    |> assign(:total, CashOuts.total_for_shop_date(shop_date))
  end

  defp barista?(%User{role: "barista"}), do: true
  defp barista?(_), do: false

  defp format_shop_time(%DateTime{} = at) do
    at
    |> DateTime.add(8 * 60 * 60, :second)
    |> Calendar.strftime("%-I:%M %p")
    |> String.trim_leading("0")
  end

  defp create_error(changeset) do
    cond do
      Keyword.has_key?(changeset.errors, :amount) ->
        "Enter a valid amount greater than zero."

      Keyword.has_key?(changeset.errors, :category) ->
        "Select a category."

      true ->
        "Could not record Cash Out. Check the details and try again."
    end
  end

  defp void_error(changeset) do
    if Keyword.has_key?(changeset.errors, :void_reason) do
      "A void reason is required."
    else
      "Could not void Cash Out."
    end
  end
end

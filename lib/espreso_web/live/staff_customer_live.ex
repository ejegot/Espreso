defmodule EspresoWeb.StaffCustomerLive do
  @moduledoc """
  Staff-facing customer lookup and read-only loyalty/order history.
  """
  use EspresoWeb, :live_view

  alias Espreso.Customers
  alias Espreso.Customers.Customer
  alias Espreso.Loyalty
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.Order

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Customers")
     |> assign(:phone_query, "")
     |> assign(:search_error, nil)
     |> assign(:customer, nil)
     |> assign(:orders, [])
     |> assign(:activity, [])
     |> assign(:reward_available?, false), layout: false}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Integer.parse(id) do
      {customer_id, ""} ->
        case Customers.get_customer(customer_id) do
          %Customer{} = customer ->
            {:noreply, assign_customer(socket, customer)}

          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "Customer not found.")
             |> push_navigate(to: ~p"/customers")}
        end

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Customer not found.")
         |> push_navigate(to: ~p"/customers")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "Customers")
     |> assign(:customer, nil)
     |> assign(:orders, [])
     |> assign(:activity, [])
     |> assign(:reward_available?, false)
     |> assign(:search_error, nil)}
  end

  @impl true
  def handle_event("search_phone", %{"phone" => phone}, socket) do
    phone = to_string(phone || "")

    case Customers.get_by_phone(phone) do
      {:ok, customer} ->
        {:noreply,
         socket
         |> assign(:phone_query, phone)
         |> assign(:search_error, nil)
         |> push_navigate(to: ~p"/customers/#{customer.id}")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:phone_query, phone)
         |> assign(:search_error, "No customer found for that phone.")}

      {:error, :invalid_phone} ->
        {:noreply,
         socket
         |> assign(:phone_query, phone)
         |> assign(:search_error, "Enter a valid Philippine mobile number.")}
    end
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:phone_query, "")
     |> assign(:search_error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:customers} current_user={@current_user} page_title={@page_title}>
      <main class="staff-customer" id="staff-customer">
        <%= if @live_action == :show and @customer do %>
          <.customer_detail
            customer={@customer}
            orders={@orders}
            activity={@activity}
            reward_available?={@reward_available?}
          />
        <% else %>
          <.customer_search phone_query={@phone_query} search_error={@search_error} />
        <% end %>
      </main>
    </.staff_shell>
    """
  end

  defp customer_search(assigns) do
    ~H"""
    <header class="staff-customer-head">
      <div>
        <p class="staff-customer-eyebrow">Loyalty</p>
        <h2>Customers</h2>
        <p>Look up a phone to view points and recent history.</p>
      </div>
    </header>

    <form class="staff-customer-search" id="customer-search-form" phx-submit="search_phone">
      <label class="staff-customer-field" for="customer-search-phone">
        <span>Phone</span>
        <input
          type="tel"
          id="customer-search-phone"
          name="phone"
          value={@phone_query}
          placeholder="09XXXXXXXXX"
          autocomplete="tel"
          inputmode="tel"
          required
        />
      </label>
      <div class="staff-customer-search-actions">
        <button type="submit" id="customer-search-submit">Find customer</button>
        <button
          :if={@phone_query != ""}
          type="button"
          id="customer-search-clear"
          phx-click="clear_search"
        >
          Clear
        </button>
      </div>
    </form>

    <p :if={@search_error} class="staff-customer-error" id="customer-search-error">
      {@search_error}
    </p>

    <p class="staff-customer-hint" id="customer-search-hint">
      Search does not create a customer. New loyalty accounts are created from POS or QR checkout.
    </p>
    """
  end

  defp customer_detail(assigns) do
    ~H"""
    <header class="staff-customer-head" id="customer-profile">
      <div>
        <p class="staff-customer-eyebrow">Customer</p>
        <h2 id="customer-name">{display_name(@customer)}</h2>
        <p id="customer-phone">{@customer.phone_e164}</p>
      </div>
      <.link navigate={~p"/customers"} class="staff-customer-back" id="customer-back">
        New search
      </.link>
    </header>

    <section class="staff-customer-loyalty" id="customer-loyalty" aria-label="Loyalty summary">
      <div class="staff-customer-loyalty-main">
        <p class="staff-customer-loyalty-label">Points</p>
        <p class="staff-customer-points" id="customer-points">
          {@customer.points_balance}
          <span>{points_label(@customer.points_balance)}</span>
        </p>
        <p :if={@reward_available?} class="staff-customer-reward" id="customer-reward-available">
          Reward available
        </p>
        <p :if={!@reward_available?} class="staff-customer-reward-muted" id="customer-reward-progress">
          {points_to_reward(@customer.points_balance)} more to redeem
        </p>
      </div>
      <div class="staff-customer-loyalty-side">
        <p class="staff-customer-loyalty-label">Toward next point</p>
        <p id="customer-spend-progress">
          {format_centavos(@customer.spend_remainder_centavos)} / {format_centavos(
            Loyalty.point_threshold_centavos()
          )}
        </p>
        <p class="staff-customer-hint">Based on paid qualifying spend already on file.</p>
      </div>
    </section>

    <section class="staff-customer-section" id="customer-orders" aria-label="Recent orders">
      <header class="staff-customer-section-head">
        <h3>Recent orders</h3>
        <p>Orders linked to this phone. Walk-in name-only tickets are not listed.</p>
      </header>

      <div :if={@orders == []} class="staff-customer-empty" id="customer-orders-empty">
        <strong>No linked orders yet</strong>
        <p class="staff-customer-empty-hint">
          History appears after a paid order is attached to this customer.
        </p>
      </div>

      <ul :if={@orders != []} class="staff-customer-list" id="customer-orders-list">
        <li :for={order <- @orders} class="staff-customer-row" id={"customer-order-#{order.id}"}>
          <div class="staff-customer-row-main">
            <strong>{order.number}</strong>
            <span>{format_shop_datetime(order.inserted_at)}</span>
          </div>
          <div class="staff-customer-row-meta">
            <span>{order_source_label(order)}</span>
            <span>{payment_status_label(order)}</span>
            <strong>{Menu.format_price(order.total)}</strong>
            <span :if={loyalty_free?(order)} class="staff-customer-free">
              Loyalty free {format_centavos(order.loyalty_free_amount_centavos)}
            </span>
          </div>
          <p :if={item_summary(order) != ""} class="staff-customer-items">{item_summary(order)}</p>
        </li>
      </ul>
    </section>

    <section class="staff-customer-section" id="customer-activity" aria-label="Loyalty activity">
      <header class="staff-customer-section-head">
        <h3>Loyalty activity</h3>
        <p>Earn and redeem ledger entries for this customer.</p>
      </header>

      <div :if={@activity == []} class="staff-customer-empty" id="customer-activity-empty">
        <strong>No loyalty activity yet</strong>
        <p class="staff-customer-empty-hint">
          Points activity appears after the first earn or redeem.
        </p>
      </div>

      <ul :if={@activity != []} class="staff-customer-list" id="customer-activity-list">
        <li :for={entry <- @activity} class="staff-customer-row" id={"customer-activity-#{entry.id}"}>
          <div class="staff-customer-row-main">
            <strong>{activity_kind_label(entry.kind)}</strong>
            <span class={activity_points_class(entry.points)}>
              {format_points_delta(entry.points)}
            </span>
            <span>{format_shop_datetime(entry.inserted_at)}</span>
          </div>
          <div class="staff-customer-row-meta">
            <span :if={entry.order}>{entry.order.number}</span>
            <span :if={entry.kind == "earn" and is_integer(entry.qualifying_amount_centavos)}>
              Qualifying {format_centavos(entry.qualifying_amount_centavos)}
            </span>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  defp assign_customer(socket, customer) do
    orders = Orders.list_orders_for_customer(customer.id)
    activity = Loyalty.list_activity_for_customer(customer.id)

    socket
    |> assign(:page_title, display_name(customer))
    |> assign(:customer, customer)
    |> assign(:orders, orders)
    |> assign(:activity, activity)
    |> assign(:reward_available?, customer.points_balance >= Loyalty.redeem_cost())
    |> assign(:search_error, nil)
  end

  defp display_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp display_name(_), do: "No name on file"

  defp points_label(1), do: "point"
  defp points_label(_), do: "points"

  defp points_to_reward(balance) when is_integer(balance) do
    max(Loyalty.redeem_cost() - balance, 0)
  end

  defp format_centavos(centavos) when is_integer(centavos) do
    Orders.format_reconciliation_amount(centavos)
  end

  defp format_centavos(_), do: "—"

  defp loyalty_free?(%Order{loyalty_free_amount_centavos: n}) when is_integer(n) and n > 0,
    do: true

  defp loyalty_free?(_), do: false

  defp order_source_label(%Order{source: "pos"}), do: "POS"
  defp order_source_label(%Order{source: "customer"}), do: "QR menu"
  defp order_source_label(%Order{source: source}) when is_binary(source), do: source
  defp order_source_label(_), do: "—"

  defp payment_status_label(%Order{payment_status: "paid"}), do: "Paid"
  defp payment_status_label(%Order{payment_status: "awaiting_payment"}), do: "Awaiting payment"
  defp payment_status_label(%Order{payment_status: "unpaid"}), do: "Unpaid"
  defp payment_status_label(%Order{payment_status: status}) when is_binary(status), do: status
  defp payment_status_label(_), do: "—"

  defp item_summary(%Order{items: items}) when is_list(items) and items != [] do
    items
    |> Enum.map(fn item ->
      size = if is_binary(item.size) and item.size != "", do: " (#{item.size})", else: ""
      "#{item.quantity}× #{item.name}#{size}"
    end)
    |> Enum.join(", ")
  end

  defp item_summary(_), do: ""

  defp activity_kind_label("earn"), do: "Earn"
  defp activity_kind_label("redeem"), do: "Redeem"
  defp activity_kind_label(other) when is_binary(other), do: String.capitalize(other)
  defp activity_kind_label(_), do: "Activity"

  defp format_points_delta(points) when is_integer(points) and points > 0, do: "+#{points}"
  defp format_points_delta(points) when is_integer(points), do: Integer.to_string(points)
  defp format_points_delta(_), do: "—"

  defp activity_points_class(points) when is_integer(points) and points < 0,
    do: "staff-customer-delta--redeem"

  defp activity_points_class(_), do: "staff-customer-delta--earn"

  defp format_shop_datetime(%DateTime{} = at) do
    at
    |> manila_time()
    |> Calendar.strftime("%b %-d, %Y · %-I:%M %p")
  end

  defp format_shop_datetime(_), do: "—"

  defp manila_time(at), do: DateTime.add(at, 8 * 60 * 60, :second)
end

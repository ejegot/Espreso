defmodule EspresoWeb.Api.JSON do
  @moduledoc false

  alias Espreso.Accounts.User
  alias Espreso.BusinessSettings
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.Order

  def user(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role
    }
  end

  def roster_entry(%{id: id, name: name, role: role}) do
    %{id: id, name: name, role: role}
  end

  def order(%Order{} = order) do
    %{
      id: order.id,
      number: order.number,
      customer_name: order.customer_name,
      fulfillment: order.fulfillment,
      table_number: order.table_number,
      notes: order.notes,
      status: order.status,
      payment_method: order.payment_method,
      payment_status: order.payment_status,
      paid_via: order.paid_via,
      online_wallet: order.online_wallet,
      payment_label: Orders.payment_label(order),
      source: order.source,
      total: decimal_string(order.total),
      total_label: Orders.format_total(order),
      items: Enum.map(order.items || [], &order_item/1),
      inserted_at: datetime_iso8601(order.inserted_at),
      updated_at: datetime_iso8601(order.updated_at)
    }
  end

  def order_item(item) do
    %{
      id: item.id,
      name: item.name,
      size: item.size,
      quantity: item.quantity,
      unit_price: decimal_string(item.unit_price),
      line_total: decimal_string(item.line_total)
    }
  end

  def menu(categories) when is_list(categories) do
    Enum.map(categories, fn category ->
      %{
        name: category.name,
        products:
          Enum.map(category.products, fn product ->
            %{
              id: product.id,
              name: product.name,
              description: product.description,
              available: product.available,
              image_path: Menu.product_image(category.name, product.name),
              prices:
                Enum.map(product.product_prices, fn price ->
                  %{
                    id: price.id,
                    size: price.size,
                    price: decimal_string(price.price),
                    price_label: Menu.format_price(price.price)
                  }
                end)
            }
          end)
      }
    end)
  end

  def business_settings do
    setting = BusinessSettings.get()
    config = BusinessSettings.payment_config()

    %{
      business_name: setting.business_name,
      address: setting.address,
      phone: setting.phone,
      email: setting.email,
      hours_lines: setting.hours_lines,
      payments_mode: config.payments_mode,
      gcash_qrph_path: config.gcash_qrph_path,
      maya_qrph_path: config.maya_qrph_path
    }
  end

  defp decimal_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp decimal_string(nil), do: nil

  defp datetime_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime_iso8601(_), do: nil
end

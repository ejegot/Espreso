defmodule EspresoWeb.SalesExportController do
  @moduledoc """
  Authenticated Excel download for Owner/Manager sales reports.
  """
  use EspresoWeb, :controller

  alias Espreso.Accounts.Authorization
  alias Espreso.Orders
  alias Espreso.Reports.SalesExport

  @xlsx_content_type "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

  def download(conn, params) do
    user = conn.assigns.current_user

    with true <- Authorization.can?(user, :reports),
         {:ok, from_date} <- parse_date(params["from"]),
         {:ok, to_date} <- parse_date(params["to"]),
         :ok <- Orders.validate_sales_export_shop_dates(from_date, to_date),
         {:ok, orders} <- Orders.list_paid_orders_for_shop_dates(from_date, to_date),
         {:ok, {filename, binary}} <- SalesExport.build(orders, from_date, to_date) do
      conn
      |> put_resp_content_type(@xlsx_content_type)
      |> send_download({:binary, binary},
        filename: filename,
        content_type: @xlsx_content_type
      )
    else
      false ->
        conn
        |> put_flash(:error, "You don’t have permission to export sales reports.")
        |> redirect(to: ~p"/staff")

      {:error, :invalid_date} ->
        fail(conn, "Enter a valid Date From and Date To.")

      {:error, :invalid_range} ->
        fail(conn, "Date From must be on or before Date To.")

      {:error, :range_too_large} ->
        fail(
          conn,
          "Choose a date range of #{Orders.max_sales_export_shop_days()} days or fewer."
        )

      {:error, :too_many_orders} ->
        fail(conn, "Too many orders in this range. Choose a shorter date range.")

      {:error, reason} ->
        fail(conn, "Unable to export sales (#{inspect(reason)}). Try again.")
    end
  end

  defp fail(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/staff/reports")
  end

  defp parse_date(nil), do: {:error, :invalid_date}
  defp parse_date(""), do: {:error, :invalid_date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(_), do: {:error, :invalid_date}
end

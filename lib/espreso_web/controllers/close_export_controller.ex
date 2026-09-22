defmodule EspresoWeb.CloseExportController do
  @moduledoc """
  Authenticated day-close Excel and PDF download for Owner/Manager.
  """
  use EspresoWeb, :controller

  alias Espreso.Accounts.Authorization
  alias Espreso.Orders
  alias Espreso.Reports.CloseExport

  @xlsx_content_type "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  @pdf_content_type "application/pdf"

  def xlsx(conn, params), do: download(conn, params, :xlsx)
  def pdf(conn, params), do: download(conn, params, :pdf)

  defp download(conn, params, kind) do
    user = conn.assigns.current_user

    with true <- Authorization.can?(user, :reports),
         {:ok, from_date} <- parse_date(params["from"]),
         {:ok, to_date} <- parse_date(params["to"]),
         {:ok, pack} <- CloseExport.pack(from_date, to_date),
         {:ok, {filename, binary}} <- build(kind, pack) do
      content_type = if(kind == :pdf, do: @pdf_content_type, else: @xlsx_content_type)

      conn
      |> put_resp_content_type(content_type)
      |> send_download({:binary, binary}, filename: filename, content_type: content_type)
    else
      false ->
        conn
        |> put_flash(:error, "You don’t have permission to export reports.")
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

      {:error, reason} ->
        fail(conn, "Unable to export close report (#{inspect(reason)}). Try again.")
    end
  end

  defp build(:xlsx, pack), do: CloseExport.build_xlsx(pack)
  defp build(:pdf, pack), do: CloseExport.build_pdf(pack)

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

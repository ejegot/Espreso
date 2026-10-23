defmodule EspresoWeb.BusinessGcashQrController do
  use EspresoWeb, :controller

  alias Espreso.BusinessSettings
  alias Espreso.Tenancy

  def show(conn, params) do
    # Support optional tenant/branch params for multi-tenant/branch isolation.
    # Falls back to default Lilac context if no params or invalid slugs.
    case params do
      %{"tenant_slug" => tenant_slug, "branch_slug" => branch_slug}
      when is_binary(tenant_slug) and is_binary(branch_slug) ->
        Tenancy.put_guest_tenant_branch(tenant_slug, branch_slug)

      %{"tenant_slug" => tenant_slug} when is_binary(tenant_slug) ->
        Tenancy.put_guest_tenant(tenant_slug)

      %{"branch_slug" => branch_slug} when is_binary(branch_slug) ->
        Tenancy.put_guest_branch(branch_slug)

      _ ->
        Tenancy.put_lilac_context()
    end

    case BusinessSettings.get_gcash_qr() do
      nil ->
        send_resp(conn, :not_found, "")

      qr ->
        conn
        |> put_resp_content_type(qr.content_type)
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_resp(:ok, qr.data)
    end
  end
end

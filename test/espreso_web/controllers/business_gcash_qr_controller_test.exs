defmodule EspresoWeb.BusinessGcashQrControllerTest do
  use EspresoWeb.ConnCase

  alias Espreso.Accounts
  alias Espreso.BusinessSettings
  alias Espreso.Tenancy

  test "serves the uploaded GCash QR image", %{conn: conn} do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.gcashqr@test.local",
        password: "password123",
        role: "owner"
      })

    png = tiny_png()

    assert {:ok, qr} = BusinessSettings.save_gcash_qr_as(owner, png, "image/png")

    conn = get(conn, ~p"/media/business/gcash-qr")

    assert response(conn, 200) == png
    assert get_resp_header(conn, "content-type") |> List.first() =~ "image/png"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
    assert qr.data == png
  end

  test "returns 404 when no GCash QR image has been uploaded", %{conn: conn} do
    conn = get(conn, ~p"/media/business/gcash-qr")
    assert response(conn, 404)
  end

  test "serves branch-specific GCash QR via tenant and branch slug params", %{conn: conn} do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.branch.qr@test.local",
        password: "password123",
        role: "owner"
      })

    # Create a new branch
    {:ok, branch} =
      Tenancy.Branches.create_as(owner, %{name: "Branch for QR Test"})

    # Upload a QR to the default branch
    png_default = tiny_png()
    assert {:ok, _qr_default} = BusinessSettings.save_gcash_qr_as(owner, png_default, "image/png")

    # Upload a different QR to the new branch
    Tenancy.put_context(%{tenant_id: branch.tenant_id, branch_id: branch.id})
    png_branch = tiny_png() <> "extra"
    assert {:ok, _qr_branch} = BusinessSettings.save_gcash_qr_as(owner, png_branch, "image/png")

    # Reset to default context for HTTP requests
    Tenancy.put_lilac_context()

    # Test default branch access
    conn1 = get(conn, ~p"/media/business/gcash-qr")
    assert response(conn1, 200) == png_default

    # Test access via branch slug only
    conn2 = get(conn, "/b/#{branch.slug}/media/business/gcash-qr")
    assert response(conn2, 200) == png_branch

    # Test access via full tenant/branch params
    tenant = Tenancy.get_tenant(branch.tenant_id)
    conn3 = get(conn, "/media/business/gcash-qr/t/#{tenant.slug}/b/#{branch.slug}")
    assert response(conn3, 200) == png_branch
  end

  test "invalid branch/tenant slugs fall back to default Lilac context", %{conn: conn} do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.invalid.slug@test.local",
        password: "password123",
        role: "owner"
      })

    png = tiny_png()
    assert {:ok, _} = BusinessSettings.save_gcash_qr_as(owner, png, "image/png")

    # Non-existent branch slug should fall back to Lilac and return the Lilac QR
    conn1 = get(conn, "/b/nonexistent/media/business/gcash-qr")
    assert response(conn1, 200) == png

    # Non-existent tenant slug should fall back to Lilac and return the Lilac QR
    conn2 = get(conn, "/media/business/gcash-qr/t/nonexistent")
    assert response(conn2, 200) == png

    # Non-existent tenant + branch should fall back to Lilac and return the Lilac QR
    conn3 = get(conn, "/media/business/gcash-qr/t/nonexistent/b/nonexistent")
    assert response(conn3, 200) == png
  end

  test "different image formats work with branch isolation", %{conn: conn} do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.formats@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, branch} =
      Tenancy.Branches.create_as(owner, %{name: "Format Test Branch"})

    # Upload PNG to default
    png = tiny_png()
    assert {:ok, qr1} = BusinessSettings.save_gcash_qr_as(owner, png, "image/png")
    assert qr1.content_type == "image/png"

    # Upload JPEG to branch
    jpeg = tiny_jpeg()
    Tenancy.put_context(%{tenant_id: branch.tenant_id, branch_id: branch.id})
    assert {:ok, qr2} = BusinessSettings.save_gcash_qr_as(owner, jpeg, "image/jpeg")
    assert qr2.content_type == "image/jpeg"

    # Verify correct format is returned for each
    Tenancy.put_lilac_context()
    conn1 = get(conn, ~p"/media/business/gcash-qr")
    assert get_resp_header(conn1, "content-type") |> List.first() =~ "image/png"
    assert response(conn1, 200) == png

    tenant = Tenancy.get_tenant(branch.tenant_id)
    conn2 = get(conn, "/media/business/gcash-qr/t/#{tenant.slug}/b/#{branch.slug}")
    assert get_resp_header(conn2, "content-type") |> List.first() =~ "image/jpeg"
    assert response(conn2, 200) == jpeg
  end

  test "rejects corrupted image files with valid signatures", %{conn: _conn} do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.corrupt@test.local",
        password: "password123",
        role: "owner"
      })

    # Valid PNG signature but corrupted content
    corrupted_png =
      <<137, 80, 78, 71, 13, 10, 26, 10>> <> String.duplicate("corrupted data", 10)

    assert {:error, :invalid_photo} =
             BusinessSettings.save_gcash_qr_as(owner, corrupted_png, "image/png")
  end

  test "rejects images with mismatched content-type", %{conn: _conn} do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.mismatch@test.local",
        password: "password123",
        role: "owner"
      })

    png = tiny_png()
    jpeg = tiny_jpeg()

    # Declare PNG as JPEG
    assert {:error, :invalid_photo} =
             BusinessSettings.save_gcash_qr_as(owner, png, "image/jpeg")

    # Declare JPEG as PNG
    assert {:error, :invalid_photo} =
             BusinessSettings.save_gcash_qr_as(owner, jpeg, "image/png")
  end

  defp tiny_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
  end

  defp tiny_jpeg do
    # Minimal valid JPEG
    Base.decode64!(
      "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8VAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k="
    )
  end
end

defmodule EspresoWeb.PwaManifestTest do
  use EspresoWeb.ConnCase

  @manifest_path Path.expand("../../priv/static/elilai-kafe.webmanifest", __DIR__)
  @logo_path Path.expand("../../priv/static/images/elilai-kafe/elilai-kafe-logo.jpg", __DIR__)
  @icon_192_path Path.expand("../../priv/static/images/elilai-kafe/app-icon-192.png", __DIR__)
  @icon_512_path Path.expand("../../priv/static/images/elilai-kafe/app-icon-512.png", __DIR__)
  @apple_icon_path Path.expand(
                     "../../priv/static/images/elilai-kafe/apple-touch-icon.png",
                     __DIR__
                   )

  test "employee manifest contains identity colors and official icons" do
    manifest =
      @manifest_path
      |> File.read!()
      |> Jason.decode!()

    assert manifest["name"] == "ELIlai Kafe"
    assert manifest["short_name"] == "ELIlai"
    assert manifest["start_url"] == "/login"
    assert manifest["scope"] == "/"
    assert manifest["display"] == "standalone"
    assert manifest["background_color"] == "#F4EFE3"
    assert manifest["theme_color"] == "#394331"

    icons = Map.fetch!(manifest, "icons")

    assert Enum.any?(icons, fn icon ->
             icon["src"] == "/images/elilai-kafe/app-icon-192.png" and
               icon["sizes"] == "192x192"
           end)

    assert Enum.any?(icons, fn icon ->
             icon["src"] == "/images/elilai-kafe/app-icon-512.png" and
               icon["sizes"] == "512x512"
           end)
  end

  test "official logo and derived icons exist on disk", do: assert_asset_files!()

  test "official logo and derived icons are served", %{conn: conn} do
    assert_asset_files!()

    for path <- [
          "/images/elilai-kafe/elilai-kafe-logo.jpg",
          "/images/elilai-kafe/app-icon-192.png",
          "/images/elilai-kafe/app-icon-512.png",
          "/images/elilai-kafe/apple-touch-icon.png"
        ] do
      response = get(conn, path)
      assert response(response, 200)
    end
  end

  test "manifest is served as a static JSON resource", %{conn: conn} do
    conn = get(conn, "/elilai-kafe.webmanifest")

    assert get_resp_header(conn, "content-type") == ["application/manifest+json"]

    body = Jason.decode!(response(conn, 200))

    assert body["name"] == "ELIlai Kafe"
    assert body["start_url"] == "/login"
    assert body["scope"] == "/"
    assert body["display"] == "standalone"
    assert body["theme_color"] == "#394331"
    assert body["background_color"] == "#F4EFE3"
    assert is_list(body["icons"])
  end

  defp assert_asset_files! do
    assert File.exists?(@logo_path)
    assert File.exists?(@icon_192_path)
    assert File.exists?(@icon_512_path)
    assert File.exists?(@apple_icon_path)
  end
end

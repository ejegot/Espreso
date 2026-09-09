defmodule EspresoWeb.PwaManifestTest do
  use EspresoWeb.ConnCase

  @manifest_path Path.expand("../../priv/static/elilai-kafe.webmanifest", __DIR__)

  test "employee manifest contains the install identity and launch boundary" do
    manifest =
      @manifest_path
      |> File.read!()
      |> Jason.decode!()

    assert manifest["name"] == "ELIlai Kafe"
    assert manifest["short_name"] == "ELIlai"
    assert manifest["start_url"] == "/login"
    assert manifest["scope"] == "/"
    assert manifest["display"] == "standalone"
    assert manifest["background_color"] == "#FAF7F4"
    assert manifest["theme_color"] == "#382010"

    refute Map.has_key?(manifest, "icons")
  end

  test "manifest is served as a static JSON resource", %{conn: conn} do
    conn = get(conn, "/elilai-kafe.webmanifest")

    assert get_resp_header(conn, "content-type") == ["application/manifest+json"]

    assert response(conn, 200)
           |> Jason.decode!()
           |> Map.take(["name", "start_url", "scope", "display"]) == %{
             "name" => "ELIlai Kafe",
             "start_url" => "/login",
             "scope" => "/",
             "display" => "standalone"
           }
  end
end

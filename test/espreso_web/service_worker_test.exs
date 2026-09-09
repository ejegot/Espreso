defmodule EspresoWeb.ServiceWorkerTest do
  use EspresoWeb.ConnCase

  @customer_root_path Path.expand(
                        "../../lib/espreso_web/components/layouts/root.html.heex",
                        __DIR__
                      )
  @employee_root_path Path.expand(
                        "../../lib/espreso_web/components/layouts/employee_root.html.heex",
                        __DIR__
                      )
  @service_worker_path Path.expand("../../priv/static/sw.js", __DIR__)
  @app_js_path Path.expand("../../assets/js/app.js", __DIR__)

  test "service worker file exists and is served as static javascript", %{conn: conn} do
    assert File.exists?(@service_worker_path)

    conn = get(conn, "/sw.js")

    assert response(conn, 200) =~ "const STATIC_CACHE ="
    assert get_resp_header(conn, "content-type") |> Enum.any?(&String.contains?(&1, "javascript"))
  end

  test "employee app registers the service worker from shared javascript only when employee root is active" do
    source = File.read!(@app_js_path)
    employee_root = File.read!(@employee_root_path)
    customer_root = File.read!(@customer_root_path)

    assert source =~ ~S|if (!("serviceWorker" in navigator)) return|
    assert source =~ ~S|root?.dataset.application !== "elilai-kafe-employee"|
    assert source =~ ~S|navigator.serviceWorker.register("/sw.js")|
    assert employee_root =~ ~S|data-application="elilai-kafe-employee"|
    refute customer_root =~ "elilai-kafe-employee"
    refute customer_root =~ "sw.js"
  end

  test "service worker contract is limited to the static allowlist" do
    source = File.read!(@service_worker_path)

    assert source =~ "const STATIC_CACHE = \"elilai-static-v1\""
    assert source =~ "const ALLOWED_PREFIXES = [\"/assets/\", \"/fonts/\"]"
    assert source =~ "\"/images/elilai-kafe/elilai-kafe-logo.jpg\""
    assert source =~ "\"/images/elilai-kafe/app-icon-192.png\""
    assert source =~ "\"/images/elilai-kafe/app-icon-512.png\""
    assert source =~ "\"/images/elilai-kafe/apple-touch-icon.png\""

    refute source =~ ~S|path.startsWith("/images/")|
    refute source =~ "\"/menu\""
    refute source =~ "\"/order/\""
    refute source =~ "\"/login\""
    refute source =~ "\"/staff\""
    refute source =~ "\"/orders\""
    refute source =~ "\"/pos\""
    refute source =~ "\"/dashboard\""
    refute source =~ "\"/about\""
    refute source =~ "\"/contact\""
    assert source =~ "if (path === \"/elilai-kafe.webmanifest\") return false"
  end

  test "service worker explicitly excludes navigation liveview api and mutation requests" do
    source = File.read!(@service_worker_path)

    assert source =~ ~S|if (request.method !== "GET") return false|
    assert source =~ ~S|if (request.mode === "navigate") return false|
    assert source =~ ~S|if (path.startsWith("/api/")) return false|
    assert source =~ "if (path === \"/live\" || path.startsWith(\"/live/\")) return false"
    assert source =~ "if (path === \"/socket\" || path.startsWith(\"/socket/\")) return false"
  end

  test "service worker removes old cache versions during activation" do
    source = File.read!(@service_worker_path)

    assert source =~ "const STATIC_CACHE_PREFIX = \"elilai-static-\""
    assert source =~ ".filter(key => key.startsWith(STATIC_CACHE_PREFIX) && key !== STATIC_CACHE)"
    assert source =~ ".map(key => caches.delete(key))"
  end
end

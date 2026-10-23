defmodule EspresoWeb.LiveViewOriginTest do
  @moduledoc """
  Tests that the allowed_origins configuration built in config/runtime.exs
  produces valid origin strings that Phoenix.Socket.Transport.parse_origin/1
  can accept without raising.

  This does NOT test the actual WebSocket connection (that happens in LiveView
  functional tests), but verifies that our configuration produces origin strings
  that are valid for Phoenix 1.7.24's strict URI.parse-based validation.

  Invalid origins would raise ArgumentError at app startup:
    "invalid :check_origin option: ... Expected an origin with a host ..."
  """
  use ExUnit.Case, async: false

  describe "allowed_origins configuration validity" do
    test "built PHX_HOST with https:// scheme is valid for Phoenix" do
      # Simulate what config/runtime.exs does
      phx_host = "134-209-110-46.nip.io"
      System.put_env("ALLOWED_ORIGINS", "")

      allowed_origins = build_allowed_origins(phx_host)

      # Each origin must be parseable by URI.parse without nil host
      assert_all_valid_for_phoenix(allowed_origins)
      # Must include at least the PHX_HOST with https scheme
      assert Enum.any?(allowed_origins, &String.starts_with?(&1, "https://"))
    end

    test "PHX_HOST + comma-separated ALLOWED_ORIGINS are all valid" do
      phx_host = "134-209-110-46.nip.io"
      System.put_env("ALLOWED_ORIGINS", "https://elilaikafe.devs.surf,https://other.com")

      allowed_origins = build_allowed_origins(phx_host)

      assert_all_valid_for_phoenix(allowed_origins)
      # Verify both domains are included
      assert "https://134-209-110-46.nip.io" in allowed_origins
      assert "https://elilaikafe.devs.surf" in allowed_origins
      assert "https://other.com" in allowed_origins
    end

    test "protocol-relative origins with ports are valid" do
      phx_host = "localhost"
      System.put_env("ALLOWED_ORIGINS", "//example.com:8443,//another.com")

      allowed_origins = build_allowed_origins(phx_host)

      assert_all_valid_for_phoenix(allowed_origins)
      assert "//example.com:8443" in allowed_origins
      assert "//another.com" in allowed_origins
    end

    test "whitespace-trimmed origins remain valid" do
      phx_host = "localhost"
      System.put_env("ALLOWED_ORIGINS", "  https://example.com  , https://another.com  ")

      allowed_origins = build_allowed_origins(phx_host)

      assert_all_valid_for_phoenix(allowed_origins)
      assert "https://example.com" in allowed_origins
      assert "https://another.com" in allowed_origins
    end

    test "empty ALLOWED_ORIGINS produces only PHX_HOST" do
      phx_host = "example.com"

      for env_val <- [nil, "", "   "] do
        System.put_env("ALLOWED_ORIGINS", env_val || "")
        allowed_origins = build_allowed_origins(phx_host)

        assert_all_valid_for_phoenix(allowed_origins)
        assert length(allowed_origins) >= 1
        assert "https://example.com" in allowed_origins
      end
    end

    test "bare domains without scheme are invalid and would be rejected by Phoenix at startup" do
      # This test documents the constraint: users must provide scheme
      invalid_origins = ["example.com", "example.com:443", "domain.com"]

      Enum.each(invalid_origins, fn origin ->
        # URI.parse will NOT extract host from these formats
        parsed = URI.parse(origin)

        assert is_nil(parsed.host),
               "#{origin} should not have a host after URI.parse (Phoenix would reject it)"
      end)
    end

    test "valid origin formats that Phoenix accepts" do
      valid_origins = [
        "https://example.com",
        "//another.com:888",
        "//*.wildcard.com",
        "https://example.com:443"
      ]

      Enum.each(valid_origins, fn origin ->
        # These should parse and extract host
        parsed = URI.parse(origin)

        assert not is_nil(parsed.host),
               "#{origin} should have a host after URI.parse"
      end)
    end
  end

  # Helper: mimics the origin-building logic from config/runtime.exs
  defp build_allowed_origins(host) do
    ["https://#{host}"] ++
      (System.get_env("ALLOWED_ORIGINS")
       |> then(fn val -> if is_binary(val) and byte_size(val) > 0, do: val, else: "" end)
       |> String.split(",")
       |> Enum.map(&String.trim/1)
       |> Enum.reject(&(&1 == "")))
  end

  # Helper: verify each origin string is valid according to Phoenix's parse_origin logic
  # This mimics what Phoenix.Socket.Transport.parse_origin/1 does at app startup
  defp assert_all_valid_for_phoenix(origins) do
    Enum.each(origins, fn origin ->
      case URI.parse(origin) do
        %{host: nil} ->
          raise "Origin #{inspect(origin)} is invalid for Phoenix: host cannot be extracted by URI.parse/1"

        %{scheme: _scheme, port: _port, host: _host} ->
          # Valid - Phoenix can use this
          :ok
      end
    end)
  end
end

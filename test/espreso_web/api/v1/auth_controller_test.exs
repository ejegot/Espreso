defmodule EspresoWeb.Api.V1.AuthControllerTest do
  use EspresoWeb.ConnCase, async: true

  alias Espreso.Accounts

  test "POST /auth/email returns tokens for valid credentials", %{conn: conn} do
    user = register_staff!("Ana API", "ana.api@coffeespot.local", "barista")

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/email", %{email: user.email, password: "password123"})

    assert %{
             "access_token" => access,
             "refresh_token" => refresh,
             "user" => %{"id" => id, "role" => "barista"}
           } = json_response(conn, 200)

    assert id == user.id
    assert is_binary(access)
    assert is_binary(refresh)
  end

  test "POST /auth/email rejects invalid credentials", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/email", %{email: "nope@coffeespot.local", password: "bad"})

    assert json_response(conn, 401) == %{"error" => "invalid_credentials"}
  end

  test "POST /auth/pin returns tokens when pin is set", %{conn: conn} do
    user = register_staff!("Pin API", "pin.api@coffeespot.local", "barista")
    {:ok, _} = Accounts.set_pin(user, "4321")

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user.id, pin: "4321"})

    assert %{"access_token" => _, "refresh_token" => _, "user" => %{"id" => id}} =
             json_response(conn, 200)

    assert id == user.id
  end

  test "POST /auth/refresh returns a new access token", %{conn: conn} do
    user = register_staff!("Refresh API", "refresh.api@coffeespot.local", "barista")

    login =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/email", %{email: user.email, password: "password123"})

    %{"refresh_token" => refresh} = json_response(login, 200)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/refresh", %{refresh_token: refresh})

    assert %{"access_token" => access, "user" => %{"id" => id}} = json_response(conn, 200)
    assert id == user.id
    assert is_binary(access)
  end

  test "GET /staff/roster returns active staff without secrets", %{conn: conn} do
    active = register_staff!("Roster Active", "roster.active@coffeespot.local", "barista")
    inactive = register_staff!("Roster Inactive", "roster.inactive@coffeespot.local", "barista")
    {:ok, _} = Accounts.update_user(inactive, %{active: false})

    conn = get(conn, ~p"/api/v1/staff/roster")
    assert %{"staff" => staff} = json_response(conn, 200)

    ids = Enum.map(staff, & &1["id"])
    assert active.id in ids
    refute inactive.id in ids
    refute Enum.any?(staff, &Map.has_key?(&1, "email"))
  end
end

defmodule EspresoWeb.Api.V1.AuthControllerTest do
  use EspresoWeb.ConnCase, async: false

  alias Espreso.Accounts
  alias Espreso.Auth.PinAttemptLimiter

  setup do
    PinAttemptLimiter.reset!()
    :ok
  end

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

  test "POST /auth/pin rejects wrong pin with generic 401", %{conn: conn} do
    user = register_staff!("Pin Bad", "pin.bad@coffeespot.local", "barista")
    {:ok, _} = Accounts.set_pin(user, "4321")

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user.id, pin: "9999"})

    assert json_response(conn, 401) == %{"error" => "invalid_credentials"}
  end

  test "POST /auth/pin returns 429 after repeated failures", %{conn: _conn} do
    user = register_staff!("Pin Limit", "pin.limit@coffeespot.local", "barista")
    {:ok, _} = Accounts.set_pin(user, "4321")

    Enum.each(1..5, fn _ ->
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/auth/pin", %{user_id: user.id, pin: "0000"})

      assert json_response(conn, 401) == %{"error" => "invalid_credentials"}
    end)

    limited =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user.id, pin: "0000"})

    assert json_response(limited, 429) == %{"error" => "too_many_attempts"}
  end

  test "POST /auth/pin success resets user throttle and another user remains free", %{conn: _conn} do
    user_a = register_staff!("Pin A", "pin.a@coffeespot.local", "barista")
    user_b = register_staff!("Pin B", "pin.b@coffeespot.local", "manager")
    {:ok, _} = Accounts.set_pin(user_a, "4321")
    {:ok, _} = Accounts.set_pin(user_b, "5678")

    Enum.each(1..4, fn _ ->
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user_a.id, pin: "0000"})
    end)

    ok =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user_a.id, pin: "4321"})

    assert %{"access_token" => _, "user" => %{"id" => id}} = json_response(ok, 200)
    assert id == user_a.id

    Enum.each(1..5, fn _ ->
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user_a.id, pin: "0000"})
    end)

    limited =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user_a.id, pin: "1111"})

    assert json_response(limited, 429) == %{"error" => "too_many_attempts"}

    other =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user_b.id, pin: "5678"})

    assert %{"user" => %{"id" => other_id, "role" => "manager"}} = json_response(other, 200)
    assert other_id == user_b.id
  end

  test "browser and API pin auth share limiter state", %{conn: conn} do
    user = register_staff!("Pin Shared", "pin.shared@coffeespot.local", "barista")
    {:ok, _} = Accounts.set_pin(user, "4321")

    Enum.each(1..5, fn _ ->
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => user.id,
        "pin" => "0000"
      })
    end)

    limited =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/pin", %{user_id: user.id, pin: "0000"})

    assert json_response(limited, 429) == %{"error" => "too_many_attempts"}
  end

  test "POST /auth/pin inactive and missing pin stay generic 401", %{conn: _conn} do
    active = register_staff!("Pin Active", "pin.active2@coffeespot.local", "barista")
    inactive = register_staff!("Pin Inactive", "pin.inactive2@coffeespot.local", "barista")
    {:ok, _} = Accounts.set_pin(active, "4321")
    {:ok, _} = Accounts.set_pin(inactive, "4321")
    {:ok, _} = Accounts.update_user(inactive, %{active: false})

    no_pin = register_staff!("Pin None", "pin.none@coffeespot.local", "barista")

    for {user, pin} <- [{inactive, "4321"}, {no_pin, "4321"}, {active, "9999"}] do
      resp =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/auth/pin", %{user_id: user.id, pin: pin})

      assert json_response(resp, 401) == %{"error" => "invalid_credentials"}
    end
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

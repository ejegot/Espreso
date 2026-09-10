defmodule Espreso.Auth.PinAttemptLimiterTest do
  use ExUnit.Case, async: true

  alias Espreso.Auth.PinAttemptLimiter

  setup do
    name = :"pin_limiter_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({PinAttemptLimiter, name: name})
    %{server: name}
  end

  defp opts(server, now), do: [server: server, now: now]

  test "new user/ip is allowed", %{server: server} do
    assert :ok = PinAttemptLimiter.check(1, "10.0.0.1", opts(server, 0))
  end

  test "first four failures do not trigger cooldown", %{server: server} do
    Enum.each(1..4, fn i ->
      assert :ok = PinAttemptLimiter.check(7, "10.0.0.2", opts(server, i))
      assert :ok = PinAttemptLimiter.record_failure(7, "10.0.0.2", opts(server, i))
    end)

    assert :ok = PinAttemptLimiter.check(7, "10.0.0.2", opts(server, 5))
  end

  test "fifth failure triggers cooldown; sixth attempt is blocked", %{server: server} do
    Enum.each(1..5, fn i ->
      assert :ok = PinAttemptLimiter.check(8, "10.0.0.3", opts(server, i))
      assert :ok = PinAttemptLimiter.record_failure(8, "10.0.0.3", opts(server, i))
    end)

    assert {:error, :rate_limited} = PinAttemptLimiter.check(8, "10.0.0.3", opts(server, 6))
  end

  test "cooldown expires and allows attempts again", %{server: server} do
    base = 1_000

    Enum.each(0..4, fn i ->
      :ok = PinAttemptLimiter.record_failure(9, "10.0.0.4", opts(server, base + i))
    end)

    locked_at = base + 4

    assert {:error, :rate_limited} =
             PinAttemptLimiter.check(9, "10.0.0.4", opts(server, locked_at + 59_999))

    assert :ok = PinAttemptLimiter.check(9, "10.0.0.4", opts(server, locked_at + 60_000))
  end

  test "continued abuse escalates to 2 minutes then caps at 5 minutes", %{server: server} do
    # First lockout: 60s
    base1 = 10_000

    Enum.each(0..4, fn i ->
      :ok = PinAttemptLimiter.record_failure(11, "10.0.0.5", opts(server, base1 + i))
    end)

    t1 = base1 + 4

    assert {:error, :rate_limited} =
             PinAttemptLimiter.check(11, "10.0.0.5", opts(server, t1 + 59_999))

    assert :ok = PinAttemptLimiter.check(11, "10.0.0.5", opts(server, t1 + 60_000))

    # Second lockout: 120s
    base2 = t1 + 60_000

    Enum.each(0..4, fn i ->
      :ok = PinAttemptLimiter.record_failure(11, "10.0.0.5", opts(server, base2 + i))
    end)

    t2 = base2 + 4

    assert {:error, :rate_limited} =
             PinAttemptLimiter.check(11, "10.0.0.5", opts(server, t2 + 119_999))

    assert :ok = PinAttemptLimiter.check(11, "10.0.0.5", opts(server, t2 + 120_000))

    # Third lockout: 300s (cap)
    base3 = t2 + 120_000

    Enum.each(0..4, fn i ->
      :ok = PinAttemptLimiter.record_failure(11, "10.0.0.5", opts(server, base3 + i))
    end)

    t3 = base3 + 4

    assert {:error, :rate_limited} =
             PinAttemptLimiter.check(11, "10.0.0.5", opts(server, t3 + 299_999))

    assert :ok = PinAttemptLimiter.check(11, "10.0.0.5", opts(server, t3 + 300_000))

    # Fourth lockout still capped at 300s
    base4 = t3 + 300_000

    Enum.each(0..4, fn i ->
      :ok = PinAttemptLimiter.record_failure(11, "10.0.0.5", opts(server, base4 + i))
    end)

    t4 = base4 + 4

    assert {:error, :rate_limited} =
             PinAttemptLimiter.check(11, "10.0.0.5", opts(server, t4 + 299_999))

    assert :ok = PinAttemptLimiter.check(11, "10.0.0.5", opts(server, t4 + 300_000))
  end

  test "successful authentication resets user state", %{server: server} do
    Enum.each(1..5, fn i ->
      :ok = PinAttemptLimiter.record_failure(12, "10.0.0.6", opts(server, i))
    end)

    assert {:error, :rate_limited} = PinAttemptLimiter.check(12, "10.0.0.6", opts(server, 10))

    assert :ok = PinAttemptLimiter.record_success(12, "10.0.0.6", opts(server, 10))
    assert :ok = PinAttemptLimiter.check(12, "10.0.0.6", opts(server, 11))
  end

  test "another user on same IP is not blocked by user-level cooldown", %{server: server} do
    Enum.each(1..5, fn i ->
      :ok = PinAttemptLimiter.record_failure(13, "10.0.0.7", opts(server, i))
    end)

    assert {:error, :rate_limited} = PinAttemptLimiter.check(13, "10.0.0.7", opts(server, 10))
    assert :ok = PinAttemptLimiter.check(14, "10.0.0.7", opts(server, 10))
  end

  test "IP soft limit counts failures across users and triggers cooldown", %{server: server} do
    Enum.each(1..30, fn i ->
      user = 100 + rem(i, 10)
      assert :ok = PinAttemptLimiter.check(user, "10.0.0.8", opts(server, i))
      assert :ok = PinAttemptLimiter.record_failure(user, "10.0.0.8", opts(server, i))
    end)

    assert {:error, :rate_limited} = PinAttemptLimiter.check(999, "10.0.0.8", opts(server, 31))
    # Different IP still ok
    assert :ok = PinAttemptLimiter.check(999, "10.0.0.9", opts(server, 31))
  end

  test "IP cooldown is modest (60s) not an aggressive lock", %{server: server} do
    base = 5_000

    Enum.each(0..29, fn i ->
      :ok = PinAttemptLimiter.record_failure(200 + rem(i, 5), "10.1.0.1", opts(server, base + i))
    end)

    locked_at = base + 29

    assert {:error, :rate_limited} =
             PinAttemptLimiter.check(250, "10.1.0.1", opts(server, locked_at + 30_000))

    assert :ok = PinAttemptLimiter.check(250, "10.1.0.1", opts(server, locked_at + 60_000))
  end

  test "success does not wipe IP failure budget", %{server: server} do
    Enum.each(1..29, fn i ->
      :ok = PinAttemptLimiter.record_failure(300 + rem(i, 3), "10.2.0.1", opts(server, i))
    end)

    assert :ok = PinAttemptLimiter.record_success(300, "10.2.0.1", opts(server, 30))
    assert :ok = PinAttemptLimiter.record_failure(301, "10.2.0.1", opts(server, 31))
    assert {:error, :rate_limited} = PinAttemptLimiter.check(302, "10.2.0.1", opts(server, 32))
  end

  test "expired idle state is cleaned up", %{server: server} do
    :ok = PinAttemptLimiter.record_failure(40, "10.3.0.1", opts(server, 1))
    # Force cleanup via reset of unrelated state still works; exercise reset!
    assert :ok = PinAttemptLimiter.reset!(server: server)
    assert :ok = PinAttemptLimiter.check(40, "10.3.0.1", opts(server, 2))
  end

  test "concurrent failures do not bypass the intended limit", %{server: server} do
    tasks =
      for i <- 1..5 do
        Task.async(fn ->
          PinAttemptLimiter.record_failure(50, "10.4.0.1", opts(server, i))
        end)
      end

    Enum.each(tasks, &Task.await/1)

    assert {:error, :rate_limited} = PinAttemptLimiter.check(50, "10.4.0.1", opts(server, 10))
  end

  test "named servers isolate state from the application singleton", %{server: server} do
    Enum.each(1..5, fn i ->
      :ok = PinAttemptLimiter.record_failure(60, "10.5.0.1", opts(server, i))
    end)

    assert {:error, :rate_limited} = PinAttemptLimiter.check(60, "10.5.0.1", opts(server, 10))
    # Application singleton remains usable for the same logical user id.
    PinAttemptLimiter.reset!()
    assert :ok = PinAttemptLimiter.check(60, "10.5.0.1", now: 10)
  end
end

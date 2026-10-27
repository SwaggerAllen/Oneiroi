defmodule Oneiroi.Gaia.AccountsTest do
  @moduledoc "Identity through its exports, against the real store: the projectors write from their own processes, so the sandbox is shared."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Throttle
  alias Oneiroi.Platform.Clock
  alias Oneiroi.Platform.Clock.Fake

  test "login verifies the password, opens a session, and the session resolves to the principal" do
    %{id: id, email: email} = Fixtures.account!()
    assert {:ok, raw, principal} = Gaia.login(email, Fixtures.password(), nil)
    assert principal.account_id == id
    assert {:ok, %{account_id: ^id, via: :session}} = Gaia.authenticate_session(raw)
    assert :ok = Gaia.logout(raw)
    assert :error = Gaia.authenticate_session(raw)
  end

  test "a wrong password, an unknown email and a case-different email all answer the same way" do
    %{email: email} = Fixtures.account!()
    assert {:error, :gaia_invalid_credentials} = Gaia.login(email, "wrong", nil)

    assert {:error, :gaia_invalid_credentials} =
             Gaia.login("nobody@example.org", Fixtures.password(), nil)

    assert {:ok, _raw, _p} = Gaia.login(String.upcase(email), Fixtures.password(), nil)
  end

  test "a session expires at its ttl" do
    %{email: email} = Fixtures.account!()
    assert {:ok, raw, _p} = Gaia.login(email, Fixtures.password(), nil)
    Fake.advance(31 * 24 * 3600)
    assert :error = Gaia.authenticate_session(raw)
  end

  test "an enrolled second factor is required, and a valid code passes" do
    %{id: id, email: email} = Fixtures.account!()

    assert {:ok, %{secret: secret, uri: uri}} =
             Gaia.enroll_second_factor(id, Actor.new(:steward, id))

    assert uri =~ "otpauth://totp/Oneiroi:"

    assert {:error, :gaia_second_factor_required} =
             Gaia.login(email, Fixtures.password(), nil)

    code =
      secret
      |> Base.decode32!(padding: false)
      |> NimbleTOTP.verification_code(time: DateTime.to_unix(Clock.now()))

    assert {:ok, _raw, _p} = Gaia.login(email, Fixtures.password(), code)

    assert {:error, :gaia_invalid_credentials} =
             Gaia.login(email, Fixtures.password(), "000000")
  end

  test "a token resolves to its account until revoked" do
    %{id: id} = Fixtures.account!()
    assert {:ok, raw, hash} = Gaia.issue_token(id, "script", Actor.new(:steward, id))
    assert {:ok, %{account_id: ^id, via: :token}} = Gaia.authenticate_token(raw)
    assert :ok = Gaia.revoke_token(id, hash, Actor.new(:steward, id))
    assert :error = Gaia.authenticate_token(raw)
  end

  test "the throttle doubles from the base and caps at five seconds" do
    assert Throttle.delay(0, 200) == 0
    assert Throttle.delay(1, 200) == 200
    assert Throttle.delay(2, 200) == 400
    assert Throttle.delay(5, 200) == 3200
    assert Throttle.delay(6, 200) == 5000
    assert Throttle.failed("someone@example.org", 0) == 0
    assert Throttle.failed("someone@example.org", 0) == 0
    assert :ok = Throttle.clear("someone@example.org")
  end
end

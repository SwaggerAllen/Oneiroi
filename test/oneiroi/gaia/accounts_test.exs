defmodule Oneiroi.Gaia.AccountsTest do
  @moduledoc "Identity through its exports, against the real store: the projectors write from their own processes, so the sandbox is shared."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Clock.Fake
  alias Oneiroi.Config.Secret
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Throttle
  alias Oneiroi.Scope

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

    assert {:error,
            %Gaia.Error{kind: :gaia_invalid_credentials, site: :gaia_login_credentials_invalid}} =
             Gaia.login(email, "wrong", nil)

    assert {:error,
            %Gaia.Error{kind: :gaia_invalid_credentials, site: :gaia_login_credentials_invalid}} =
             Gaia.login("nobody@example.org", Fixtures.password(), nil)

    assert {:ok, _raw, _p} = Gaia.login(String.upcase(email), Fixtures.password(), nil)
  end

  # The steward's login answered 401 invalid credentials during a
  # deploy's overlap: the session's dispatch had timed out on a projector.
  # A zero consistency timeout is that timeout, made on purpose.
  test "credentials that verify and a session the store cannot open answer unavailable, and count nothing" do
    %{email: email} = Fixtures.account!()

    assert {:error,
            %Gaia.Error{kind: :gaia_invalid_credentials, site: :gaia_login_credentials_invalid}} =
             Gaia.login(email, "wrong", nil)

    # Unset in test config: restoring is deleting, since a nil timeout is
    # an error and not the default.
    restore = fn -> Application.delete_env(:commanded, :dispatch_consistency_timeout) end
    on_exit(restore)
    Application.put_env(:commanded, :dispatch_consistency_timeout, 0)

    assert {:error,
            %Gaia.Error{kind: :gaia_session_unavailable, site: :gaia_login_session_not_opened}} =
             Gaia.login(email, Fixtures.password(), nil)

    restore.()

    # The verified password cleared the wrong one, and the unavailable
    # answer added nothing: the next failure is the first.
    assert Throttle.failed(email, 200) == 200

    # A retry opens one; its dispatch waits on the projector, which so
    # takes the timed-out session's event too before the test ends.
    assert {:ok, _raw, _p} = Gaia.login(email, Fixtures.password(), nil)
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
             Gaia.enroll_second_factor(id, Actor.new(:witness, id))

    assert uri =~ "otpauth://totp/Oneiroi:"

    assert {:error,
            %Gaia.Error{kind: :gaia_second_factor_required, site: :gaia_login_code_missing}} =
             Gaia.login(email, Fixtures.password(), nil)

    code =
      secret
      |> Base.decode32!(padding: false)
      |> NimbleTOTP.verification_code(time: DateTime.to_unix(Clock.now()))

    assert {:ok, _raw, _p} = Gaia.login(email, Fixtures.password(), code)

    assert {:error,
            %Gaia.Error{kind: :gaia_invalid_credentials, site: :gaia_login_credentials_invalid}} =
             Gaia.login(email, Fixtures.password(), "000000")
  end

  test "a token resolves to its account until revoked" do
    %{id: id} = Fixtures.account!()
    assert {:ok, raw, hash} = Gaia.issue_token(id, "script", Actor.new(:witness, id))
    assert {:ok, %{account_id: ^id, via: :token}} = Gaia.authenticate_token(raw)
    assert :ok = Gaia.revoke_token(id, hash, Actor.new(:witness, id))
    assert :error = Gaia.authenticate_token(raw)
  end

  test "the witness's key is stored encrypted, read back wrapped, rotated by storing again, and revoked" do
    %{id: id} = Fixtures.account!()
    actor = Actor.new(:witness, id)
    assert %{present: false, stored_at: nil} = Gaia.key_status(id)

    assert {:error, %Gaia.Error{kind: :gaia_no_key, site: :gaia_key_for_absent}} =
             Gaia.key_for(id)

    assert {:error, %Gaia.Error{kind: :gaia_key_required, site: :gaia_store_key_blank}} =
             Gaia.store_key(id, "   ", actor)

    assert :ok = Gaia.store_key(id, "sk-or-first", actor)
    assert %{present: true, stored_at: %DateTime{}} = Gaia.key_status(id)
    assert {:ok, secret} = Gaia.key_for(id)
    assert Secret.unwrap(secret) == "sk-or-first"
    refute inspect(secret) =~ "sk-or-first"

    # The row holds the vault's ciphertext, never the key.
    row = Scope.account(id, fn -> Gaia.Store.account(id) end)
    refute row.key_ciphertext =~ "sk-or-first"

    assert :ok = Gaia.store_key(id, "sk-or-second", actor)
    assert {:ok, secret} = Gaia.key_for(id)
    assert Secret.unwrap(secret) == "sk-or-second"

    assert :ok = Gaia.revoke_key(id, actor)

    assert {:error, %Gaia.Error{kind: :gaia_no_key, site: :gaia_key_for_absent}} =
             Gaia.key_for(id)

    assert {:error, %Gaia.Error{kind: :gaia_no_key, site: :gaia_account_revoke_key_absent}} =
             Gaia.revoke_key(id, actor)
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

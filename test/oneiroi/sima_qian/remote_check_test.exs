defmodule Oneiroi.SimaQian.RemoteCheckTest do
  @moduledoc """
  A backup remote, checked (sima-qian#65; the witness, 2026-11-21). Its
  shape first, for anyone who sets it: an email address in the field
  (Scarlett's, that morning) is refused, a clone URL or a local path is
  kept. Its host asked, for the witness's set: a token that cannot push
  is refused; a public repository is kept and warned of, in the answer
  and in needs_you, never refused; and the nightly backup asks again, so
  one made public after the set is warned of too, while the backup goes
  on.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Remote
  alias Oneiroi.SimaQian.RemoteCheck.Fake

  setup do
    on_exit(&Fake.clear/0)
    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    {:ok, id: resident.id, andrew: Actor.new(:witness, account.id)}
  end

  defp warned(id), do: Enum.filter(Brain.needs_you(id), &(&1.kind == "remote_public"))

  test "only a remote's shape is kept, whoever sets it" do
    for good <- [
          "https://github.com/you/records.git",
          "https://x-token@github.com/you/records",
          "ssh://git@example.org:2222/you/records.git",
          "git@github.com:you/records.git",
          "/var/data/records.git",
          "file:///tmp/records.git"
        ],
        do: assert(Remote.shape(good) == :ok, good)

    for bad <- [
          "allen.strut@pm.me",
          "records",
          "https://github.com",
          "github.com/you/records",
          ""
        ],
        do: assert({:error, %{kind: :sima_qian_remote_invalid}} = Remote.shape(bad), bad)
  end

  test "an email address in the field is refused, and nothing is kept", ctx do
    assert {:error, %{kind: :sima_qian_remote_invalid}} =
             SimaQian.set_remote(ctx.id, "allen.strut@pm.me", nil, ctx.andrew)

    assert {:ok, %{remote_url: nil}} = Oneiroi.AgathosDaimon.fetch(ctx.id)
  end

  test "a token its host says cannot push is refused before anything is kept", ctx do
    Fake.put("you/records", %{private: true, push: false})

    assert {:error, %{kind: :sima_qian_remote_unpushable}} =
             SimaQian.set_remote_checked(
               ctx.id,
               "https://github.com/you/records.git",
               "tok",
               ctx.andrew
             )

    # Hidden from the token is no push either.
    assert {:error, %{kind: :sima_qian_remote_unpushable}} =
             SimaQian.set_remote_checked(
               ctx.id,
               "https://github.com/you/hidden",
               "tok",
               ctx.andrew
             )

    assert {:ok, %{remote_url: nil}} = Oneiroi.AgathosDaimon.fetch(ctx.id)
  end

  test "a public repository is kept and warned of; a private one is not", ctx do
    Fake.put("you/open", %{private: false, push: true})

    assert {:ok, %{visibility: "public", push: "yes"}} =
             SimaQian.set_remote_checked(
               ctx.id,
               "https://github.com/you/open.git",
               "tok",
               ctx.andrew
             )

    assert [%{about: %{what: what}, screen: "settings"}] = warned(ctx.id)
    assert what =~ "https://github.com/you/open.git"

    Fake.put("you/closed", %{private: true, push: true})

    assert {:ok, %{visibility: "private"}} =
             SimaQian.set_remote_checked(
               ctx.id,
               "https://github.com/you/closed",
               "tok",
               ctx.andrew
             )

    assert warned(ctx.id) == []
  end

  test "a host that cannot be asked is unknown, kept, and no warning", ctx do
    assert {:ok, %{visibility: "unknown", push: "unknown"}} =
             SimaQian.set_remote_checked(
               ctx.id,
               "https://example.org/you/records.git",
               nil,
               ctx.andrew
             )

    assert warned(ctx.id) == []
  end

  test "made public after the set, the next check warns, and only a change is recorded", ctx do
    Fake.put("you/records", %{private: true, push: true})

    {:ok, _} =
      SimaQian.set_remote_checked(ctx.id, "https://github.com/you/records", "tok", ctx.andrew)

    job = Actor.new(:job, "backups")
    assert %{visibility: "private"} = SimaQian.Backup.recheck_remote(ctx.id, job)
    assert warned(ctx.id) == []

    Fake.put("you/records", %{private: false, push: true})
    assert %{visibility: "public"} = SimaQian.Backup.recheck_remote(ctx.id, job)
    assert [_] = warned(ctx.id)
  end
end

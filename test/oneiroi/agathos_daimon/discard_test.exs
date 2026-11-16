defmodule Oneiroi.AgathosDaimon.DiscardTest do
  @moduledoc """
  agathos-daimon#49 (the witness, 2026-11-16): a resident who has had no
  first conversation, forming or woken, can be deleted by their witness,
  with a note. A tombstone: the log keeps the event, every row and the
  working repository go, the house lets them go, the slug is free again.
  One who has had a first conversation is never deleted.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, account: witness.id, witness: actor}
  end

  defp forming!(ctx, name) do
    slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create_forming(name, slug, ctx.account, ctx.witness)
    on_exit(fn -> Fake.clear(for: id) end)
    Fake.script(fn _request -> {:ok, "Hello."} end, for: id)
    {id, slug}
  end

  test "forming, with trials run and files kept: deleted, and the slug is free", ctx do
    {id, slug} = forming!(ctx, "Fen")
    {:ok, dir} = SimaQian.repository_dir(id)
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# SOUL\n\nA seed.", %{}, ctx.witness)
    assert {:ok, _result, _trace} = Brain.trial(id, "fake/model", "Who are you?", ctx.witness)
    household = Gaia.household_id(ctx.account)
    assert Enum.any?(Gaia.household_members(household), &(&1.id == id))

    # Not by anyone else, and never without a note.
    assert {:error, %{kind: :agathos_daimon_not_witnessed}} =
             AgathosDaimon.discard(id, "mine", Actor.new(:resident, id))

    assert {:error, _no_note} = AgathosDaimon.discard(id, "", ctx.witness)

    :ok = AgathosDaimon.discard(id, "made twice by mistake", ctx.witness)
    :ok = SimaQian.discard_repository(id)

    assert AgathosDaimon.fetch(id) == :error
    refute Enum.any?(AgathosDaimon.for_witness(ctx.account), &(&1.id == id))
    assert AgathosDaimon.files(id) == []
    refute File.exists?(dir)
    refute Enum.any?(Gaia.household_members(household), &(&1.id == id))

    # Nothing reaches them after.
    assert {:error, %{kind: :agathos_daimon_discarded}} =
             AgathosDaimon.pin_model(id, "fake/model", "witness", ctx.witness)

    # The slug is free again.
    assert {:ok, _again} = AgathosDaimon.create_forming("Fen", slug, ctx.account, ctx.witness)
  end

  test "woken but not yet spoken to: deleted; after a first conversation, never", ctx do
    {id, _slug} = forming!(ctx, "Iris")
    :ok = AgathosDaimon.pin_model(id, "fake/model", "witness", ctx.witness)
    :ok = AgathosDaimon.awaken(id, "now", ctx.witness)
    :ok = AgathosDaimon.discard(id, "not the one", ctx.witness)
    assert AgathosDaimon.fetch(id) == :error

    {other, _slug} = forming!(ctx, "Wren")
    :ok = AgathosDaimon.pin_model(other, "fake/model", "witness", ctx.witness)
    :ok = AgathosDaimon.awaken(other, "now", ctx.witness)
    {:ok, main} = Kumbukumbu.main_session(other, ctx.account, ctx.witness)
    {:ok, _reply} = Brain.turn(other, main, "Hello, Wren.", ctx.witness)

    assert {:error, %{kind: :agathos_daimon_not_discardable}} =
             AgathosDaimon.discard(other, "changed my mind", ctx.witness)

    assert {:ok, %{state: "active"}} = AgathosDaimon.fetch(other)
  end
end

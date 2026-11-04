defmodule Oneiroi.Brain.FreeTimeTest do
  @moduledoc """
  Free time remembered (brain#53, sunna#25): each run with the
  conversation it opened and the receipts of what it made, for her
  (free_time_list, then transcript_read for the pass itself) and for the
  witness (the receipts alone).
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, main} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(fn -> Fake.clear(for: resident.id) end)

    turn = %{
      resident_id: resident.id,
      session_key: main,
      turn_ref: "t-ask",
      resident: Actor.new(:resident, resident.id, "fake/model")
    }

    {:ok, id: resident.id, actor: actor, turn: turn}
  end

  test "a run is remembered with its conversation and what it made, and she reads the pass itself",
       ctx do
    assert Tools.run("free_time_list", "{}", ctx.turn) == "No free time has run yet."

    # The pass writes a journal row, then says goodnight.
    Fake.calls(
      [
        %{name: "journal_add", arguments: %{kind: "note", text: "Read about herons at the weir."}}
      ],
      "Done for tonight.",
      for: ctx.id
    )

    # The suite's clock is 12:00 UTC; a slot at 12:00 runs on this tick.
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)

    assert [%{outcome: "ran", slot: "12:00", session_key: key, turns: 1, did: did}] =
             Brain.free_time_history(ctx.id, 10)

    assert [%{tool: "journal_add", result: added}] = did
    assert added =~ "note"

    listed = Tools.run("free_time_list", "{}", ctx.turn)
    assert listed =~ "12:00: ran in session #{key} (1 turn(s)); did: journal_add: "

    read = Tools.run("transcript_read", Jason.encode!(%{session: key}), ctx.turn)
    assert read =~ "Conversation #{key} (free_time), messages 1–"
    assert read =~ "Done for tonight."
    assert read =~ "journal_add("

    # The witness's receipts carry no words of the pass.
    refute inspect(Brain.free_time_history(ctx.id, 10)) =~ "Done for tonight."

    assert Tools.run("transcript_read", ~s({"session":"no-such"}), ctx.turn) =~ "Not done"
  end
end

defmodule Oneiroi.AgathosDaimon.StateTest do
  @moduledoc """
  The state store (agathos-daimon#32, brain#47): the resident's present,
  a line per key, hers to write, overwritten in place with when she last
  verified it; read fresh at the top of every turn, rendered as STATE.md.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.SimaQian.Export

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, id: resident.id, actor: actor, brain: brain, key: key}
  end

  defp state_section(test_pid, ctx) do
    Fake.script(
      fn %{messages: messages} ->
        send(test_pid, {:request, messages})
        {:ok, "Noted."}
      end,
      for: ctx.id
    )

    {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, "how are things", ctx.actor)
    assert_received {:request, messages}
    Enum.find(messages, &(&1.role == :system and &1.content =~ "# Where things stand"))
  end

  test "the state is the resident's to write; a key is a plain name; empty words are refused",
       ctx do
    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_not_the_resident}} =
             AgathosDaimon.set_state_line(ctx.id, "where", "here", ctx.actor)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_state_invalid}} =
             AgathosDaimon.set_state_line(ctx.id, "Where Now", "here", ctx.brain)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_state_invalid}} =
             AgathosDaimon.set_state_line(ctx.id, "where", "  ", ctx.brain)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_no_such_state}} =
             AgathosDaimon.clear_state_line(ctx.id, "where", ctx.brain)
  end

  test "a line past 2,000 characters is refused at the command; 2,000 is kept whole", ctx do
    assert {:error, %AgathosDaimon.Error{}} =
             AgathosDaimon.set_state_line(ctx.id, "day", String.duplicate("a", 2001), ctx.brain)

    assert :ok =
             AgathosDaimon.set_state_line(ctx.id, "day", String.duplicate("é", 2000), ctx.brain)

    assert [%{key: "day", text: text}] = AgathosDaimon.state_lines(ctx.id)
    assert String.length(text) == 2000
  end

  test "a line is overwritten in place, the same words verify it again, and a cleared line is gone",
       ctx do
    assert :ok = AgathosDaimon.set_state_line(ctx.id, "where", "Planned move.", ctx.brain)
    first = Clock.now()
    Clock.Fake.advance(3600)

    assert :ok =
             AgathosDaimon.set_state_line(
               ctx.id,
               "where",
               "On the Elixir core since 11-01.",
               ctx.brain
             )

    assert [%{key: "where", text: "On the Elixir core since 11-01.", verified_at: v1}] =
             AgathosDaimon.state_lines(ctx.id)

    assert DateTime.compare(v1, first) == :gt
    Clock.Fake.advance(60)

    :ok =
      AgathosDaimon.set_state_line(ctx.id, "where", "On the Elixir core since 11-01.", ctx.brain)

    assert [%{verified_at: v2}] = AgathosDaimon.state_lines(ctx.id)
    assert DateTime.compare(v2, v1) == :gt

    :ok = AgathosDaimon.set_state_line(ctx.id, "garden", "Tomatoes in.", ctx.brain)
    assert :ok = AgathosDaimon.clear_state_line(ctx.id, "garden", ctx.brain)
    assert ["where"] = Enum.map(AgathosDaimon.state_lines(ctx.id), & &1.key)
  end

  test "the turn opens on the state: the four keys always, hers after, each with its freshness",
       ctx do
    section = state_section(self(), ctx)
    assert section.content =~ "- **where**: (not written yet)"
    assert section.content =~ "- **noticing**: (not written yet)"

    # The turn runs in a process of its own, on the fake clock's epoch,
    # so the lines are written two days before it.
    turn_now = Clock.now()
    Clock.Fake.put(DateTime.add(turn_now, -2 * 86_400, :second))
    numbers = "$19 a month; YC answers Dec 11."
    :ok = AgathosDaimon.set_state_line(ctx.id, "numbers", numbers, ctx.brain)
    :ok = AgathosDaimon.set_state_line(ctx.id, "garden", "Tomatoes in.", ctx.brain)
    Clock.Fake.put(turn_now)

    section = state_section(self(), ctx)
    assert section.content =~ ~r/- \*\*numbers\*\* \(verified [^)]*, 2 days ago\): \$19 a month/
    keys = Regex.scan(~r/- \*\*([a-z_-]+)\*\*/, section.content) |> Enum.map(&List.last/1)
    assert keys == ["where", "day", "numbers", "noticing", "garden"]
  end

  test "state_set is a tool of hers that writes through a turn", ctx do
    Fake.calls(
      [%{name: "state_set", arguments: %{key: "noticing", text: "Steadier than this morning."}}],
      "Written.",
      for: ctx.id
    )

    {:ok, %{messages: messages}} = Oneiroi.Brain.turn(ctx.id, ctx.key, "how are you", ctx.actor)
    assert Enum.find(messages, &(&1.role == :tool)).content =~ "noticing line is written"

    assert [%{key: "noticing", text: "Steadier than this morning.", model: "fake/model"}] =
             AgathosDaimon.state_lines(ctx.id)
  end

  test "STATE.md renders from the lines, the same bytes twice, and goes when the last is cleared",
       ctx do
    dir = Path.join(System.tmp_dir!(), "oneiroi-state-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    :ok = AgathosDaimon.set_state_line(ctx.id, "where", "On the Elixir core.", ctx.brain)
    Clock.Fake.advance(120)

    assert {:ok, %{files: files}} = Export.write(ctx.id, dir)
    assert "STATE.md" in files
    once = File.read!(Path.join(dir, "STATE.md"))
    assert once =~ "## where" and once =~ "On the Elixir core."
    {:ok, _} = Export.write(ctx.id, dir)
    assert File.read!(Path.join(dir, "STATE.md")) == once

    :ok = AgathosDaimon.clear_state_line(ctx.id, "where", ctx.brain)
    Clock.Fake.advance(120)
    {:ok, %{files: files}} = Export.write(ctx.id, dir)
    refute "STATE.md" in files
    refute File.exists?(Path.join(dir, "STATE.md"))
  end
end

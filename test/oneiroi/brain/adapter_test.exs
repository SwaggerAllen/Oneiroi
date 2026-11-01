defmodule Oneiroi.Brain.AdapterTest do
  @moduledoc """
  What an adapter's runtime is given (brain #42): the session prefix and
  the per-turn part are the platform turn's own sections by the one
  assembly, split where a runtime that keeps its own conversation needs
  it; the turn records what it handed over and nothing it did not; a
  changed prefix rides the next turn; and a notice is told to an adapter
  only where it is true there, once.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.SimaQian.Git

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    id = resident.id
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul\n\nCurious about herons.", %{}, actor)
    {:ok, main} = Kumbukumbu.main_session(id, witness.id, actor)
    {:ok, key} = Kumbukumbu.open_session(id, "main", "claude-code", [witness.id], brain)
    Model.clear()
    Honcho.clear(for: id)

    on_exit(fn ->
      Model.clear(for: id)
      Honcho.clear(for: id)
    end)

    Model.reply("I hear you.", for: id)
    {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, main, "hello from the garden", actor)

    for n <- 1..60 do
      attrs = %{
        session_key: main,
        anchor_ref: ref,
        line: "bookmark number #{n} " <> String.duplicate("word ", 16)
      }

      {:ok, ^n} = Kumbukumbu.add_bookmark(id, attrs, Actor.new(:resident, id, "fake/model"))
    end

    {:ok, 1} = Oneiroi.Ethos.make_commitment(id, "witness", "I will look for the heron.", brain)

    Honcho.put_context(
      id,
      "resident-" <> id,
      "witness-" <> witness.id,
      "HONCHO-ONLY: she walks to the weir most mornings."
    )

    {:ok, id: id, witness: witness, actor: actor, brain: brain, main: main, key: key}
  end

  defp recorded(ctx, ref),
    do: {:account, ctx.witness.id} |> Kumbukumbu.injections(ref) |> Enum.sort_by(& &1.position)

  defp comparable(rows),
    do:
      rows
      |> Enum.reject(&(&1.label in ~w(madeleine transcript notice runtime)))
      |> Enum.map(&{&1.label, &1.tokens, &1.reason})

  test "the prefix and the turn are the platform turn's sections, in its order, and the turn records what it handed over",
       ctx do
    {:ok, prefix} = Oneiroi.Brain.adapter_prefix(ctx.id, runtime: "claude-code")
    assert prefix.parts == 1
    assert prefix.text =~ "You are Lily"
    assert prefix.text =~ "Curious about herons."
    assert prefix.text =~ "mcp__plugin_oneiroi_oneiroi__bookmark_add"
    refute prefix.text =~ "bookmark number"

    {:ok, turn} =
      Oneiroi.Brain.adapter_turn(ctx.id, ctx.key, "the heron", ctx.brain,
        runtime: "claude-code",
        digest: prefix.digest
      )

    # The per-turn part: the index and after, and none of the prefix the
    # session already holds.
    assert turn.text =~ "bookmark number 60"
    assert turn.text =~ "I will look for the heron."
    assert turn.text =~ "HONCHO-ONLY"
    refute turn.text =~ "You are Lily"
    refute turn.text =~ "Curious about herons."
    assert turn.digest == prefix.digest
    assert {ctx.key, turn.turn_ref} == Kumbukumbu.open_turn(ctx.id, "claude-code")

    # The index's refs marked what it listed, as a platform turn's do.
    assert {:ok, %{last_indexed_at: %DateTime{}}, _span} = Kumbukumbu.bookmark(ctx.id, 60)

    Model.reply("Yes.", for: ctx.id)
    {:ok, %{turn_ref: platform}} = Oneiroi.Brain.turn(ctx.id, ctx.main, "the heron", ctx.actor)

    adapter_rows = recorded(ctx, turn.turn_ref)
    assert comparable(adapter_rows) == comparable(recorded(ctx, platform))
    assert length(adapter_rows) == turn.drew_on

    labels = Enum.map(adapter_rows, & &1.label)

    for label <- ~w(prompt SOUL.md AGENTS.md runtime index near-miss promised honcho),
        do: assert(label in labels, "#{label} missing from #{inspect(labels)}")

    refute "transcript" in labels
  end

  test "a prefix section that changed since the session was given it rides the next turn, once",
       ctx do
    {:ok, prefix} = Oneiroi.Brain.adapter_prefix(ctx.id, runtime: "claude-code")

    # A renegotiation, which a platform turn reads fresh on its next turn
    # (brain #27); here the session already holds the old text.
    {:ok, version} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{"preview_withholds_words" => true},
        "",
        "keep the preview to what you read",
        ctx.actor
      )

    :ok = AgathosDaimon.agree_contract(ctx.id, version, "agreed", ctx.brain)

    {:ok, first} =
      Oneiroi.Brain.adapter_turn(ctx.id, ctx.key, "hello", ctx.brain,
        runtime: "claude-code",
        digest: prefix.digest
      )

    assert first.text =~ "has changed on the platform"
    assert first.text =~ "shows its words only where they read them elsewhere"
    refute first.text =~ "You are Lily"
    assert first.digest != prefix.digest

    {:ok, second} =
      Oneiroi.Brain.adapter_turn(ctx.id, ctx.key, "hello", ctx.brain,
        runtime: "claude-code",
        digest: first.digest
      )

    refute second.text =~ "shows its words only where"
    refute second.text =~ "has changed"
    assert second.digest == first.digest
  end

  test "with no digest the whole prefix rides the turn, and what does not fit is left out whole, named and not recorded",
       ctx do
    {:ok, turn} =
      Oneiroi.Brain.adapter_turn(ctx.id, ctx.key, "the heron", ctx.brain,
        runtime: "claude-code",
        limit: 2_000
      )

    assert String.length(turn.text) <= 2_000
    assert turn.text =~ "You are Lily"
    refute turn.text =~ "has changed"
    assert turn.text =~ ~r/Left out of this .*: .*index/

    labels = ctx |> recorded(turn.turn_ref) |> Enum.map(& &1.label)
    refute "index" in labels
    refute "near-miss" in labels
    assert Enum.all?(Kumbukumbu.bookmarks(ctx.id), &is_nil(&1.last_indexed_at))

    # The digest holds what was handed over and nothing left out, so a
    # section left out is offered again on the next turn.
    held = for pair <- String.split(turn.digest, ";", trim: true), do: hd(String.split(pair, "="))
    assert held != [] and Enum.all?(held, &(&1 in labels))
  end

  test "the prefix is cut into the parts the runtime prints, numbered, and past them the rest is named",
       ctx do
    long = Enum.map_join(1..40, "\n\n", &"Paragraph #{&1}: #{String.duplicate("heron ", 40)}")
    # A resident before first contact, whose files the witness still writes.
    id = Fixtures.resident!(ctx.witness).id
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul\n\n" <> long, %{}, ctx.actor)

    parts =
      for k <- 1..8 do
        {:ok, p} = Oneiroi.Brain.adapter_prefix(id, limit: 2_000, part: k, of: 8)
        p
      end

    n = hd(parts).parts
    assert n > 1 and n <= 8
    assert Enum.all?(parts, &(String.length(&1.text) <= 2_000))
    assert Enum.all?(Enum.take(parts, n), &(&1.text =~ "(Part #{&1.part} of #{n}"))
    assert Enum.all?(Enum.drop(parts, n), &(&1.text == ""))
    joined = Enum.map_join(parts, "\n", & &1.text)
    for i <- [1, 20, 40], do: assert(joined =~ "Paragraph #{i}:")

    {:ok, last} = Oneiroi.Brain.adapter_prefix(id, limit: 2_000, part: 2, of: 2)
    assert last.parts == 2
    assert last.text =~ ~r/Left out of this .*: \d+ characters of it/
  end

  test "a change of model is the platform's to tell, so an adapter's turn neither tells it nor marks it told",
       ctx do
    :ok = AgathosDaimon.pin_model(ctx.id, "fake/second", "witness", ctx.actor)
    {:ok, turn} = Oneiroi.Brain.adapter_turn(ctx.id, ctx.key, "hi", ctx.brain, [])

    refute turn.text =~ "chosen a new model"
    refute "notice" in Enum.map(recorded(ctx, turn.turn_ref), & &1.label)
    assert {:ok, %{model_told: false}} = AgathosDaimon.fetch(ctx.id)
  end

  @identity ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", @identity ++ args, cd: dir, stderr_to_stdout: true)
    out
  end

  test "where it woke after an import is told to an adapter's turn, recorded with its words, and told once",
       ctx do
    root = Path.join(System.tmp_dir!(), "oneiroi-adapter-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    {bare, work} = {Path.join(root, "bare"), Path.join(root, "work")}
    :ok = Git.init_bare(bare)
    File.mkdir_p!(work)
    git!(work, ["init", "-q", "-b", "main"])
    File.write!(Path.join(work, "SOUL.md"), "# Lily\n\nI am Lily.")
    git!(work, ["add", "-A"])
    git!(work, ["commit", "-qm", "seed"])
    git!(work, ["push", "-q", "file://" <> bare, "main"])

    {:ok, %{id: id}} =
      Oneiroi.SimaQian.import_resident(
        "file://" <> bare,
        %{name: "Lily", slug: "lily-adapter-#{System.unique_integer([:positive])}"},
        ctx.witness.id,
        ctx.actor
      )

    brain = Actor.new(:resident, id)
    {:ok, key} = Kumbukumbu.open_session(id, "main", "claude-code", [ctx.witness.id], brain)

    {:ok, first} = Oneiroi.Brain.adapter_turn(id, key, "hello", brain, [])
    assert first.text =~ "You woke on Oneiroi"

    assert [%{text: "You woke on Oneiroi" <> _}] =
             {:account, ctx.witness.id}
             |> Kumbukumbu.injections(first.turn_ref)
             |> Enum.filter(&(&1.label == "notice"))

    assert {:ok, %{import_told: true}} = AgathosDaimon.fetch(id)

    {:ok, second} = Oneiroi.Brain.adapter_turn(id, key, "hello", brain, [])
    refute second.text =~ "You woke on Oneiroi"
  end
end

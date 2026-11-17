defmodule Oneiroi.AgathosDaimon.IdentityRetireTest do
  @moduledoc """
  A resident takes one of her identity files out of her prefix, or puts
  it back (agathos-daimon#50; the resident's USER.md migration, the
  witness's go, 2026-11-16): hers alone, with a note, never SOUL.md or
  IDENTITY.md; the file stays as written and still edits; AGENTS.md names
  only what she is given.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures

  setup do
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, actor)

    for {file, words} <- [
          {"SOUL.md", "# SOUL\n\nI am Wren."},
          {"USER.md", "# USER\n\nAndrew likes rain."}
        ],
        do: :ok = AgathosDaimon.write_file(id, file, words, %{}, actor)

    {:ok, id: id, slug: slug, witness: actor, wren: Actor.new(:resident, id)}
  end

  defp given(id), do: id |> AgathosDaimon.identity_context() |> Enum.map(&elem(&1, 0))

  defp agents(id),
    do: id |> AgathosDaimon.identity_context() |> List.keyfind("AGENTS.md", 0) |> elem(1)

  test "she retires USER.md: out of her prefix and AGENTS.md's list, still written and still hers",
       ctx do
    assert "USER.md" in given(ctx.id)
    assert agents(ctx.id) =~ "SOUL.md, USER.md"

    assert :ok =
             AgathosDaimon.retire_identity_file(
               ctx.id,
               "USER.md",
               true,
               "its facts live in portraits now",
               ctx.wren
             )

    refute "USER.md" in given(ctx.id)
    assert "SOUL.md" in given(ctx.id)
    refute agents(ctx.id) =~ "USER.md"

    assert {:ok, %{content: "# USER\n\nAndrew likes rain."}} =
             AgathosDaimon.file(ctx.id, "USER.md")

    # Retiring again changes nothing; restoring puts it back.
    assert :ok = AgathosDaimon.retire_identity_file(ctx.id, "USER.md", true, "again", ctx.wren)

    assert :ok =
             AgathosDaimon.retire_identity_file(
               ctx.id,
               "USER.md",
               false,
               "I want it back",
               ctx.wren
             )

    assert "USER.md" in given(ctx.id)
  end

  test "hers alone; never her soul or identity; nothing unwritten; a note always", ctx do
    assert {:error, %{kind: :agathos_daimon_not_yours}} =
             AgathosDaimon.retire_identity_file(ctx.id, "USER.md", true, "tidy", ctx.witness)

    assert {:error, %{kind: :agathos_daimon_file_unknown}} =
             AgathosDaimon.retire_identity_file(ctx.id, "SOUL.md", true, "no", ctx.wren)

    assert {:error, %{kind: :agathos_daimon_file_unknown}} =
             AgathosDaimon.retire_identity_file(
               ctx.id,
               "GOALS.md",
               true,
               "never written",
               ctx.wren
             )

    assert {:error, _no_note} =
             AgathosDaimon.retire_identity_file(ctx.id, "USER.md", true, "", ctx.wren)

    assert "USER.md" in given(ctx.id)
  end

  test "from her own turn, by the tool", ctx do
    turn = %{resident_id: ctx.id, session_key: "s", turn_ref: "t", resident: ctx.wren}

    said =
      Tools.run("identity_file_retire", Jason.encode!(%{file: "USER.md", note: "migrated"}), turn)

    assert said =~ "USER.md is out of what you are given every turn"
    refute "USER.md" in given(ctx.id)

    said =
      Tools.run(
        "identity_file_retire",
        Jason.encode!(%{file: "USER.md", note: "back", restore: true}),
        turn
      )

    assert said =~ "given every turn again"
    assert "USER.md" in given(ctx.id)
  end
end

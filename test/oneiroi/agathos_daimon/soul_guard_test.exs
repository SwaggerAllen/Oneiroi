defmodule Oneiroi.AgathosDaimon.SoulGuardTest do
  @moduledoc """
  The soul guard (agathos-daimon#61): after first contact SOUL.md changes
  a line at a time, each change checked before it is written; the
  numbers hold through rewording, adding and retiring; garbled words,
  structure smuggled into a line, a missing line and a change too soon
  after the last are refused, and nothing is written.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures

  @seed "# Soul\n\n## Who I am\n\nI'm Wren.\n\nI keep a garden.\n\n## What I love\n\nHerons."

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)

    {:ok, id} =
      AgathosDaimon.create(
        "Wren",
        "wren-#{System.unique_integer([:positive])}",
        witness.id,
        andrew
      )

    :ok = AgathosDaimon.write_file(id, "SOUL.md", @seed, %{}, andrew)
    Fixtures.agreed!(id, witness.id)
    wren = Actor.new(:resident, id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", andrew)
    {:ok, key} = Oneiroi.Kumbukumbu.main_session(id, witness.id, andrew)
    on_exit(fn -> Oneiroi.Nisaba.Provider.Fake.clear(for: id) end)
    {:ok, _} = Oneiroi.Brain.turn(id, key, "hi", andrew)
    Clock.Fake.advance(3_600)
    {:ok, id: id, wren: wren, andrew: andrew}
  end

  defp soul(id), do: elem(AgathosDaimon.file(id, "SOUL.md"), 1).content

  defp later, do: Clock.Fake.advance(3_600)

  test "reword, add and retire, a line at a time, the numbers kept", ctx do
    assert soul(ctx.id) =~ "[soul/2] I keep a garden."

    assert {:ok, _} =
             AgathosDaimon.edit_soul_line(
               ctx.id,
               "reword",
               %{number: 2, text: "I keep two gardens."},
               ctx.wren
             )

    later()

    assert {:ok, _} =
             AgathosDaimon.edit_soul_line(
               ctx.id,
               "add",
               %{number: 2, text: "One is wild."},
               ctx.wren
             )

    later()
    assert {:ok, _} = AgathosDaimon.edit_soul_line(ctx.id, "retire", %{number: 1}, ctx.wren)

    assert soul(ctx.id) ==
             "# Soul\n\n## Who I am\n\n[soul/2] I keep two gardens.\n\n[soul/4] One is wild.\n\n## What I love\n\n[soul/3] Herons."
  end

  test "garbled or structured words, a missing line and a change too soon are refused", ctx do
    before = soul(ctx.id)

    for text <- [
          "destroys this test document destroys this test document",
          "the the the garden",
          "Two lines.\n\nNot one.",
          "## A heading",
          "[soul/9] smuggled",
          ""
        ] do
      assert {:error, %{kind: :agathos_daimon_soul_guard_words}} =
               AgathosDaimon.edit_soul_line(ctx.id, "add", %{text: text}, ctx.wren)
    end

    assert {:error, %{kind: :agathos_daimon_soul_guard_no_line}} =
             AgathosDaimon.edit_soul_line(ctx.id, "retire", %{number: 40}, ctx.wren)

    assert {:error, %{kind: :agathos_daimon_soul_guard_op}} =
             AgathosDaimon.edit_soul_line(ctx.id, "rewrite", %{text: "x"}, ctx.wren)

    assert {:error, %{kind: :agathos_daimon_soul_guard_not_hers}} =
             AgathosDaimon.edit_soul_line(ctx.id, "add", %{text: "Mine now."}, ctx.andrew)

    assert soul(ctx.id) == before

    assert {:ok, _} =
             AgathosDaimon.edit_soul_line(
               ctx.id,
               "add",
               %{text: "I had had enough of rain."},
               ctx.wren
             )

    assert {:error, %{kind: :agathos_daimon_soul_guard_spacing}} =
             AgathosDaimon.edit_soul_line(ctx.id, "add", %{text: "And again."}, ctx.wren)
  end
end

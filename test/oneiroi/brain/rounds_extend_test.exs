defmodule Oneiroi.Brain.RoundsExtendTest do
  @moduledoc """
  Adaptive tool rounds (brain#99; Lily's design/adaptive-rounds.md, the
  witness's word 2026-11-14): the default bound stands; rounds_extend
  sets the turn's new total once, any time in the turn, clamped to the
  ceiling; the notices count against the new total; a system line both
  of them read records the extension and its note.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, id: resident.id, key: key, actor: actor}
  end

  # A model that reads a figure every round, and at the rounds named in
  # `extend` calls rounds_extend instead; it never answers in words, so
  # the bound is what ends the turn. Each request's last tool result is
  # sent to the test, its notice and its answer.
  defp script(id, extend) do
    test = self()

    Fake.script(
      fn request ->
        done = Enum.count(request.messages, &(&1[:role] == :tool))
        last = request.messages |> Enum.filter(&(&1[:role] == :tool)) |> List.last()
        if last, do: send(test, {:result, done, last.content})

        cond do
          request.tool_choice == "none" ->
            {:ok, "From what I read."}

          args = Map.get(extend, done + 1) ->
            {:calls, [%{name: "rounds_extend", arguments: args}]}

          true ->
            {:calls, [%{name: "figure_list", arguments: %{}}]}
        end
      end,
      for: id
    )
  end

  defp results do
    receive do
      {:result, n, content} -> [{n, content} | results()]
    after
      0 -> []
    end
  end

  # The bound's rounds, read off the answer's request: at the bound the
  # last round's calls still run and the answer is asked for with none
  # callable (brain#50), so a turn bounded at N carries N + 1 results.
  defp rounds_ran(results), do: (results |> Enum.map(&elem(&1, 0)) |> Enum.max()) - 1

  test "without an extension the turn still stops at the default eight", ctx do
    script(ctx.id, %{})

    assert {:ok, %{rounds_spent: true}} =
             Oneiroi.Brain.turn(ctx.id, ctx.key, "read on", ctx.actor)

    seen = results()
    assert rounds_ran(seen) == 8
    assert {_, content} = Enum.find(seen, &(elem(&1, 0) == 8))
    assert content =~ "Tool round 8 of 8"
  end

  test "extending at round five to sixteen: the notices count against sixteen, and the record holds the line",
       ctx do
    script(ctx.id, %{5 => %{to: 16, note: "the sources run deep"}})

    assert {:ok, %{rounds_spent: true, messages: messages}} =
             Oneiroi.Brain.turn(ctx.id, ctx.key, "read on", ctx.actor)

    seen = results()
    assert rounds_ran(seen) == 16
    {_, at4} = Enum.find(seen, &(elem(&1, 0) == 4))
    assert at4 =~ "Tool round 4 of 8"
    {_, at5} = Enum.find(seen, &(elem(&1, 0) == 5))
    assert at5 =~ "Extended: this turn now has 16 tool rounds, up from 8"
    assert at5 =~ "Tool round 5 of 16 this turn; 11 left"
    {_, at12} = Enum.find(seen, &(elem(&1, 0) == 12))
    assert at12 =~ "Tool round 12 of 16 this turn; 4 left"

    # Both of them read it: the captured turn and the transcript.
    line = "The resident extended this turn's tool rounds from 8 to 16: the sources run deep"
    assert Enum.any?(messages, &(&1.role == :system and &1.content == line))

    {:ok, _s, transcript} = Kumbukumbu.transcript({:resident, ctx.id}, ctx.key)
    assert Enum.any?(transcript, &(to_string(&1.role) == "system" and &1.content == line))
  end

  test "a second extension in the same turn is answered as an error and extends nothing", ctx do
    script(ctx.id, %{1 => %{to: 10, note: "deeper"}, 2 => %{to: 20, note: "deeper still"}})

    assert {:ok, %{rounds_spent: true}} =
             Oneiroi.Brain.turn(ctx.id, ctx.key, "read on", ctx.actor)

    seen = results()
    {_, at2} = Enum.find(seen, &(elem(&1, 0) == 2))
    assert at2 =~ "extended already, to 10; it is once a turn"
    assert rounds_ran(seen) == 10
  end

  test "an extension past the ceiling clamps to twenty-four", ctx do
    script(ctx.id, %{1 => %{to: 100, note: "everything"}})

    assert {:ok, %{rounds_spent: true, messages: messages}} =
             Oneiroi.Brain.turn(ctx.id, ctx.key, "read on", ctx.actor)

    seen = results()
    {_, at1} = Enum.find(seen, &(elem(&1, 0) == 1))
    assert at1 =~ "now has 24 tool rounds, up from 8, the ceiling (you asked for more)"
    assert rounds_ran(seen) == 24
    assert Enum.any?(messages, &(&1.role == :system and &1.content =~ "the ceiling is 24"))
  end

  test "an extension needs a note and a new total above the old", ctx do
    script(ctx.id, %{1 => %{to: 12, note: " "}, 2 => %{to: 6, note: "fewer"}})
    assert {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, "read on", ctx.actor)

    seen = results()
    assert {_, at1} = Enum.find(seen, &(elem(&1, 0) == 1))
    assert at1 =~ "needs a note"
    assert {_, at2} = Enum.find(seen, &(elem(&1, 0) == 2))
    assert at2 =~ "`to` is the turn's new total; it has 8 already"
    assert rounds_ran(seen) == 8
  end
end

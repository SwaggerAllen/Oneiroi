defmodule Oneiroi.Brain.OracleTranscriptTest do
  @moduledoc """
  A conversation as an oracle source (kumbukumbu#94; the witness,
  2026-11-21, after two OOM kills at 06:30Z: Scarlett's four questions
  each named her whole main conversation, 1,697 messages, to read a
  stretch of ninety). Named with a range, only those messages are read,
  a page at a time from the database. Named whole, it is not read up
  front: the oracle is told its size and to search and page it with its
  tools first.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Oracle
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)
    slug = "lily-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Lily", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    {:ok, key} = Kumbukumbu.main_session(id, witness.id, andrew)
    {:ok, dir} = SimaQian.repository_dir(id)
    lily = Actor.new(:resident, id, "fake/model")
    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:asked, Enum.map_join(messages, "\n", &to_string(&1[:content]))})
        {:ok, "Read.\nUsed: none\nConfidence: medium, from what was given."}
      end,
      for: id
    )

    on_exit(fn ->
      Fake.clear(for: id)
      File.rm_rf!(dir)
    end)

    # Ten turns, twenty messages: "said 1" … "said 20".
    for t <- 1..10 do
      at = Clock.now()

      :ok =
        Kumbukumbu.capture(
          id,
          key,
          "t-#{t}",
          at,
          [
            %{role: :user, content: "said #{2 * t - 1}.", sent_at: at, actor: andrew},
            %{role: :assistant, content: "said #{2 * t}.", sent_at: at, actor: lily}
          ],
          lily
        )
    end

    {:ok, id: id, key: key, lily: lily}
  end

  defp asked do
    receive do
      {:asked, words} -> words <> asked()
    after
      0 -> ""
    end
  end

  defp ask(ctx, source) do
    {:ok, [n]} =
      Seshat.dispatch_oracle(
        ctx.id,
        ctx.key,
        [%{"question" => "What was said?", "sources" => [source]}],
        ctx.lily
      )

    :ok = Oracle.run(ctx.id, n)
    asked()
  end

  test "a range reads those messages alone", ctx do
    words = ask(ctx, "transcript/#{ctx.key}@5-8")
    assert words =~ "Messages 5–8 of 20"

    for n <- 5..8, do: assert(words =~ "said #{n}.")
    refute words =~ "said 4."
    refute words =~ "said 9."
  end

  test "named whole, it is not read up front, and the oracle is pointed to its tools", ctx do
    words = ask(ctx, "transcript/#{ctx.key}")
    assert words =~ "Not read up front: transcript/#{ctx.key} is 20 messages"
    assert words =~ "transcript_search"
    assert words =~ "Try your search tools before reading anything from start to finish"
    refute words =~ "said 7."
  end
end

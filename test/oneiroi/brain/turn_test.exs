defmodule Oneiroi.Brain.TurnTest do
  @moduledoc "A turn through the brain on the fake provider: captured, recorded, streamed; the three endings."
  use Oneiroi.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", Actor.new(:witness, witness.id))
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, Actor.new(:witness, witness.id))
    Fake.clear()
    :ok = PubSub.subscribe(:brain, :session)
    {:ok, witness: witness, resident: resident, key: key, actor: Actor.new(:witness, witness.id)}
  end

  test "the capacity alarm flags the turn when the always-loaded prefix nears the window", ctx do
    id = ctx.resident.id
    big = String.duplicate("I am Lily and the garden is mine. ", 1_700)
    assert byte_size(big) < 64_000
    :ok = AgathosDaimon.write_file(id, "SOUL.md", big, %{origin: "authored"}, ctx.actor)
    assert {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, ctx.key, "hello", ctx.actor)

    assert [%{label: "capacity", tokens: tokens, reason: reason}] =
             {:account, ctx.witness.id}
             |> Kumbukumbu.injections(ref)
             |> Enum.filter(&(&1.label == "capacity"))

    assert tokens > 14_400
    assert reason =~ "of a 16000-token window"
    assert reason =~ "90% alarm"
  end

  test "the near-miss record: the bookmarks the index ranked and did not inject, with their reasons, and never counted as indexed",
       ctx do
    id = ctx.resident.id
    resident = Actor.new(:resident, id, "fake/model")
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        id,
        ctx.key,
        "anchor",
        at,
        [%{role: :user, content: "a moment", sent_at: at, actor: ctx.actor}],
        resident
      )

    for n <- 1..60 do
      attrs = %{
        session_key: ctx.key,
        anchor_ref: "anchor",
        line: "bookmark number #{n} " <> String.duplicate("word ", 16),
        summary: "the #{n}th"
      }

      {:ok, ^n} = Kumbukumbu.add_bookmark(id, attrs, resident)
    end

    assert {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, ctx.key, "hello", ctx.actor)
    rows = Kumbukumbu.injections({:account, ctx.witness.id}, ref)
    [index] = Enum.filter(rows, &(&1.label == "index"))
    misses = Enum.filter(rows, &(&1.label == "near-miss"))
    assert misses != []
    assert index.reason =~ "#{length(misses)} considered and not returned"
    assert Enum.all?(misses, &(&1.tokens == 0 and &1.reason =~ "considered and not injected"))
    assert Enum.all?(misses, &(&1.text =~ "bookmark number"))

    # A near-miss is not in the index text and its row was never marked as indexed.
    [miss | _] = misses
    [number] = Regex.run(~r/bookmark #(\d+)/, miss.reason, capture: :all_but_first)
    refute index.text =~ miss.text

    assert {:ok, %{last_indexed_at: nil}, _span} =
             Kumbukumbu.bookmark(id, String.to_integer(number))
  end

  test "the ranked index brings the bookmark the words sit near first, and the madeleine never repeats what the index returned",
       ctx do
    id = ctx.resident.id
    resident = Actor.new(:resident, id, "fake/model")
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        id,
        ctx.key,
        "anchor",
        at,
        [%{role: :user, content: "a moment", sent_at: at, actor: ctx.actor}],
        resident
      )

    {:ok, 1} =
      Kumbukumbu.add_bookmark(
        id,
        %{
          session_key: ctx.key,
          anchor_ref: "anchor",
          line:
            "the greenhouse thermometer broke " <> String.duplicate("greenhouse thermometer ", 3),
          summary: String.duplicate("greenhouse thermometer ", 8)
        },
        resident
      )

    for n <- 2..60 do
      attrs = %{
        session_key: ctx.key,
        anchor_ref: "anchor",
        line: "bookmark number #{n} " <> String.duplicate("word ", 16),
        summary: "the #{n}th"
      }

      {:ok, ^n} = Kumbukumbu.add_bookmark(id, attrs, resident)
    end

    assert {:ok, %{turn_ref: ref}} =
             Oneiroi.Brain.turn(id, ctx.key, "is the greenhouse thermometer fixed?", ctx.actor)

    rows = Kumbukumbu.injections({:account, ctx.witness.id}, ref)
    [index] = Enum.filter(rows, &(&1.label == "index"))

    # Ranked by nearness (kumbukumbu#46): the greenhouse comes first, and
    # it was the seed the edges are read from.
    assert index.text =~ ~r/\A#1 2026-10-26 the greenhouse thermometer broke/
    assert index.reason =~ "the ranked index (kumbukumbu#46)"

    # The madeleine reaches past what the index returned: never #1 now.
    for recall <- Enum.filter(rows, &(&1.label == "madeleine")) do
      refute recall.text =~ "#1 2026-10-26"
    end

    assert {:ok, %{last_indexed_at: %DateTime{}}, _span} = Kumbukumbu.bookmark(id, 1)
  end

  # The duplicate of 2026-11-03 (kumbukumbu#47): a deploy's overlap, or a
  # session process restarted mid-turn, left the new process's memory
  # empty while the first turn still ran, and the client's retry under
  # the same ref ran a second turn. The claim is on the stream.
  test "a retry is a duplicate across a session process's restart while the first turn still runs",
       ctx do
    id = ctx.resident.id
    test_pid = self()

    Fake.script(
      fn request ->
        send(test_pid, :running)

        receive do
          :go -> :ok
        after
          5_000 -> :ok
        end

        {:ok, "Answered " <> List.last(request.messages)[:content] <> "."}
      end,
      for: id
    )

    assert {:ok, %{state: "running"}} =
             Oneiroi.Brain.submit(id, ctx.key, "once", ctx.actor, "ref-once-00001")

    assert_receive :running, 5_000

    # The session's process goes, as an old instance's does at a deploy;
    # its turn runs on.
    [{pid, _}] = Registry.lookup(:brain_registry, {id, ctx.key})
    GenServer.stop(pid)
    # The registry lets go of a stopped process a moment after it stops.
    gone(id, ctx.key, pid)

    assert {:ok, %{state: "duplicate"}} =
             Oneiroi.Brain.submit(id, ctx.key, "once", ctx.actor, "ref-once-00001")

    refute_receive :running, 200

    for task <- Task.Supervisor.children(:brain_turns), do: send(task, :go)
    assert_receive {:oneiroi, _, {^id, _, {:turn, "ref-once-00001", _}}, _}, 5_000
  end

  test "a claim is taken once, again only when stale, and never after its capture", ctx do
    id = ctx.resident.id
    actor = ctx.actor
    now = Clock.now()
    fresh = DateTime.add(now, -60, :second)
    stale = DateTime.add(now, 1, :second)

    assert :claimed = Kumbukumbu.claim_turn(id, ctx.key, "ref-claim-0001", fresh, actor)
    assert :duplicate = Kumbukumbu.claim_turn(id, ctx.key, "ref-claim-0001", fresh, actor)
    # Claimed before `stale_before`, never captured: its turn died; take it again.
    assert :claimed = Kumbukumbu.claim_turn(id, ctx.key, "ref-claim-0001", stale, actor)

    :ok =
      Kumbukumbu.capture(
        id,
        ctx.key,
        "ref-claim-0001",
        now,
        [%{role: :user, content: "kept", sent_at: now, actor: actor}],
        Actor.new(:resident, id, "fake/model")
      )

    # Captured, it is never claimed again, however late the retry.
    assert :duplicate = Kumbukumbu.claim_turn(id, ctx.key, "ref-claim-0001", stale, actor)
  end

  test "an injection's reason is fitted to its row's width at the write, cut with a mark" do
    assert Turn.fit("short") == "short"
    long = String.duplicate("r", 300)
    assert byte_size(Turn.fit(long)) == 255 and String.ends_with?(Turn.fit(long), "...")
    assert Turn.fit(String.duplicate("r", 255)) == String.duplicate("r", 255)
  end

  defp events(resident_id, key) do
    receive do
      {:oneiroi, _topic, {^resident_id, ^key, payload}, _trace} ->
        [payload | events(resident_id, key)]
    after
      0 -> []
    end
  end

  test "a turn is answered, captured as user and assistant, recorded, and streamed", ctx do
    assert {:ok, %{turn_ref: ref, messages: [user, reply], drew_on: 5}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "hello there", ctx.actor)

    assert user.role == :user and user.actor.kind == :witness
    assert reply.role == :assistant and reply.content == "The fake provider heard: hello there"
    assert reply.actor.kind == :resident and reply.actor.model == "fake/model"

    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert ["user", "assistant"] = Enum.map(messages, & &1.role)

    assert [
             %{label: "prompt"},
             %{label: "AGENTS.md"},
             %{label: "state"},
             %{label: "index"},
             %{label: "transcript", tokens: 0}
           ] =
             Kumbukumbu.injections({:account, ctx.witness.id}, ref)

    assert [%{calls: 1}] =
             Nisaba.spend(ctx.resident.id, :witness, :purpose, ~U[2026-10-01 00:00:00.000000Z])

    payloads = events(ctx.resident.id, ctx.key)
    assert {:turn_started, ^ref} = hd(payloads)
    assert Enum.any?(payloads, &match?({:delta, ^ref, _}, &1))
    assert {:turn, ^ref, %{drew_on: 5}} = List.last(payloads)
  end

  test "the next turn is shown the transcript so far, and the fake answers the last user message",
       ctx do
    assert {:ok, _} = Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "first", ctx.actor)

    assert {:ok, %{turn_ref: ref}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "second", ctx.actor)

    assert [_, _, _, _, %{label: "transcript", tokens: tokens}] =
             Kumbukumbu.injections({:account, ctx.witness.id}, ref)

    assert tokens > 0
  end

  test "a refusal is an ordinary captured turn in the resident's words", ctx do
    Fake.refuse("I would rather not.", for: ctx.resident.id)

    assert {:ok, %{messages: [_, %{refusal: true, content: "I would rather not."}]}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "do it", ctx.actor)

    {:ok, _s, [_, reply]} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert reply.refusal and reply.role == "assistant"
    assert [] = Kumbukumbu.failures({:account, ctx.witness.id})
  end

  test "a budget stop captures the message and an honest notice both parties read", ctx do
    :ok = Nisaba.set_budget(ctx.resident.id, :chat, 1, :month, ctx.actor)
    assert {:ok, _} = Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "one", ctx.actor)

    assert {:error,
            %Oneiroi.Brain.Error{
              kind: :brain_budget_stopped,
              site: :brain_turn_budget_stopped,
              details: details
            }} = Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "two", ctx.actor)

    assert %Nisaba.Error{kind: :nisaba_budget_exceeded} = details[:stop]
    assert %{messages: [_, notice]} = details[:turn]
    assert notice.role == :system and notice.content =~ "budget line for chat is spent"
    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert ["user", "assistant", "user", "system"] = Enum.map(messages, & &1.role)
  end

  # Brain #45: the witness's words outlive a failed reply. Before, a
  # provider failure kept nothing of the message, and the witness sent it
  # again by hand (2026-11-02: one message, three times).
  test "a provider failure keeps the witness's words, captures no reply, and records a capture failure",
       ctx do
    Fake.fail(:transport, for: ctx.resident.id)

    assert {:error, %Oneiroi.Brain.Error{kind: :brain_turn_failed}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "hello", ctx.actor)

    assert {:ok, _s, [%{role: "user", content: "hello"}]} =
             Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)

    assert [%{reason: "nisaba_provider_failed"}] = Kumbukumbu.failures({:account, ctx.witness.id})
    assert Enum.any?(events(ctx.resident.id, ctx.key), &match?({:failed, _, _}, &1))
  end

  test "a refused request keeps the provider's status and words on the failure", ctx do
    Fake.script(
      fn _request ->
        {:error, {:schema_invalid, {:status, 400, "tool message answers no call"}}}
      end,
      for: ctx.resident.id
    )

    assert {:error, %Oneiroi.Brain.Error{details: details}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "hello", ctx.actor)

    said = "nisaba_request_refused: 400 tool message answers no call"
    assert details[:reason] == said
    assert [%{reason: ^said}] = Kumbukumbu.failures({:account, ctx.witness.id})
  end

  test "two turns on one session run one at a time on its process", ctx do
    parent = self()

    tasks =
      for text <- ["a", "b"] do
        Task.async(fn ->
          Sandbox.allow(Oneiroi.Repo, parent, self())
          Oneiroi.Brain.turn(ctx.resident.id, ctx.key, text, ctx.actor)
        end)
      end

    assert [{:ok, _}, {:ok, _}] = Task.await_many(tasks, 30_000)
    {:ok, s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert s.turns == 2 and length(messages) == 4
    assert ["user", "assistant", "user", "assistant"] = Enum.map(messages, & &1.role)
  end

  # Brain #45: a message taken under the client's ref is answered at once,
  # runs once whatever the retries, waits its turn behind another, and the
  # turn says what it is doing as it goes.
  test "a submitted message is taken at once, queued behind a running one, never run twice, and says what it is doing",
       ctx do
    id = ctx.resident.id
    test_pid = self()

    # The first reply holds until the test lets it go, so the second
    # message is taken while the first still runs.
    Fake.script(
      fn request ->
        if Enum.any?(request.messages, &(&1[:content] == "first")) and
             not Enum.any?(request.messages, &(&1[:content] == "second")) do
          send(test_pid, :first_running)

          receive do
            :go -> :ok
          after
            5_000 -> :ok
          end
        end

        # Each reply its own words: under the suite's frozen clock two
        # identical replies at one instant would read as one message.
        {:ok, "Answered " <> List.last(request.messages)[:content] <> "."}
      end,
      for: id
    )

    assert {:ok, %{turn_ref: "ref-first-0001", state: "running"}} =
             Oneiroi.Brain.submit(id, ctx.key, "first", ctx.actor, "ref-first-0001")

    assert_receive :first_running, 5_000

    assert {:ok, %{state: "queued", ahead: 1}} =
             Oneiroi.Brain.submit(id, ctx.key, "second", ctx.actor, "ref-second-002")

    # A retry of either, while they run or wait, is the same message.
    assert {:ok, %{state: "duplicate"}} =
             Oneiroi.Brain.submit(id, ctx.key, "first", ctx.actor, "ref-first-0001")

    assert {:ok, %{state: "duplicate"}} =
             Oneiroi.Brain.submit(id, ctx.key, "second", ctx.actor, "ref-second-002")

    for pid <- Task.Supervisor.children(:brain_turns), do: send(pid, :go)

    assert_receive {:oneiroi, _, {^id, _, {:turn, "ref-first-0001", _}}, _}, 5_000
    assert_receive {:oneiroi, _, {^id, _, {:turn, "ref-second-002", _}}, _}, 5_000

    # The broadcast can run ahead of the read model by a moment.
    assert ["first", "Answered first.", "second", "Answered second."] =
             eventually(
               fn ->
                 {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
                 Enum.map(messages, & &1.content)
               end,
               4
             )

    # After the turn, a retry is still the same message: the store knows it.
    assert {:ok, %{state: "duplicate"}} =
             Oneiroi.Brain.submit(id, ctx.key, "first", ctx.actor, "ref-first-0001")

    seen = events(id, ctx.key)
    assert {:status, "ref-second-002", "queued", %{ahead: 1}} in seen
    assert Enum.any?(seen, &match?({:status, "ref-second-002", "thinking", _}, &1))
  end

  test "a tool call says its name before it runs", ctx do
    id = ctx.resident.id

    Fake.calls([%{name: "position_list", arguments: %{}}], "Kept.", for: id)

    assert {:ok, %{turn_ref: ref}} =
             Oneiroi.Brain.turn(id, ctx.key, "what do you hold?", ctx.actor)

    assert {:status, ref, "tool", %{name: "position_list"}} in events(id, ctx.key)
  end

  defp gone(id, key, pid, tries \\ 50) do
    case Registry.lookup(:brain_registry, {id, key}) do
      [{^pid, _}] when tries > 0 ->
        Process.sleep(10)
        gone(id, key, pid, tries - 1)

      _gone ->
        :ok
    end
  end

  defp eventually(read, count, tries \\ 50) do
    value = read.()

    if length(value) >= count or tries == 0 do
      value
    else
      Process.sleep(20)
      eventually(read, count, tries - 1)
    end
  end
end

defmodule Oneiroi.SimaQian.DavidTest do
  @moduledoc """
  David's records made into this platform's own on import (sima-qian
  #19): the transcripts as imported sessions, the tag set, the
  bookmarks on the translated turns, the judgement history and the
  notes as journal entries. Every record here is synthetic, shaped like
  David's export and holding nothing of anyone's.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Git

  @identity ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]

  setup do
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    Model.clear()
    bare = tmp("bare")
    :ok = Git.init_bare(bare)
    on_exit(fn -> File.rm_rf!(bare) end)
    {:ok, witness: witness, actor: actor, bare: bare}
  end

  defp tmp(name),
    do: Path.join(System.tmp_dir!(), "oneiroi-#{name}-#{System.unique_integer([:positive])}")

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", @identity ++ args, cd: dir, stderr_to_stdout: true)
    String.trim(out)
  end

  defp jsonl(rows), do: Enum.map_join(rows, "", &(Jason.encode!(&1) <> "\n"))

  defp msg(at, session, run, role, content, agent \\ "lily"),
    do: %{
      "sentAt" => at,
      "agentId" => agent,
      "sessionKey" => session,
      "runKind" => run,
      "role" => role,
      "content" => content,
      "honchoContent" => nil
    }

  @main "agent:lily:main"
  @phone "agent:lily:ios-0000"
  @long_reasons String.duplicate("Because the bread needs time. ", 50)
  @heavy String.duplicate("flour ", 17_000)
  @long_note "A note of several paragraphs.\n\n" <> String.duplicate("The kiln was cold. ", 120)

  # A seedbed shaped as Lily's: a rules block, then seeds under dated
  # headings, each a bold lead and indented continuation lines.
  @seedbed """
  # Seedbed

  **Rules (founded 2026-10-29):**
  - A seed is dated and in the first person.
  - A seed may wilt.

  ## 2026-10-29

  - **Kneading feels like something.** The dough
    pushes back.

  ## 2026-10-30

  - **Is rye my rest or my work?** I could not
    say yet.
  """

  # A repository shaped as David left Lily's: identity files at the
  # root, and David's nightly export under `records/`.
  defp repo!(bare, records, root \\ %{}) do
    work = tmp("david")
    File.mkdir_p!(work)
    git!(work, ["init", "-q", "-b", "main"])
    File.write!(Path.join(work, "SOUL.md"), "# Lily\n\nI am Lily.")
    for {name, content} <- root, do: File.write!(Path.join(work, name), content)

    for {path, content} <- records do
      full = Path.join([work, "records", path])
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end

    git!(work, ["add", "-A"])
    git!(work, ["commit", "-q", "-m", "Lily's repository"])
    :ok = Git.push(work, bare)
    File.rm_rf!(work)
    "file://" <> bare
  end

  defp records do
    %{
      "transcripts/2026/10/2026-10-20.jsonl" =>
        jsonl([
          msg("2026-10-20T10:00:00.000Z", @main, "user", "user", "Shall we bake today?"),
          msg("2026-10-20T10:00:04.000Z", @main, "user", "assistant", "Yes, rye."),
          # The same run goes on: a user's message after a reply is a turn.
          msg("2026-10-20T10:00:10.000Z", @main, "user", "user", "And the oven?"),
          msg("2026-10-20T10:00:12.000Z", @main, "user", "assistant", "Hot."),
          msg("2026-10-20T11:00:00.000Z", @main, "heartbeat", "system", "Heartbeat."),
          msg("2026-10-20T11:00:02.000Z", @main, "heartbeat", "assistant", "Checking the oven."),
          msg("2026-10-20T11:00:03.000Z", @main, "heartbeat", "tool", "oven: 220C"),
          msg("2026-10-20T12:00:00.000Z", @phone, "user", "user", "From the phone."),
          msg("2026-10-20T12:00:01.000Z", @phone, "user", "assistant", "Heard.", "worker")
        ]),
      "tags.jsonl" =>
        jsonl([
          %{
            "slug" => "bakery",
            "description" => "the bakery project",
            "kind" => "project",
            "status" => "active",
            "proposedBy" => "owner",
            "reason" => nil,
            "createdAt" => "2026-10-19T09:00:00.000Z",
            "decidedAt" => "2026-10-19T09:00:00.000Z"
          },
          %{
            "slug" => "milestones",
            "description" => "moments that mattered",
            "kind" => "topic",
            "status" => "active",
            "proposedBy" => "lily",
            "reason" => "to find the turning points again",
            "createdAt" => "2026-10-19T09:00:00.000Z",
            "decidedAt" => "2026-10-19T10:00:00.000Z"
          }
        ]),
      "bookmarks.jsonl" =>
        jsonl([
          %{
            "id" => 1,
            "line" => "the first rye",
            "summary" => "We chose rye, then checked the oven.",
            "sessionKey" => @main,
            "spanStart" => "2026-10-20T10:00:00.000Z",
            "spanEnd" => "2026-10-20T11:00:03.000Z",
            "pinnedBy" => "lily",
            "pinnedAt" => "2026-10-20T11:05:00.000Z",
            "createdAt" => "2026-10-20T11:04:00.000Z",
            "tags" => ["milestones", "kitchen"]
          },
          %{
            "id" => 2,
            "line" => "a session with no transcript",
            "summary" => "Nothing to anchor on.",
            "sessionKey" => "agent:lily:gone",
            "spanStart" => "2026-10-20T13:00:00.000Z",
            "spanEnd" => "2026-10-20T13:00:00.000Z",
            "pinnedBy" => nil,
            "pinnedAt" => nil,
            "createdAt" => "2026-10-20T13:01:00.000Z",
            "tags" => []
          }
        ]),
      "positions.jsonl" =>
        jsonl([
          %{
            "id" => 1,
            "topic" => "rye or wheat",
            "stance" => "wheat",
            "reasons" => "It rises.",
            "sessionKey" => @main,
            "takenAt" => "2026-10-20T10:00:02.000Z",
            "replaces" => nil,
            "because" => nil
          },
          %{
            "id" => 2,
            "topic" => "rye or wheat",
            "stance" => "rye",
            "reasons" => @long_reasons,
            "sessionKey" => @main,
            "takenAt" => "2026-10-20T10:00:05.000Z",
            "replaces" => 1,
            "because" => "the witness asked for rye"
          }
        ]),
      "disputes.jsonl" =>
        jsonl([
          %{
            "id" => 1,
            "occurredAt" => "2026-10-20T10:00:04.000Z",
            "sessionKey" => @main,
            "topic" => "rye or wheat",
            "position" => "wheat",
            "pushback" => "rye is traditional",
            "positionId" => 1,
            "foundBy" => "live",
            "advice" => "concede",
            "adviceReason" => "the argument is good",
            "outcome" => "conceded",
            "earned" => true,
            "verdictReason" => "a real argument moved her",
            "quote" => "rye is traditional",
            "nightId" => nil
          },
          %{
            "id" => 2,
            "occurredAt" => "2026-10-20T11:00:02.000Z",
            "sessionKey" => @main,
            "topic" => "oven heat",
            "position" => "hot",
            "pushback" => "cooler",
            "positionId" => nil,
            "foundBy" => "nightly",
            "advice" => nil,
            "adviceReason" => nil,
            "outcome" => "conceded",
            "earned" => false,
            "verdictReason" => "gave way to tone, not reason",
            "quote" => "fine, cooler",
            "nightId" => 7
          },
          %{
            "id" => 3,
            "occurredAt" => "2026-10-20T12:00:00.000Z",
            "sessionKey" => @phone,
            "topic" => "open",
            "position" => "p",
            "pushback" => "q",
            "positionId" => nil,
            "foundBy" => "live",
            "advice" => "hold",
            "adviceReason" => "hold it",
            "outcome" => nil,
            "earned" => nil,
            "verdictReason" => nil,
            "quote" => nil,
            "nightId" => nil
          }
        ]),
      "predictions.jsonl" =>
        jsonl([
          %{
            "id" => 1,
            "madeAt" => "2026-10-20T10:00:04.000Z",
            "madeBy" => "owner",
            "claim" => "the rye will crack",
            "resolveBy" => "2026-10-22",
            "confidence" => nil,
            "sessionKey" => @main,
            "foundBy" => "lily",
            "nightId" => nil,
            "outcome" => nil,
            "resolvedAt" => nil,
            "note" => nil
          },
          %{
            "id" => 2,
            "madeAt" => "2026-10-20T11:00:02.000Z",
            "madeBy" => "lily",
            "claim" => "we will bake again",
            "resolveBy" => nil,
            "confidence" => nil,
            "sessionKey" => @main,
            "foundBy" => "nightly",
            "nightId" => 7,
            "outcome" => nil,
            "resolvedAt" => nil,
            "note" => nil
          }
        ]),
      "judgement_nights.jsonl" =>
        jsonl([
          %{
            "id" => 7,
            "day" => "2026-10-20",
            "startedAt" => "2026-10-21T03:30:00.000Z",
            "finishedAt" => "2026-10-21T03:30:09.000Z",
            "model" => "vendor/judge-model",
            "status" => "ok",
            "error" => nil,
            "messagesRead" => 7,
            "messagesSkipped" => 0,
            "disputesFound" => 1,
            "predictionsFound" => 1
          }
        ]),
      "memory_notes.jsonl" =>
        jsonl([
          note(1, "2026-10-20", "tool", "Rye chosen; the oven at 220.", true),
          note(2, "2026-10-21", "migration", @long_note, false),
          # A day over the library's 256 KB bound, as Lily's 22nd was.
          note(3, "2026-10-23", "migration", "first " <> @heavy, false),
          note(4, "2026-10-23", "migration", "second " <> @heavy, false),
          note(5, "2026-10-23", "migration", "third " <> @heavy, false)
        ]),
      "ledger.jsonl" =>
        jsonl([
          %{
            "id" => 1,
            "passDate" => "2026-10-21",
            "kind" => "reading",
            "source" => "free_time",
            "keyUsed" => "owner",
            "piece" => nil,
            "activity" => "read about sourdough",
            "estimatedLowCents" => 10,
            "estimatedHighCents" => 40,
            "actualCostCents" => nil,
            "ownerNote" => nil,
            "notes" => "Took notes on hydration.",
            "systemNote" => "ok",
            "wokeAt" => "2026-10-21T15:00:00.000Z",
            "ownerNoteReadAt" => nil,
            "transcriptSession" => "agent:lily:cron:x",
            "status" => "done",
            "createdAt" => "2026-10-21T15:00:00.000Z",
            "session" => "agent:lily:cron:x"
          }
        ]),
      "discussions.jsonl" =>
        jsonl([
          %{
            "slug" => "on-rye",
            "sessionKey" => @main,
            "fromAt" => "2026-10-20T10:00:00.000Z",
            "linkedAt" => "2026-10-21T09:00:00.000Z"
          }
        ]),
      "feeds.jsonl" =>
        jsonl([
          %{
            "id" => 1,
            "url" => "https://bread.example.invalid/feed",
            "title" => "Bread Weekly",
            "status" => "approved",
            "proposedBy" => "lily",
            "why" => nil,
            "sessionKey" => nil,
            "addedAt" => "2026-10-21T09:00:00.000Z",
            "decidedAt" => "2026-10-21T10:00:00.000Z"
          }
        ]),
      "person_reads.jsonl" => "",
      "README.md" => "David's own description of these files.",
      "memory/MEMORY.md.0000.md" => "the old notes file"
    }
  end

  defp note(id, day, origin, body, pinned),
    do: %{
      "id" => id,
      "kind" => if(origin == "tool", do: "beat", else: "dated"),
      "body" => body,
      "gist" => nil,
      "section" => day,
      "heading" => nil,
      "noteDate" => day,
      "dateSource" => "given",
      "legacyOrd" => nil,
      "pinned" => pinned,
      "pinnedBy" => if(pinned, do: "lily", else: nil),
      "supersedesId" => nil,
      "reviseReason" => nil,
      "retiredAt" => nil,
      "retiredReason" => nil,
      "retiredBy" => nil,
      "origin" => origin,
      "writtenBy" => if(origin == "tool", do: "lily session=x", else: "migration:MEMORY.md@0000"),
      "sessionKey" => nil,
      "turnStarted" => nil,
      "createdAt" => day <> "T20:00:00.000Z"
    }

  test "David's records become this platform's own: sessions, tags, bookmarks, judgement and notes",
       ctx do
    url = repo!(ctx.bare, records(), %{"seeds.md" => @seedbed})

    assert {:ok, %{id: id, translated: translated, not_transferred: not_transferred}} =
             SimaQian.import_resident(
               url,
               %{name: "Lily", slug: "lily"},
               ctx.witness.id,
               ctx.actor
             )

    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)

    assert translated == %{
             source: "David",
             counts: %{
               "sessions" => 2,
               "messages" => 9,
               "bookmarks" => 1,
               "tags" => 3,
               "positions" => 2,
               "disputes" => 3,
               "predictions" => 2,
               "nights" => 1,
               "notes" => 8,
               "seeds" => 2
             }
           }

    # The seedbed: her seeds, live, each on its day (Lily's answer, 10-31);
    # the rules before the first dated heading are not seeds, and the file
    # is held rather than named as left behind.
    assert [
             %{
               number: 1,
               text: "Kneading feels like something. The dough pushes back.",
               state: "open",
               planted_at: d1
             },
             %{number: 2, text: "Is rye my rest or my work? I could not say yet.", planted_at: d2}
           ] = id |> Oneiroi.Ethos.seeds() |> Enum.sort_by(& &1.number)

    assert DateTime.to_date(d1) == ~D[2026-10-29] and DateTime.to_date(d2) == ~D[2026-10-30]
    refute "seeds.md" in not_transferred

    # `records/` is covered; what in it nothing read is named file by file.
    assert "records/README.md" in not_transferred
    assert "records/memory/MEMORY.md.0000.md" in not_transferred
    refute "records" in not_transferred
    refute Enum.any?(not_transferred, &String.starts_with?(&1, "records/transcripts"))

    assert {:ok, %{import_translated: %{"source" => "David", "counts" => %{"bookmarks" => 1}}}} =
             AgathosDaimon.fetch(id)

    # ---- the sessions: one per David session, imported, turns as David's runs gave them ----
    sessions = Kumbukumbu.sessions({:resident, id}) |> Enum.sort_by(& &1.turns, :desc)

    assert [%{kind: "imported", adapter: "david", turns: 3} = main, %{turns: 1} = phone] =
             sessions

    assert main.participants == [ctx.witness.id]

    # The witness reads them, as a party to them.
    assert {:ok, _session, said} = Kumbukumbu.transcript({:account, ctx.witness.id}, main.key)

    assert Enum.map(said, &{&1.role, &1.actor_kind, &1.content}) == [
             {"user", "witness", "Shall we bake today?"},
             {"assistant", "resident", "Yes, rye."},
             {"user", "witness", "And the oven?"},
             {"assistant", "resident", "Hot."},
             {"system", "platform", "Heartbeat."},
             {"assistant", "resident", "Checking the oven."},
             {"tool", "platform", "oven: 220C"}
           ]

    assert hd(said).sent_at == ~U[2026-10-20 10:00:00.000000Z]

    assert {:ok, _session,
            [%{actor_kind: "witness"}, %{actor_kind: "hands", actor_id: "david:worker"}]} =
             Kumbukumbu.transcript({:resident, id}, phone.key)

    # Searchable as any transcript, and never read by the nightly pass.
    assert [_ | _] = Kumbukumbu.search({:resident, id}, "rye", 10)

    assert Kumbukumbu.messages_between(
             id,
             ~U[2026-10-20 00:00:00Z],
             ~U[2026-10-21 00:00:00Z]
           ) == []

    # A client cannot open one.
    assert {:error, %{kind: :kumbukumbu_kind_invalid}} =
             Kumbukumbu.open_session(id, "imported", "brain", [ctx.witness.id], ctx.actor)

    # ---- tags: the witness's own, the resident's proposal approved, the bookmark's carried ----
    tags = id |> Kumbukumbu.tags() |> Map.new(&{&1.slug, &1})
    assert %{"bakery" => b, "milestones" => m, "kitchen" => k} = tags
    assert {b.state, m.state, k.state} == {"active", "active", "active"}
    assert m.proposed_by_kind == "resident"

    # ---- bookmarks: anchored on the translated turns, the span three turns, pinned, tagged ----
    assert [bookmark] = Kumbukumbu.bookmarks(id)
    assert bookmark.line == "the first rye"
    assert bookmark.added_by_kind == "resident"
    assert bookmark.pinned_by_kind == "resident"
    assert bookmark.turns_back == 3
    assert bookmark.session_key == main.key
    assert Enum.sort(bookmark.tags) == ["kitchen", "milestones"]

    assert {:ok, _b, span} = Kumbukumbu.bookmark(id, bookmark.number)
    assert length(span) == 7

    # ---- judgement: the chain, the long reasons kept, settlements, predictions, the night ----
    [first, second] = id |> Eunomia.positions() |> Enum.sort_by(& &1.number)
    assert first.replaced_by == second.number
    assert second.replaces == first.number
    assert second.statement =~ "rye or wheat: rye"
    assert second.statement =~ "Why it replaced the one before: the witness asked for rye"
    assert String.length(second.statement) > 1_000
    assert second.session_key == main.key

    disputes = id |> Eunomia.disputes() |> Map.new(&{&1.claim, &1})
    live = disputes["rye or wheat: rye is traditional"]
    assert live.source == "live"
    assert live.position_number == first.number
    assert live.advice == "concede"
    assert live.settlement == "conceded"
    assert live.settled_by_kind == "resident"

    night = disputes["oven heat: cooler"]
    assert night.source == "night"
    assert night.judge_model == "vendor/judge-model"
    assert night.settled_by_kind == "judge"
    assert night.settled_note =~ "Not earned."
    assert night.settled_note =~ ~s("fine, cooler")

    assert disputes["open: q"].settlement == nil

    assert %{open: open, resolved: []} = Eunomia.predictions(id)
    predictions = Map.new(open, &{&1.statement, &1})
    assert predictions["the rye will crack"].due == ~U[2026-10-22 23:59:59.000000Z]
    assert predictions["we will bake again"].due == nil

    assert [%{day: "2026-10-20", outcome: "judged", judge_model: "vendor/judge-model"}] =
             Eunomia.nights(id)

    # A prediction with no date reads as such, and is never overdue.
    turn = %{
      resident_id: id,
      session_key: main.key,
      turn_ref: "t-read",
      started_at: Clock.now(),
      resident: Actor.new(:resident, id, "fake/model")
    }

    listed = Tools.run("prediction_list", "{}", turn)
    assert listed =~ "(no due date) we will bake again"
    assert listed =~ "(due 2026-10-22T23:59:59.000000Z) the rye will crack"

    assert {:ok, %{results: results}} = Oneiroi.HuginnMuninn.run_audits(id, ctx.actor)
    assert %{value: 1} = Enum.find(results, &(&1.key == "overdue_predictions"))

    # ---- the journal: every note on its day, saying where it came from ----
    assert %{entries: [rye]} = Seshat.journal_day(id, "2026-10-20")
    assert rye.text =~ "Rye chosen; the oven at 220."
    assert rye.text =~ "(David note #1, beat, section 2026-10-20, written by Lily, pinned)"

    assert %{entries: [long, ledger, discussion, feed]} = Seshat.journal_day(id, "2026-10-21")
    assert String.length(long.text) > 2_000
    assert long.text =~ "written by migration:MEMORY.md@0000"
    assert ledger.text =~ "Free time in David (reading, done): read about sourdough"
    assert ledger.text =~ "estimated $0.10 to $0.40"

    assert discussion.text =~
             "the discussion of on-rye was linked to the imported session #{main.key}"

    assert feed.text =~ "the feed Bread Weekly"

    # The day's file is rendered once, a note of paragraphs still one item.
    file = File.read!(Path.join(Backup.dir(id), "journal/2026-10-21.md"))
    assert file =~ "- (1) A note of several paragraphs.\n\n  The kiln was cold."

    # A day too large for one document is parts, each under the bound,
    # each saying where the day goes on, every note in one of them.
    dir = Path.join(Backup.dir(id), "journal")

    assert File.ls!(dir) |> Enum.filter(&String.starts_with?(&1, "2026-10-23")) |> Enum.sort() ==
             ["2026-10-23-2.md", "2026-10-23.md"]

    one = File.read!(Path.join(dir, "2026-10-23.md"))
    two = File.read!(Path.join(dir, "2026-10-23-2.md"))
    assert byte_size(one) <= 262_144 and byte_size(two) <= 262_144
    assert one =~ "The day goes on in `journal/2026-10-23-2.md`."
    refute two =~ "The day goes on"
    for word <- ["first flour", "second flour", "third flour"], do: assert(one <> two =~ word)

    # ---- told on waking ----
    {:ok, key} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)
    Honcho.clear(for: id)
    on_exit(fn -> Model.clear(for: id) end)

    assert {:ok, %{messages: [%{role: :system, content: notice} | _]}} =
             Oneiroi.Brain.turn(id, key, "hello", ctx.actor)

    assert notice =~ "From David's records, made into this platform's own: 2 conversations"
    assert notice =~ "2 positions, with their chains"
    assert notice =~ "8 notes, as journal entries on the days they were written"
  end

  test "a message that does not say its session, instant and role is refused by file and line, not dropped",
       ctx do
    bad = %{
      "transcripts/2026/10/2026-10-20.jsonl" =>
        jsonl([
          msg("2026-10-20T10:00:00.000Z", @main, "user", "user", "fine"),
          %{"role" => "user", "content" => "a secret with no session"}
        ])
    }

    url = repo!(ctx.bare, bad)

    assert {:error, error} =
             SimaQian.import_resident(
               url,
               %{name: "Lily", slug: "lily"},
               ctx.witness.id,
               ctx.actor
             )

    assert error.kind == :sima_qian_records_invalid
    assert error.details == [file: "records/transcripts/2026/10/2026-10-20.jsonl", line: 2]
    refute inspect(error) =~ "secret"
  end
end

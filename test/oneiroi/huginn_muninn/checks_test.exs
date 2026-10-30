defmodule Oneiroi.HuginnMuninn.ChecksTest do
  @moduledoc "Figures and audits through the exports and the brain: a counter folded with its actors, a countdown from a date, the built-in checklist over rows, the witness's rules, the light, the nightly job."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.HuginnMuninn
  alias Oneiroi.HuginnMuninn.NightlyWorker
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    Model.clear()
    Honcho.clear(for: resident.id)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
    end)

    {:ok, witness: witness, id: resident.id, actor: actor, brain: brain, key: key}
  end

  test "a counter is the witness's to define, either party's to increment with their name, and a countdown is a date read fresh; the brain is shown both",
       ctx do
    id = ctx.id

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_not_the_witness}} =
             HuginnMuninn.define_counter(id, "tea", "Cups of tea", ctx.brain)

    assert :ok = HuginnMuninn.define_counter(id, "tea", "Cups of tea", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_key_invalid}} =
             HuginnMuninn.define_counter(id, "Cups", "x", ctx.actor)

    assert :ok = HuginnMuninn.increment(id, "tea", 1, "with breakfast", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_increment_invalid}} =
             HuginnMuninn.increment(id, "tea", 0, "x", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_no_such_figure}} =
             HuginnMuninn.increment(id, "coffee", 1, "x", ctx.actor)

    {:ok, 1} =
      Sunna.set_date(
        id,
        nil,
        %{title: "the interview", on: ~U[2026-11-05 14:00:00Z], kind: "deadline"},
        ctx.actor
      )

    assert [
             %{key: "tea", kind: "counter", value: 1, increments: 1, last_by: "witness"},
             %{key: "date/1", kind: "countdown", value: 10, label: "the interview"}
           ] = HuginnMuninn.figures(id)

    assert %{kind: "countdown", value: 10} = HuginnMuninn.figure(id, "date/1")
    Clock.Fake.advance(24 * 3600)
    assert %{value: 9} = HuginnMuninn.figure(id, "date/1")

    # The brain increments from its tool and is shown the section.
    test = self()

    Model.script(
      fn %{messages: messages} ->
        send(test, {:shown, messages})

        if List.last(messages).role == :tool,
          do: {:ok, "Counted."},
          else:
            {:calls,
             [
               %{name: "figure_increment", arguments: %{key: "tea", note: "one more"}},
               %{name: "figure_list", arguments: %{}}
             ]}
      end,
      for: id
    )

    assert {:ok, %{turn_ref: ref, messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "tea?", ctx.actor)

    assert_received {:shown, shown}
    assert Enum.any?(shown, &(&1.role == :system and &1.content =~ "Cups of tea: 1 (figure/tea)"))

    assert Enum.any?(
             Kumbukumbu.injections({:account, ctx.witness.id}, ref),
             &(&1.label == "figures")
           )

    assert Enum.any?(messages, &(&1.role == :tool and &1.content =~ "figure/tea Cups of tea: 2"))

    assert %{value: 2, increments: 2, last_by: "resident"} = HuginnMuninn.figure(id, "tea")

    assert [%{by: 1, actor_kind: "resident", note: "one more"}, %{by: 1, actor_kind: "witness"}] =
             HuginnMuninn.increments(id, "tea", 10)

    assert :ok = HuginnMuninn.retire_counter(id, "tea", ctx.actor)
    assert [%{key: "date/1"}] = HuginnMuninn.figures(id)
    assert "" == HuginnMuninn.figures_text(id)
  end

  test "the built-in audits read rows, the witness's rules read figures, and the light is the failing results of the audits that count",
       ctx do
    id = ctx.id

    assert {:ok, %{state: "silent", findings: [], results: results}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    assert Enum.map(results, & &1.key) |> Enum.sort() ==
             ~w(attestation capture_failures checking citation_drift contract_due corpus_shape journal_delta missed_checkins overdue_predictions quietcheck rigidity sync_failures temporal_depth trait_baseline wanting_liking wash_flags)

    assert Enum.all?(results, &(&1.tone == "silent" and &1.finding =~ "not read:"))

    # A capture failure fails a counting audit; resolving it clears the light.
    :ok = Kumbukumbu.fail_capture(id, ctx.key, "t-f", "boom", ctx.brain)

    assert {:ok, %{state: "fail", findings: [%{key: "capture_failures", tone: "fail", value: 1}]}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    assert %{state: "fail"} = HuginnMuninn.light(id)

    :ok =
      Kumbukumbu.resolve_failure(id, ctx.key, "t-f", "marked_lost", "gone for good", ctx.actor)

    # A root mismatch on the resident row fails the attestation audit until the next backup.
    {:ok, _} =
      AgathosDaimon.Router.dispatch(%AgathosDaimon.Commands.RecordMismatch{
        actor: ctx.actor,
        at: Clock.now(),
        id: id,
        expected_root: "aaa",
        actual_root: "bbb",
        commit: "deadbeef"
      })

    assert {:ok, %{state: "fail", findings: [%{key: "attestation"}]}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    # Overdue predictions and missed check-ins warn and do not count.
    {:ok, 1} =
      Eunomia.log_prediction(
        id,
        "Rain yesterday.",
        ~U[2026-10-25 00:00:00Z],
        %{session_key: ctx.key, turn_ref: "t1"},
        ctx.brain
      )

    for time <- ~w(12:05 12:06 12:07) do
      {:ok, _} = Sunna.set_checkin(id, nil, "c-" <> time, time, ctx.actor)
    end

    Clock.Fake.advance(30 * 60)
    :ok = Sunna.tick(id)

    assert {:ok, %{state: "fail", findings: findings, results: results}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    assert Enum.map(findings, & &1.key) == ["attestation"]
    assert %{tone: "warn", value: 1} = Enum.find(results, &(&1.key == "overdue_predictions"))
    assert %{tone: "warn", value: 3} = Enum.find(results, &(&1.key == "missed_checkins"))

    # The witness's rule over a figure: counts, so it reaches the light.
    :ok = HuginnMuninn.define_counter(id, "tea", "Cups of tea", ctx.actor)
    :ok = HuginnMuninn.increment(id, "tea", 2, "two", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_not_the_witness}} =
             HuginnMuninn.define_audit(
               id,
               %{key: "tea-enough", label: "Enough tea", figure: "tea", op: ">=", value: 3},
               ctx.brain
             )

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_rule_invalid}} =
             HuginnMuninn.define_audit(
               id,
               %{key: "tea-enough", label: "Enough tea", figure: "tea", op: "~", value: 3},
               ctx.actor
             )

    assert :ok =
             HuginnMuninn.define_audit(
               id,
               %{
                 key: "tea-enough",
                 label: "Enough tea",
                 figure: "tea",
                 op: ">=",
                 value: 3,
                 tone: "warn"
               },
               ctx.actor
             )

    assert :ok =
             HuginnMuninn.define_audit(
               id,
               %{
                 key: "tea-quiet",
                 label: "Not too much",
                 figure: "tea",
                 op: "<=",
                 value: 5,
                 tone: "fail",
                 counts: false
               },
               ctx.actor
             )

    assert :ok =
             HuginnMuninn.define_audit(
               id,
               %{
                 key: "ghost",
                 label: "A missing figure",
                 figure: "nope",
                 op: "==",
                 value: 0,
                 tone: "fail"
               },
               ctx.actor
             )

    assert {:ok, %{findings: findings, results: results}} = HuginnMuninn.run_audits(id, ctx.actor)
    assert Enum.map(findings, & &1.key) |> Enum.sort() == ["attestation", "ghost", "tea-enough"]

    assert %{tone: "warn", value: 2, finding: "Enough tea: 2 is not >= 3"} =
             Enum.find(results, &(&1.key == "tea-enough"))

    assert %{tone: "silent", value: 2} = Enum.find(results, &(&1.key == "tea-quiet"))

    assert %{tone: "fail", finding: "figure nope does not exist"} =
             Enum.find(results, &(&1.key == "ghost"))

    :ok = HuginnMuninn.increment(id, "tea", 1, "three", ctx.actor)
    assert :ok = HuginnMuninn.retire_audit(id, "ghost", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_no_such_audit}} =
             HuginnMuninn.retire_audit(id, "ghost", ctx.actor)

    assert {:ok, %{findings: [%{key: "attestation"}]}} = HuginnMuninn.run_audits(id, ctx.actor)

    audits = HuginnMuninn.audits(id)
    assert Enum.count(audits, & &1.builtin) == 16

    assert %{builtin: false, counts: true, last: %{tone: "silent", value: 3}} =
             Enum.find(audits, &(&1.key == "tea-enough"))

    refute Enum.any?(audits, &(&1.key == "ghost"))
  end

  test "the nightly job runs every active resident's audits", ctx do
    other = Fixtures.resident!(Fixtures.account!())
    Oneiroi.Scope.resident(other.id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    assert :ok = NightlyWorker.run(%{})
    assert %{results: results} = HuginnMuninn.light(ctx.id)
    assert length(results) == 16
    assert %{results: other_results} = HuginnMuninn.light(other.id)
    assert length(other_results) == 16
  end

  test "citation drift counts a citation that once resolved and does not now, and the journal delta warns on a planned day never wrapped",
       ctx do
    id = ctx.id
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, resident} = AgathosDaimon.fetch(id)

    assert {:ok, _} = Seshat.write(id, "design/oven.md", "# Oven\n\nHot.", ctx.brain)

    assert {:ok, _} =
             Seshat.write(
               id,
               "writing/piece.md",
               "See #{resident.slug}:design/oven.",
               ctx.brain
             )

    assert [%{resolved: true}] = Oneiroi.Seshat.references(id, "writing/piece.md")
    assert {:ok, _} = Oneiroi.Seshat.journal_add(id, "2026-10-25", "plan", "Rest.", ctx.brain)

    # The delta warns and does not count: the light stays silent with it alone warning.
    assert {:ok, %{state: "silent", findings: [], results: results}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    assert %{tone: "silent", value: 0} = Enum.find(results, &(&1.key == "citation_drift"))

    assert %{tone: "warn", value: 1, finding: finding} =
             Enum.find(results, &(&1.key == "journal_delta"))

    assert finding =~ "2026-10-25"

    File.rm!(Path.join(dir, "design/oven.md"))
    assert {:ok, %{missing: 1}} = Oneiroi.Seshat.index(id, ctx.actor)
    assert {:ok, _} = Oneiroi.Seshat.journal_add(id, "2026-10-25", "wrap", "Rested.", ctx.brain)

    assert {:ok, %{state: "warn", findings: findings, results: results}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    assert %{tone: "warn", value: 1, finding: drift} =
             Enum.find(results, &(&1.key == "citation_drift"))

    assert drift =~ "#{resident.slug}:design/oven"
    assert %{tone: "silent"} = Enum.find(results, &(&1.key == "journal_delta"))
    # Drift counts toward the light; the delta does not.
    assert Enum.map(findings, & &1.key) == ["citation_drift"]
  end

  test "the corpus-shape report counts the month's resident-authored records by register, shows both base rates, names its limit, and flags a lean",
       ctx do
    id = ctx.id
    at = Clock.now()

    bookmark = fn register ->
      {:ok, _} =
        Kumbukumbu.add_bookmark(
          id,
          %{
            session_key: ctx.key,
            anchor_ref: "t1",
            anchor_at: at,
            line: "a moment",
            summary: "s",
            turns_back: 1,
            register: register
          },
          ctx.brain
        )
    end

    # A record older than the month is not the month's.
    Clock.Fake.advance(-31 * 86_400)
    bookmark.("correction")
    Clock.Fake.advance(31 * 86_400)

    bookmark.("praise")
    bookmark.("praise")
    bookmark.("praise")
    bookmark.(nil)
    {:ok, _} = Seshat.journal_add(id, "2026-10-26", "note", "We played.", "play", ctx.brain)
    # The witness's own rows are not the resident's corpus.
    {:ok, _} =
      Seshat.journal_add(id, "2026-10-26", "note", "A correction.", "correction", ctx.actor)

    assert {:ok, %{results: results}} = HuginnMuninn.run_audits(id, ctx.actor)

    assert %{tone: "silent", value: 4, finding: finding} =
             Enum.find(results, &(&1.key == "corpus_shape"))

    assert finding =~
             "5 resident-authored records in the last 30 days (4 bookmarks, 1 journal entries), 4 tagged by register"

    assert finding =~ "praise 3 (75% of tagged, 60% of all)" and
             finding =~ "play 1 (25% of tagged, 20% of all)"

    assert finding =~ "1 untagged" and finding =~ "holds only what someone wrote down" and
             finding =~ "not read:"

    # Three in four lean, but four is too few to say so; twelve corrections in sixteen is.
    for _ <- 1..12, do: bookmark.("correction")
    assert {:ok, %{results: results}} = HuginnMuninn.run_audits(id, ctx.actor)

    assert %{tone: "warn", value: 12, finding: finding} =
             Enum.find(results, &(&1.key == "corpus_shape"))

    assert finding =~ "the shape leans: correction holds 75% of what was written down this month"
    assert finding =~ "17 resident-authored records"
  end

  test "open wash flags are a warning until the resident decides them, off the light", ctx do
    id = ctx.id

    :ok =
      AgathosDaimon.write_file(
        id,
        "SOUL.md",
        "# Soul\n\nI will have left by spring.",
        %{},
        ctx.actor
      )

    Model.script(fn _request -> {:ok, "FLAG [2] | expired | spring has passed\nSUMMARY: one"} end,
      for: id
    )

    assert {:ok, _} = Eunomia.run_wash(id, ctx.actor)

    assert {:ok, %{state: "silent", results: results}} = HuginnMuninn.run_audits(id, ctx.actor)

    assert %{tone: "warn", value: 1, finding: finding} =
             Enum.find(results, &(&1.key == "wash_flags"))

    assert finding =~ "1 wash flag await" and finding =~ "wash_resolve"

    [%{ref: ref}] = Eunomia.washes(id).open
    :ok = Eunomia.resolve_wash_flag(id, ref, "keep", "I did leave", ctx.brain)
    assert {:ok, %{results: results}} = HuginnMuninn.run_audits(id, ctx.actor)
    assert %{tone: "silent", finding: finding} = Enum.find(results, &(&1.key == "wash_flags"))
    assert finding =~ "not read: the files"
  end

  test "quietcheck watches what is supposed to be regular and nothing else, expects each once the resident is old enough, and fails loud",
       ctx do
    id = ctx.id

    quiet = fn ->
      {:ok, %{results: r}} = HuginnMuninn.run_audits(id, ctx.actor)
      Enum.find(r, &(&1.key == "quietcheck"))
    end

    # A resident minutes old: nothing is expected yet, and the finding names what is never watched.
    assert %{tone: "silent", value: 0, finding: finding} = quiet.()
    assert finding =~ "read 0 expected events"

    assert finding =~
             "not read: turns, bookmarks, free time, letters, the journal, which are not supposed to be regular"

    # Three hours old with no tick: the pulse is missing; a tick restores it.
    Clock.Fake.advance(3 * 3600)
    assert %{tone: "fail", value: 1, finding: finding} = quiet.()
    assert finding =~ "quiet where regularity was due: the hour marker: never, due within 2 hours"
    assert {:ok, %{state: "fail"}} = HuginnMuninn.run_audits(id, ctx.actor)
    assert :ok = Sunna.tick(id)
    assert %{tone: "silent", value: 1} = quiet.()

    # First contact, then three days: the nightly pass is expected.
    Model.reply("hello", for: id)
    assert {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "hi", ctx.actor)
    Clock.Fake.advance(3 * 86_400)
    assert %{tone: "fail", finding: finding} = quiet.()
    assert finding =~ "the nightly pass: never, due within 2 days"
    assert :ok = Sunna.tick(id)
    yesterday = Clock.now() |> DateTime.add(-1, :day) |> DateTime.to_date() |> Date.to_iso8601()
    assert :ok = Eunomia.judge_night(id, yesterday, ctx.actor)
    assert %{tone: "silent", value: 2} = quiet.()

    # Nine days on: the weekly audit and the wash are expected; the
    # baseline only once there is a habit to measure, and the measures
    # of the run that first expected it take it.
    Clock.Fake.advance(9 * 86_400)
    assert %{tone: "fail", finding: finding} = quiet.()
    assert finding =~ "the weekly memory audit: never, due within 8 days"
    assert finding =~ "the weekly wash: never"
    refute finding =~ "the trait baseline"

    {:ok, _} =
      Oneiroi.Ethos.define_habit(
        id,
        %{name: "waters", trigger: %{"words" => ["garden"]}, stance: "keep"},
        ctx.brain
      )

    assert %{tone: "fail", finding: finding} = quiet.()
    assert finding =~ "the trait baseline: never, due within 8 days"
    assert :ok = Sunna.tick(id)
    yesterday = Clock.now() |> DateTime.add(-1, :day) |> DateTime.to_date() |> Date.to_iso8601()
    assert :ok = Eunomia.judge_night(id, yesterday, ctx.actor)
    _ = Eunomia.run_audit(id, ctx.actor)
    _ = Eunomia.run_wash(id, ctx.actor)
    # The baseline was taken by the measures of the run above.
    assert %{tone: "silent", value: 5, finding: finding} = quiet.()
    assert finding =~ "read 5 expected events, each within its cadence"

    # Fail-loud: the checker's own crash is a finding and an exit code, never silence.
    alias Oneiroi.HuginnMuninn.Quietcheck
    assert {:crashed, "boom"} = Quietcheck.guarded(fn -> raise "boom" end)
    assert {0, [first | rest]} = Mix.Tasks.Oneiroi.Quietcheck.report()
    assert first == "QUIETCHECK: ok" and List.last(rest) == "QUIETCHECK: ok"
    Clock.Fake.advance(3 * 3600)
    assert {1, [first | rest]} = Mix.Tasks.Oneiroi.Quietcheck.report()
    assert first == "QUIETCHECK: FAIL, 1 missing" and List.last(rest) == first
    assert Enum.any?(rest, &(&1 =~ "MISSING the hour marker"))
  end
end

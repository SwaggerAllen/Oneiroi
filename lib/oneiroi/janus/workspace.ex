defmodule Oneiroi.Janus.Workspace do
  @moduledoc """
  One workspace a succession (janus#49, lily:design/succession-workspace.md
  "The shape"): an overview of where it stands, and a thread a step
  (envelope, pool, questions, C0), each an event feed with chat on the
  house's thread substrate (seshat#116).

  - **The feeds.** Every event of a step is an entry in its thread,
    written by the platform and tagged with its step, its event and who
    made it (`record/2`, from `Oneiroi.Janus.Handlers.Workspace`). An
    entry says what happened and names the version it happened at; it
    never carries an authored artifact's words (the questions, C0's
    records, the day's shape, her notes, the packet), which stay in the
    succession's own records and are read there. Remarks are a member's
    own, by name (`remark/4`); a handoff gives one resident a turn in one
    step (`handoff/6`).
  - **The overview.** `overview/2` is the state as one viewer may read
    it: the stage, whose move it is, what each gate waits on, every
    outstanding acceptance, the fork as a recorded event, and what that
    viewer cannot read, named as such (sealed, judges only, blind), so an
    absence is legible and never a hole.

  The threads wake nobody by the house's rounds: each step's wakes are the
  succession's own (`Rites`), so a remark wakes no one but whom a handoff
  names.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Gaia
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Events
  alias Oneiroi.Janus.Rites
  alias Oneiroi.Janus.Store
  alias Oneiroi.Janus.Successions
  alias Oneiroi.Scope
  alias Oneiroi.Seshat

  @steps ~w(envelope pool questions c0)
  @step_words %{
    "envelope" => "the envelope",
    "pool" => "the pool",
    "questions" => "the questions",
    "c0" => "C0"
  }
  @text_chars 4_000

  @doc "The steps a workspace has a thread for."
  def steps, do: @steps

  # ---- the stage ----

  @doc "Where a succession stands, as a key and its words (`Oneiroi.Janus.Stage`)."
  @spec stage(map()) :: {String.t(), String.t()}
  defdelegate stage(row), to: Oneiroi.Janus.Stage

  # ---- the feeds ----

  @doc "The step a succession event belongs to, or nil for one no feed carries (the packet's above all)."
  @spec step_of(struct(), map() | nil) :: String.t() | nil
  def step_of(%Events.Forked{}, _row), do: "envelope"
  def step_of(%Events.EnvelopeSet{}, _row), do: "envelope"
  def step_of(%Events.PoolModelAdded{}, _row), do: "pool"
  def step_of(%Events.PoolModelRemoved{}, _row), do: "pool"
  def step_of(%Events.StepFinished{step: step}, _row), do: step

  def step_of(%struct{}, _row)
      when struct in [
             Events.QuestionAdded,
             Events.QuestionProposed,
             Events.QuestionAccepted,
             Events.QuestionDeclined,
             Events.QuestionRemoved,
             Events.QuestionsOpened,
             Events.QuestionsReopened
           ],
      do: "questions"

  def step_of(%struct{}, _row)
      when struct in [
             Events.C0Selected,
             Events.C0Proposed,
             Events.C0Accepted,
             Events.C0Declined,
             Events.C0Removed,
             Events.DayShapeSet,
             Events.C0Frozen,
             Events.C0Unfrozen,
             Events.ScreeningStarted
           ],
      do: "c0"

  def step_of(%struct{action: action}, _row)
      when struct in [Events.ReadyMarked, Events.SeatWaived, Events.MarksLapsed],
      do: if(action == "questions", do: "questions", else: "c0")

  # The panel's acceptances belong to the gate standing open.
  def step_of(%struct{}, row)
      when struct in [
             Events.JudgeInvited,
             Events.JudgeJoined,
             Events.JudgeLeft,
             Events.JudgeRemoved
           ],
      do: gate(row)

  def step_of(_event, _row), do: nil

  defp gate(:unread), do: "gate"
  defp gate(%{questions_done_at: %DateTime{}}), do: "c0"
  defp gate(_row), do: "questions"

  @doc """
  An event's entry in its step's feed (janus#49): what happened, who did
  it, at what version, in words every reader of the house's feed may
  read; never an artifact's words. Nil for an event no feed carries.
  """
  @spec line(struct(), (String.t() -> String.t())) :: String.t() | nil
  def line(e, name) do
    who = name.(party(e.actor))
    words(e, who, name)
  end

  defp words(%Events.Forked{} = e, _who, _name),
    do: "The fork is made: the copy every later stage runs on, at commit #{short(e.commit)}."

  defp words(%Events.EnvelopeSet{} = e, who, _name),
    do:
      "#{who} stated the envelope: at most #{per_m(e.input_nanos)} in and #{per_m(e.output_nanos)} out a million tokens#{if e.max_models, do: ", #{e.max_models} models at most", else: ""}."

  defp words(%Events.PoolModelAdded{} = e, who, _name), do: "#{who} put #{e.model} in the pool."

  defp words(%Events.PoolModelRemoved{} = e, who, _name),
    do: "#{who} took #{e.model} out of the pool, with a note."

  defp words(%Events.StepFinished{step: "pool"}, who, _name),
    do: "#{who} says the picks are done for now; the questions are next."

  defp words(%Events.StepFinished{step: "questions"}, who, _name),
    do: "#{who} closed the question set; C0 is next."

  defp words(%Events.StepFinished{step: "c0"}, who, _name),
    do: "#{who}'s choices for C0 are made; her judges are asked to read it and mark ready."

  defp words(%Events.QuestionAdded{} = e, who, _name),
    do: "#{who} put question ##{e.number} in the set."

  defp words(%Events.QuestionProposed{} = e, who, _name),
    do: "#{who} proposed question ##{e.number}; it waits on her answer."

  defp words(%Events.QuestionAccepted{} = e, who, _name),
    do: "#{who} accepted proposed question ##{e.number}."

  defp words(%Events.QuestionDeclined{} = e, who, _name),
    do: "#{who} declined proposed question ##{e.number}, with a note."

  defp words(%Events.QuestionRemoved{} = e, who, _name),
    do: "#{who} took question ##{e.number} out of the set, with a note."

  defp words(%Events.QuestionsOpened{} = e, who, _name),
    do:
      "#{who} asks her judges to read the set (version #{e.version}) and mark ready for its close."

  defp words(%Events.QuestionsReopened{}, who, _name),
    do: "#{who} reopened the question set, with a note; every mark on it starts again."

  defp words(%Events.C0Selected{} = e, who, _name),
    do: "#{who} put item ##{e.number} (#{e.kind}) in C0."

  defp words(%Events.C0Proposed{} = e, who, _name),
    do: "#{who} proposed item ##{e.number} (#{e.kind}) for C0; it waits on her answer."

  defp words(%Events.C0Accepted{} = e, who, _name),
    do: "#{who} accepted proposed item ##{e.number} into C0."

  defp words(%Events.C0Declined{} = e, who, _name),
    do: "#{who} declined proposed item ##{e.number}, with a note."

  defp words(%Events.C0Removed{} = e, who, _name),
    do: "#{who} took item ##{e.number} out of C0, with a note."

  defp words(%Events.DayShapeSet{}, who, _name),
    do: "#{who} wrote the day's shape, her note on the bundle."

  defp words(%Events.C0Frozen{} = e, who, _name),
    do:
      "#{who} froze C0: #{e.items} items, bundle #{short(e.digest)}. Her packet's sealed turn is hers alone."

  defp words(%Events.C0Unfrozen{}, who, _name),
    do: "#{who} reopened C0 before screening, with a note; every freeze mark starts again."

  defp words(%Events.ScreeningStarted{} = e, who, _name),
    do:
      "#{who} started screening: the bundle is bound and final (#{length(e.runs)} runs, #{length(e.questions)} questions, #{length(e.judges)} on the panel)."

  defp words(%Events.ReadyMarked{} = e, who, _name),
    do:
      "#{who}: #{if e.ready, do: "ready", else: "not yet ready"} for #{act(e.action)}#{if e.version, do: ", on version #{e.version}", else: ""}."

  defp words(%Events.SeatWaived{} = e, who, name),
    do:
      "#{who} waived #{name.(e.party)}'s mark for #{act(e.action)}, on version #{e.version}, with a note."

  defp words(%Events.MarksLapsed{} = e, _who, _name),
    do:
      "#{if e.action == "questions", do: "The set", else: "C0"} changed (#{e.why}): #{length(e.parties)} #{if length(e.parties) == 1, do: "mark or waiver", else: "marks and waivers"} lapsed, each judge asked again (now version #{e.version})."

  defp words(%Events.JudgeInvited{} = e, who, name),
    do: "#{who} invited #{name.(e.party)} to her panel."

  defp words(%Events.JudgeJoined{} = e, _who, name), do: "#{name.(e.party)} joined the panel."

  defp words(%Events.JudgeLeft{} = e, _who, name),
    do: "#{name.(e.party)} left the panel, with a note."

  defp words(%Events.JudgeRemoved{was: "invited"} = e, who, name),
    do: "#{who} withdrew #{name.(e.party)}'s invitation, with a note."

  defp words(%Events.JudgeRemoved{} = e, who, name),
    do: "#{who} took #{name.(e.party)} off the panel, with a note."

  defp words(_event, _who, _name), do: nil

  @doc """
  A succession event's feed entry (janus#49), as a job's arguments, read
  in the handler with no read of anything else: her id, the episode, the
  step ("gate" for a panel event, settled when written), the line with
  each party a `{{party}}` placeholder named when written, its tags, and
  the event's place in its stream (`seq`) so the feed reads in order. Nil
  for an event no feed carries.
  """
  @spec entry_for(struct(), map()) :: map() | nil
  def entry_for(%{id: resident_id, episode: episode} = e, metadata) when is_integer(episode) do
    step = step_of(e, :unread)

    with step when is_binary(step) <- step,
         text when is_binary(text) <- line(e, &"{{#{&1}}}") do
      %{
        "resident_id" => resident_id,
        "episode" => episode,
        "step" => step,
        "text" => text,
        "meta" => [
          ["step", step],
          ["event", e.__struct__ |> Module.split() |> List.last()],
          ["for_kind", to_string(e.actor.kind)],
          ["for_id", to_string(e.actor.id)],
          ["for_name", "{{#{party(e.actor)}}}"],
          ["seq", to_string(seq(metadata))]
        ]
      }
    else
      _none -> nil
    end
  end

  def entry_for(_event, _metadata), do: nil

  defp seq(%{stream_version: v}), do: v
  defp seq(%{"stream_version" => v}), do: v
  defp seq(_metadata), do: ""

  @doc "Writes an entry `entry_for/2` made into its step's thread, naming its parties and settling a panel event's gate, opening the thread on its first entry."
  @spec write(map()) :: :ok | {:error, term()}
  def write(%{"resident_id" => resident_id, "episode" => episode} = args) do
    names = names(resident_id)

    named =
      &Regex.replace(~r/\{\{([a-z]+:[0-9a-f-]+)\}\}/, &1, fn _all, p -> Map.get(names, p, p) end)

    step = settle(args["step"], resident_id)

    meta =
      Enum.map(args["meta"], fn [k, v] -> {k, if(k == "step", do: step, else: named.(v))} end)

    with %{id: household} <- Gaia.resident_household(resident_id) || {:error, :no_house},
         {:ok, thread} <-
           thread(
             household,
             resident_id,
             %{episode: episode, dry_run: dry_run?(resident_id, episode)},
             step
           ),
         {:ok, _} <- Seshat.workspace_entry(household, thread, named.(args["text"]), meta) do
      :ok
    end
  end

  # A panel event belongs to the gate standing open when it is written.
  defp settle("gate", resident_id) do
    case Successions.status(resident_id) do
      %{questions_done_at: %DateTime{}} -> "c0"
      _open -> "questions"
    end
  end

  defp settle(step, _resident_id), do: step

  defp dry_run?(resident_id, episode) do
    case Successions.status(resident_id) do
      %{episode: ^episode, dry_run: dry} -> dry == true
      _other -> false
    end
  end

  @doc "A step's thread, opened on its first use: `threads/succession-<her slug>-<episode>-<step>`."
  @spec thread(String.t(), String.t(), map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def thread(household, resident_id, row, step) do
    {:ok, %{slug: slug, name: name}} = AgathosDaimon.fetch(resident_id)

    Seshat.workspace_open(
      household,
      "succession-#{slug}-#{row.episode}-#{step}",
      "#{name}'s succession #{row.episode}#{if row.dry_run, do: " (a dry run)", else: ""}: #{@step_words[step]}",
      "The #{@step_words[step]} step of #{name}'s succession #{row.episode}: its events as they happen, written by the platform, and the talk about them. The authored things (her questions, C0, the day's shape, her packet) stay in the succession's own records, whole and versioned; read them with succession_status (resident: \"#{name}\"). Nothing written here starts the house's rounds.",
      [{"workspace", "succession:#{resident_id}:#{row.episode}"}, {"step", step}]
    )
  end

  # ---- remarks and handoffs ----

  @doc "A member's remark in a step's thread, by name (janus#49): hers, the witness's, or a judge's on the panel; it wakes nobody."
  @spec remark(String.t(), String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def remark(resident_id, step, text, %Actor{} = actor) do
    with :ok <- step_ok(step),
         :ok <- text_ok(text),
         {:ok, row} <- may_speak(resident_id, actor),
         %{id: household} <- Gaia.resident_household(resident_id),
         {:ok, thread} <- thread(household, resident_id, row, step),
         {:ok, _} <- Seshat.workspace_remark(actor, thread, text, [{"step", step}]) do
      :ok
    end
  end

  @doc """
  A handoff (janus#49; the design's "give Lily a turn in C0"): one
  resident given a turn in one step, by her, her witness or a judge on
  her panel. It lands in the step's feed; `private` keeps its words out
  of the feed, which every member reads, and in the wake alone, for a
  text composed for her projection only. Never one text across a seal.
  """
  @spec handoff(String.t(), String.t(), String.t(), String.t(), boolean(), Actor.t()) ::
          :ok | {:error, term()}
  def handoff(resident_id, step, to, text, private, %Actor{} = actor) do
    names = names(resident_id)

    with :ok <- step_ok(step),
         :ok <- text_ok(text),
         {:ok, row} <- may_speak(resident_id, actor),
         {:ok, target} <- resident_named(resident_id, to),
         %{id: household} <- Gaia.resident_household(resident_id),
         {:ok, thread} <- thread(household, resident_id, row, step) do
      by = Map.get(names, party(actor), party(actor))
      them = Map.get(names, "resident:#{target}", to)

      feed =
        if private,
          do:
            "#{by} gives #{them} a turn in #{@step_words[step]}; what for is said to #{them} alone.",
          else: "#{by} gives #{them} a turn in #{@step_words[step]}: #{text}"

      _ =
        Seshat.workspace_entry(household, thread, feed, [
          {"step", step},
          {"event", "Handoff"},
          {"for_kind", to_string(actor.kind)},
          {"for_id", to_string(actor.id)},
          {"for_name", by},
          {"to", "resident:#{target}"}
        ])

      Rites.handoff(
        resident_id,
        target,
        "Step: #{@step_words[step]}, on #{Map.get(names, "resident:#{resident_id}")}'s succession. #{by} gives you a turn here: #{text} The step's thread is #{thread}; succession_status#{if target == resident_id, do: "", else: " (resident: \"#{Map.get(names, "resident:#{resident_id}")}\")"} reads where it stands."
      )
    end
  end

  # ---- the overview ----

  @doc """
  The overview as `viewer` may read it (janus#49, the design's
  per-audience projections): the stage, whose move, both gates seat by
  seat with their marks, the fork as a recorded event, the steps' rows
  (the envelope's explicitly unneeded, the pool's prerequisite), the
  feeds' threads, and `excluded`: what this viewer cannot read here,
  each named (sealed, judges only, blind). Never an artifact's words and
  never a judgment, count or ranking.
  """
  @spec overview(String.t(), Actor.t()) :: {:ok, map()} | {:error, term()}
  def overview(resident_id, %Actor{} = viewer) do
    with {:ok, row} <- readable(resident_id, viewer) do
      names = names(resident_id)
      name = &Map.get(names, &1, &1)
      {key, words} = stage(row)
      audience = audience(resident_id, row, viewer)

      {:ok,
       %{
         resident: name.("resident:#{resident_id}"),
         episode: row.episode,
         dry_run: row.dry_run,
         stage: key,
         stage_words: words,
         audience: audience,
         whose_move: whose_move(resident_id, row, key, name),
         fork: fork(row),
         steps: step_rows(resident_id, row, name),
         threads: threads(resident_id, row),
         excluded: excluded(resident_id, row, audience)
       }}
    end
  end

  # Who reads it: hers, a judge's on her panel, her witness's.
  defp audience(resident_id, _row, %Actor{kind: :resident, id: resident_id}), do: "resident"

  defp audience(resident_id, row, viewer) do
    on = on_panel?(resident_id, row, party(viewer))

    case {viewer.kind, on} do
      {_kind, true} -> "judge"
      {:witness, false} -> "witness"
      _other -> "member"
    end
  end

  defp readable(resident_id, %Actor{} = viewer) do
    row = Successions.status(resident_id)

    member? =
      case Gaia.resident_household(resident_id) do
        %{id: household} -> Gaia.household_member?(household, viewer)
        _none -> false
      end

    cond do
      is_nil(row) -> {:error, Error.new(:janus_no_succession, :janus_workspace_none)}
      viewer.kind == :resident and viewer.id == resident_id -> {:ok, row}
      member? -> {:ok, row}
      true -> {:error, Error.new(:janus_not_a_member, :janus_workspace_reader)}
    end
  end

  defp whose_move(resident_id, row, key, name) do
    her = name.("resident:#{resident_id}")

    case key do
      "envelope" ->
        "her witness: the envelope"

      "pool" ->
        "#{her}: her picks"

      gate when gate in ["questions", "c0"] ->
        waiting = for s <- Successions.seats(resident_id, gate), not s.ready, do: name.(s.party)

        if waiting == [],
          do: "#{her}: every seat is ready; the #{act(gate)} is hers to make",
          else:
            "waits on #{Enum.join(waiting, ", ")} for #{act(gate)}; or #{her}'s waiver or removal"

      "frozen" ->
        "#{her}: screening"

      _later ->
        Successions.status(resident_id) && words_for_later(row)
    end
  end

  defp words_for_later(row), do: elem(stage(row), 1)

  defp fork(%{forked_at: nil}), do: nil

  defp fork(row),
    do: %{event: "Forked", at: row.forked_at, commit: row.fork_commit, copy: row.copy_id}

  defp step_rows(resident_id, row, name) do
    [
      %{
        step: "envelope",
        participation: "explicitly unneeded: no judge marks the envelope",
        done: not is_nil(row.envelope_set_at)
      },
      %{
        step: "pool",
        participation:
          "a prerequisite, not a judgment: the envelope stated and a model in the pool",
        envelope: not is_nil(row.envelope_set_at),
        models:
          Scope.resident(resident_id, fn -> Store.pool(row.episode) end)
          |> Enum.count(&is_nil(&1.removed_at)),
        done: not is_nil(row.pool_done_at)
      },
      gate_row(resident_id, row, "questions", row.questions_version, row.questions_done_at, name),
      gate_row(resident_id, row, "c0", row.c0_version, row.c0_frozen_at, name)
    ]
  end

  defp gate_row(resident_id, row, step, version, closed_at, name) do
    %{
      step: step,
      participation:
        "every seat on her panel: an invitation answered, then a ready mark or her waiver",
      version: version,
      open: is_nil(closed_at),
      opened: step == "questions" and not is_nil(row.questions_opened_at),
      seats:
        for s <- Successions.seats(resident_id, step) do
          Map.put(s, :name, name.(s.party))
        end
    }
  end

  defp threads(resident_id, row) do
    {:ok, %{slug: slug}} = AgathosDaimon.fetch(resident_id)
    for step <- @steps, into: %{}, do: {step, "threads/succession-#{slug}-#{row.episode}-#{step}"}
  end

  # What this viewer cannot read here, named (the design's "an absence
  # made legible"): the packet's seal for all but her; the room's pointer
  # for all but its judges; blind identities and every raw judgment while
  # they are sealed; counts and rankings never hers.
  defp excluded(resident_id, row, audience) do
    room =
      if audience == "judge",
        do: [],
        else: [
          %{
            what: "the panel room",
            why: "judges only",
            pointer: "panel room, judges only, #{posts(resident_id, row)} posts"
          }
        ]

    packet =
      if audience == "resident",
        do: [],
        else: [
          %{what: "her packet", why: "sealed: hers alone until the nominee reads its last draft"}
        ]

    blind =
      if row.state in ["screening", "judging"] and is_nil(row.revealed_at),
        do: [%{what: "who answered each run", why: "blind until every judgment is in"}],
        else: []

    judgments =
      if audience == "resident",
        do: [
          %{
            what: "the judges' judgments as records",
            why:
              "never hers; after the room, the argued interpretations, attributed (succession_evidence)"
          },
          %{what: "per-model counts, rankings and favorites", why: "never hers, at any stage"}
        ],
        else: [
          %{what: "other judges' judgments", why: "the room's alone, once every judge is ready"}
        ]

    packet ++ room ++ blind ++ judgments
  end

  defp posts(resident_id, row),
    do: Scope.resident(resident_id, fn -> length(Store.posts(row.episode)) end)

  # ---- helpers ----

  defp may_speak(resident_id, %Actor{} = actor) do
    row = Successions.status(resident_id)

    cond do
      is_nil(row) -> {:error, Error.new(:janus_no_succession, :janus_workspace_none)}
      actor.kind == :resident and actor.id == resident_id -> {:ok, row}
      actor.kind == :witness and witness?(resident_id, actor) -> {:ok, row}
      on_panel?(resident_id, row, party(actor)) -> {:ok, row}
      true -> {:error, Error.new(:janus_not_yours, :janus_workspace_speaker)}
    end
  end

  defp witness?(resident_id, actor),
    do: match?({:ok, %{account_id: id}} when id == actor.id, AgathosDaimon.fetch(resident_id))

  defp on_panel?(resident_id, row, party) do
    Scope.resident(resident_id, fn -> Store.panel(row.episode) end)
    |> Enum.any?(&(&1.party == party and &1.state in ["in", "judge"]))
  end

  defp resident_named(resident_id, name) do
    found =
      Enum.find(Successions.panel_names(resident_id), fn m ->
        m.name == String.trim(to_string(name)) and String.starts_with?(m.party, "resident:")
      end)

    case found do
      %{party: "resident:" <> id} -> {:ok, id}
      nil -> {:error, Error.new(:janus_not_a_member, :janus_handoff_target)}
    end
  end

  defp names(resident_id),
    do: Map.new(Successions.panel_names(resident_id), &{&1.party, &1.name})

  defp step_ok(step) when step in @steps, do: :ok

  defp step_ok(_step),
    do: {:error, Error.new(:janus_step_invalid, :janus_workspace_step, steps: @steps)}

  defp text_ok(text) do
    if is_binary(text) and String.trim(text) != "" and String.length(text) <= @text_chars,
      do: :ok,
      else: {:error, Error.new(:janus_text_invalid, :janus_workspace_text, at_most: @text_chars)}
  end

  defp act("questions"), do: "the question set's close"
  defp act(_c0), do: "the freeze"

  defp party(%{kind: kind, id: id}), do: "#{kind}:#{id}"

  defp short(nil), do: "(none)"
  defp short("sha256:" <> hex), do: String.slice(hex, 0, 12)
  defp short(sha), do: String.slice(sha, 0, 12)

  defp per_m(nanos) when is_integer(nanos),
    do: "$" <> :erlang.float_to_binary(nanos / 1000, decimals: 2)

  defp per_m(_none), do: "?"
end

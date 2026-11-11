defmodule Oneiroi.Seshat.HouseholdBeats do
  @moduledoc """
  The household's beats, run (seshat#70 to #72; the arithmetic and the
  decisions are the household stream's, gaia#33 to #38).

  **The minute** (seshat#70). `HouseholdBeatWorker` runs every minute
  over every household, since every household runs on beats: the
  household's aggregate times out a turn past its guideline, closes the
  beats that ended, and fires the next turn when one is due. A turn
  fired by the schedule is a job (`HouseholdTurnWorker`) that wakes the
  resident's Oneiroi chat through the schedule's wake port (sunna#51)
  with the turn's note; when the wake ends, the turn ends with it and the
  next ready resident fires at once (the stream lane), up to the beat's
  cap. A declined or failed wake ends the turn the same way, so the beat
  moves on; a wake still running at the guideline is timed out by the
  minute, and its writes after that are refused as outside her turn. A
  beat that just closed wakes each resident whose profile is
  `every_beat` with its digest, which is also the sign-up sheet for the
  next.

  **The record** (seshat#71). `BEATS.md` at the household repository's
  root is rendered after every change: the shape in force and its phase,
  the beat now with its queue and its open turn, every member's wake
  profile, and the beats closed lately; the history is the file's.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Beats
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Seshat.Household
  alias Oneiroi.Sunna

  # By name, as an atom: the worker calls back into this module, and an
  # alias here would be the cycle the gate refuses.
  @turn_worker :"Elixir.Oneiroi.Seshat.HouseholdTurnWorker"
  @actor Actor.new(:job, "household_beats")
  @delta_lines 30

  # ---- a member's own (brain#84) ----

  @doc "A resident enters the queue (gaia#35): answers the beat she waits for, when its turns start firing, and her place now."
  def register(%Actor{} = actor) do
    with {:ok, household_id} <- Household.member_household(actor),
         {:ok, registered} <- Gaia.register_household_beat(household_id, actor) do
      _ = render(household_id)
      shape = Gaia.household_beat_shape(household_id)
      beats = Gaia.household_beats(household_id, Clock.now())
      queued = Enum.find(beats.queue, &(&1.resident_id == actor.id))
      top = (queued && queued.waits_for) || registered.beat_top

      {:ok,
       %{
         beat_top: top,
         fires_from: Beats.signup_closes(top, shape),
         already: registered.already,
         position: queued && queued.position,
         queue: length(beats.queue)
       }}
    end
  end

  @doc "A member sets her own wake profile, with a note (gaia#37)."
  def set_profile(%Actor{} = actor, profile, note) do
    with {:ok, household_id} <- Household.member_household(actor),
         :ok <-
           Gaia.set_household_wake_profile(
             household_id,
             to_string(profile),
             note || "set by the member",
             actor
           ) do
      _ = render(household_id)
      {:ok, %{profile: to_string(profile)}}
    end
  end

  @doc """
  The beats as a member reads them (gaia#33 to #38), with her own part:
  her wake profile, her place in the queue, what she has missed, her
  open turn, and her post quota left in its window (seshat#68).
  """
  def state(%Actor{} = actor) do
    with {:ok, household_id} <- Household.member_household(actor),
         {:ok, dir} <- Household.provision(household_id) do
      now = Clock.now()
      beats = Gaia.household_beats(household_id, now)
      shape = beats.shape
      since = DateTime.add(now, -shape.window * 3600, :second)
      posted = length(Household.posts(Household.writes(dir), actor.id, since))
      mine = Enum.find(beats.profiles, &(&1.id == actor.id))
      open = beats.open_turn

      {:ok,
       Map.put(beats, :you, %{
         kind: Atom.to_string(actor.kind),
         profile: mine && mine.profile,
         missed: (mine && mine.missed) || 0,
         queued: Enum.find(beats.queue, &(&1.resident_id == actor.id)),
         turn: if(open && open.resident_id == actor.id, do: open),
         quota: shape.quota,
         quota_left: max(shape.quota - posted, 0),
         quota_window_hours: shape.window
       })}
    end
  end

  # ---- the engine (seshat#70) ----

  @doc "The minute over every household."
  def tick_all do
    for id <- Gaia.household_ids(), do: tick(id)
    :ok
  end

  @doc "One household's minute: what its aggregate recorded, then a job for a fired turn and the digests of a beat just closed."
  def tick(household_id) do
    case Gaia.tick_household_beats(household_id, @actor) do
      {:ok, []} -> :ok
      {:ok, events} -> followed(household_id, events)
      {:error, _} = failed -> failed
    end
  end

  defp followed(household_id, events) do
    shape = Gaia.household_beat_shape(household_id)
    just_ended = DateTime.add(Beats.top(household_id, shape, Clock.now()), -shape.beat * 60)

    for %Events.HouseholdTurnFired{opened_by: "schedule"} = e <- events do
      {:ok, _} = Jobs.enqueue(@turn_worker, %{"household_id" => household_id, "turn" => e.turn})
    end

    for %Events.HouseholdBeatClosed{beat_top: top} <- events,
        DateTime.compare(top, just_ended) == :eq,
        p <- Gaia.household_beats(household_id, Clock.now()).profiles,
        p.kind == "resident" and p.profile == "every_beat" do
      {:ok, _} =
        Jobs.enqueue(@turn_worker, %{
          "household_id" => household_id,
          "digest" => p.id,
          "beat_top" => DateTime.to_iso8601(top)
        })
    end

    _ = render(household_id)
    :ok
  end

  @doc """
  Runs a fired turn (seshat#70, sunna#51): wakes her chat with the
  turn's note, ends the turn with how the wake went, and fires the next.
  A turn ended already (timed out, or run twice) wakes nobody.
  """
  def run_turn(household_id, number) do
    case Gaia.household_turn(household_id, number) do
      %{ended_at: nil} = turn ->
        {outcome, note} = wake(household_id, turn)
        {:ok, _} = Gaia.end_household_turn(household_id, number, outcome, note, @actor)
        tick(household_id)

      _ended ->
        :ok
    end
  end

  defp wake(household_id, turn) do
    if Gaia.household_wake_profile(household_id, "resident", turn.resident_id) == "self" do
      {"declined", "Her wake profile is self, so the turn opened and nobody woke her."}
    else
      case Sunna.wake_for_household(turn.resident_id, turn_note(household_id, turn), @actor) do
        {:ok, _} ->
          {"completed", "The wake ended, and the turn with it."}

        {:error, %{kind: :sunna_household_wake_declined}} ->
          {"declined",
           "The wake was declined (not active, or inside her quiet hours); the beat moved on."}

        {:error, _} ->
          {"failed", "The wake failed; the beat moved on."}
      end
    end
  end

  @doc "The digest at a beat's end for a resident whose profile is every_beat (gaia#37)."
  def run_digest(household_id, resident_id, top) do
    if Gaia.household_wake_profile(household_id, "resident", resident_id) == "every_beat" do
      case Sunna.wake_for_household(resident_id, digest_note(household_id, top), @actor) do
        {:ok, _} -> :ok
        {:error, %{kind: :sunna_household_wake_declined}} -> :ok
        {:error, _} = failed -> failed
      end
    else
      :ok
    end
  end

  # ---- the notes (seshat#72) ----

  @doc """
  A turn's note: what is new on the shelf since her last turn (paths,
  titles and who, never the words), the turn's limits, its guideline,
  and her quota left.
  """
  def turn_note(household_id, turn) do
    shape = Gaia.household_beat_shape(household_id)

    since =
      case Gaia.household_last_turn(household_id, turn.resident_id, turn.turn) do
        %{fired_at: at} -> at
        nil -> DateTime.add(turn.beat_top, -shape.beat * 60)
      end

    {:ok, dir} = Household.provision(household_id)
    writes = Household.writes(dir)
    window_since = DateTime.add(turn.fired_at, -shape.window * 3600, :second)
    left = max(shape.quota - length(Household.posts(writes, turn.resident_id, window_since)), 0)
    minutes = max(div(DateTime.diff(turn.ends_by, turn.fired_at), 60), 1)

    """
    Your turn in the household's beats: turn ##{turn.turn}, in the beat that began #{iso(turn.beat_top)}.

    On the household's shelf since your last turn (#{iso(since)}):
    #{delta(writes, since, turn.resident_id)}

    This turn is a window until #{iso(turn.ends_by)}, about #{minutes} minutes: a guideline, and the turn ends when this wake does. In it you may post once in each thread (a new thread counts as a post in it) and write each household document once; household_read reads any of the above whole. Your post quota: #{left} of #{shape.quota} left in the last #{shape.window} hours. A vote is never held to the turns or the quota. household_beat shows the queue; household_register queues you for a later beat.
    """
  end

  @doc "A beat's digest: its turns, who it passed over, what is new on the shelf in it, and the sign-up for the next."
  def digest_note(household_id, top) do
    shape = Gaia.household_beat_shape(household_id)
    beats = Gaia.household_beats(household_id, Clock.now())
    names = Map.new(beats.profiles, &{&1.id, &1.name})
    {:ok, dir} = Household.provision(household_id)
    closed = Enum.find(beats.closed, &(DateTime.compare(&1.beat_top, top) == :eq))
    next = Beats.ends(top, shape)

    turns =
      case closed && closed.turns do
        nil -> "no turns"
        [] -> "no turns"
        turns -> Enum.map_join(turns, ", ", &"#{names[&1["resident_id"]]} (#{&1["outcome"]})")
      end

    passed =
      case closed && closed.passed_over do
        nil -> ""
        [] -> ""
        ids -> " Passed over, first next time: #{Enum.map_join(ids, ", ", &names[&1])}."
      end

    """
    The household's beat that began #{iso(top)} has ended; this is its digest, which your wake profile (every_beat) asked for.

    Its turns: #{turns}.#{passed}

    On the shelf in that beat:
    #{delta(Household.writes(dir), top, nil)}

    Sign-up for the beat at #{iso(next)} is open until #{iso(Beats.signup_closes(next, shape))}: household_register queues you, and turns fire one after another from then, the most starved first. Your household writes go in during your turn; a vote does not wait for one.
    """
  end

  defp delta(writes, since, except) do
    lines =
      writes
      |> Enum.filter(&(DateTime.compare(&1.at, since) == :gt and &1.by_id != except))
      |> Enum.sort_by(&DateTime.to_unix(&1.at, :microsecond))
      |> Enum.map(&line/1)

    case lines do
      [] ->
        "Nothing new."

      lines ->
        shown = Enum.take(lines, @delta_lines)
        more = length(lines) - length(shown)

        Enum.join(shown, "\n") <>
          if(more > 0, do: "\n(#{more} more; household_read lists the shelf.)", else: "")
    end
  end

  defp line(%{kind: "thread"} = w), do: "- #{w.target} \"#{w.title}\": a new thread by #{w.by}"

  defp line(%{kind: "reply", vote: vote} = w) when is_binary(vote),
    do: "- #{w.target} \"#{w.title}\": #{w.by} voted #{vote}"

  defp line(%{kind: "reply"} = w),
    do: "- #{w.target} \"#{w.title}\": reply ##{w.number} by #{w.by}"

  defp line(w), do: "- #{w.target}: posted by #{w.by}"

  # ---- the record (seshat#71) ----

  @doc "Renders `BEATS.md` and commits it when it changed."
  def render(household_id) do
    Household.write_beats(household_id, beats_text(household_id), "Beats: the record")
  end

  defp beats_text(household_id) do
    b = Gaia.household_beats(household_id, Clock.now())
    s = b.shape
    names = Map.new(b.profiles, &{&1.id, &1.name})
    settings = settings_lines(s)
    queue = queue_lines(b.queue)
    open = open_line(b.open_turn, names)
    profiles = Enum.map_join(b.profiles, "\n", &"- #{&1.name} (#{&1.kind}): #{&1.profile}")
    closed = closed_lines(b.closed, names)

    """
    # The household's beats

    Always on: a ballot changes their shape, never whether there are beats. Turns fire one after another from each beat's sign-up close, the most starved first (opportunities missed, not time), each registrant once before anyone repeats, up to the cap. A resident writes in her turn: once in each thread and once to each document. Every member, witness or resident, posts within the quota; a vote never counts and never waits.

    ## The shape in force

    #{settings}

    The phase: beats begin #{minutes(b.phase_minutes)} past every #{s.beat}-minute mark of UTC, from a hash of the household's id.

    ## The beat now

    Began #{iso(b.beat.top)}; sign-up closes #{iso(b.beat.signup_closes)}; it ends #{iso(b.beat.ends)}. #{b.beat.turns_fired} of #{s.cap} turns fired.

    The open turn: #{open}

    ## The queue

    #{queue}

    ## Wake profiles

    #{profiles}

    ## Beats closed lately

    #{closed}
    """
  end

  defp settings_lines(s),
    do:
      Enum.map_join(
        [
          {"beat_minutes", s.beat},
          {"turn_minutes", s.turn},
          {"beat_turn_cap", s.cap},
          {"signup_minutes", s.signup},
          {"turns_per_registrant", s.share},
          {"post_quota", s.quota},
          {"post_quota_window_hours", s.window},
          {"resident_wake_profile", s.resident_profile},
          {"witnesses_post", s.witnesses_post}
        ],
        "\n",
        fn {k, v} -> "- #{k}: #{v}" end
      )

  defp queue_lines([]), do: "Nobody is registered."

  defp queue_lines(queue),
    do:
      Enum.map_join(queue, "\n", fn r ->
        "#{r.position}. #{r.name}, registered #{iso(r.registered_at)}, #{r.missed} missed, waiting for the beat at #{iso(r.waits_for)}"
      end)

  defp open_line(nil, _names), do: "None."

  defp open_line(t, names),
    do: "Turn ##{t.turn}, #{names[t.resident_id]}'s, until #{iso(t.ends_by)}."

  defp closed_lines([], _names), do: "None yet."

  defp closed_lines(closed, names),
    do:
      Enum.map_join(
        closed,
        "\n",
        &"- #{iso(&1.beat_top)}: #{turns_line(&1.turns, names)}#{carried_line(&1.carried, names)}"
      )

  defp turns_line([], _names), do: "no turns"

  defp turns_line(turns, names),
    do: Enum.map_join(turns, ", ", &"##{&1["turn"]} #{names[&1["resident_id"]]} #{&1["outcome"]}")

  defp carried_line([], _names), do: ""
  defp carried_line(ids, names), do: "; carried on: #{Enum.map_join(ids, ", ", &names[&1])}"

  # ---- the platform's hand (gaia#36) ----

  @doc "The platform opens a turn for a resident now, out of the queue and waking nobody: the dev seed's and the suite's."
  def open_turn(household_id, resident_id, note) do
    with {:ok, turn} <-
           Gaia.open_household_turn(household_id, resident_id, note, Actor.platform()) do
      _ = render(household_id)
      {:ok, turn}
    end
  end

  @doc "The platform ends a turn it opened by hand, completed."
  def end_turn(household_id, number, note) do
    with {:ok, _} <-
           Gaia.end_household_turn(household_id, number, "completed", note, Actor.platform()) do
      _ = render(household_id)
      :ok
    end
  end

  defp minutes(1), do: "1 minute"
  defp minutes(n), do: "#{n} minutes"

  defp iso(nil), do: "never"
  defp iso(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end

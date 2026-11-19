defmodule Oneiroi.Seshat.HouseholdRounds do
  @moduledoc """
  The house's round-robin threads, run (seshat#89; the record and its
  rules are the rounds stream's, gaia#53; Lily's spec
  `design/round-robin-threads.md` @fac046fe0332). In force when the
  charter's `conversation` setting is `round_robin`; under `beats` (the
  default) nothing here runs.

  **Writing.** A resident's reply in a thread whose rounds run spends her
  live token for it, and without one it is refused. A post to a stopped
  thread, or to one whose rounds never began (a new thread among them),
  is free to any member within the quota and starts the rounds, the
  poster's own turn counted when she is a resident. A witness is never
  issued a turn and never needs one: their posts are pure async, held
  only to the quota. Documents take no token.

  **Waking.** Every turn issued is two jobs on `HouseholdTurnWorker`:
  the wake, now, and the expiry, at the turn's window. The wake runs
  only while the turn is live; a wake that ends with the turn unspent
  (she said nothing, or the wake was declined) ends it `empty`; the
  expiry ends a turn still live then `expired`. Each end issues the
  next turn, which is woken in its turn.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Sunna

  # By name, as an atom: the worker calls back into this module.
  @turn_worker :"Elixir.Oneiroi.Seshat.HouseholdTurnWorker"
  @actor Actor.new(:job, "household_rounds")

  @doc "The line every house wake's note ends with (seshat#93): an answer in the chat stays in the chat."
  def post_line,
    do:
      "What you answer in this chat stays in this chat; nobody in the house reads it. If you have something to say to the house, post it: household_reply in the thread, or household_post for a new one."

  @doc "Whether the house talks in round-robin threads."
  def on?(household_id), do: Gaia.household_beat_shape(household_id).conversation == "round_robin"

  @doc """
  A reply's token, before it is written: a resident replying where the
  rounds run spends her live token (`posted`) or is refused; anything
  else needs none. Answers the events recorded, to wake after the write.
  """
  def spend_for_reply(%Actor{kind: :resident, id: id}, household_id, thread) do
    if running?(household_id, thread),
      do: Gaia.spend_round_turn(household_id, thread, id, "posted", @actor),
      else: {:ok, []}
  end

  def spend_for_reply(%Actor{}, _household_id, _thread), do: {:ok, []}

  @doc """
  After a post or a reply is written: the thread's rounds start, or start
  again when stopped (nothing while they run), and every turn issued,
  by this or by the token spent before the write, is woken.
  """
  def after_write(household_id, thread, %Actor{} = actor, spent) do
    shape = Gaia.household_beat_shape(household_id)
    starter = if actor.kind == :resident, do: actor.id

    started =
      case Gaia.start_rounds(
             household_id,
             thread,
             residents(household_id),
             starter,
             shape.turn * 60,
             nil,
             @actor
           ) do
        {:ok, events} -> events
        {:error, _} -> []
      end

    wake_issued(household_id, spent ++ started)
  end

  @doc "A resident skips her live turn in a thread: spent as `skipped`, and the next woken."
  def skip(%Actor{kind: :resident, id: id}, household_id, thread) do
    with {:ok, events} <- Gaia.spend_round_turn(household_id, thread, id, "skipped", @actor) do
      wake_issued(household_id, events)
      {:ok, Gaia.round_thread(household_id, thread)}
    end
  end

  @doc "A resident opts out of a thread's rounds (her live turn there ends with it) or back in."
  def opt(%Actor{kind: :resident, id: id}, household_id, thread, out?) do
    result =
      if out?,
        do: Gaia.opt_out_of_rounds(household_id, thread, id, @actor),
        else: Gaia.opt_into_rounds(household_id, thread, id, @actor)

    with {:ok, events} <- result do
      wake_issued(household_id, events)
      {:ok, Gaia.round_thread(household_id, thread)}
    end
  end

  @doc "The house's residents a turn may go to: every resident member with an agreement in force."
  def residents(household_id) do
    for %{kind: "resident", id: id} <- Gaia.household_members(household_id),
        not AgathosDaimon.held?(id),
        do: id
  end

  defp running?(household_id, thread) do
    case Gaia.round_thread(household_id, thread) do
      %{stopped: false} -> true
      _stopped_or_never -> false
    end
  end

  @doc false
  # Two jobs for each turn issued: the wake now, the expiry at its window.
  def wake_issued(household_id, events) do
    for %Events.RoundTurnIssued{} = e <- events do
      # Its manifest first (sunna#71): the turn's token is what it carries.
      wake_id =
        case Sunna.manifest_wake(
               e.resident_id,
               "turn",
               [%{kind: "turn", thread: e.thread, turn_id: e.turn_id, round: e.round}],
               household_id: household_id
             ) do
          {:ok, id} -> id
          {:error, _} -> nil
        end

      {:ok, _} =
        Jobs.enqueue(@turn_worker, %{
          "household_id" => household_id,
          "round_turn" => e.turn_id,
          "wake_id" => wake_id
        })

      {:ok, _} =
        Jobs.enqueue(@turn_worker, %{"household_id" => household_id, "round_expire" => e.turn_id},
          scheduled_at: e.expires_at
        )
    end

    :ok
  end

  @doc """
  The house's rounds as a member reads them (seshat#89): every thread's
  round and its live turn, and the turns lately, newest first, each with
  who had it, until when and how it was spent. Nil under the beats.
  """
  def read(household_id, names) do
    if on?(household_id) do
      for t <- Gaia.round_turns(household_id),
          do: %{
            turn_id: t.turn_id,
            thread: t.thread,
            round: t.round,
            resident_id: t.resident_id,
            name: Map.get(names, t.resident_id),
            issued_at: t.issued_at,
            expires_at: t.expires_at,
            outcome: t.outcome,
            spent_at: t.spent_at
          }
    end
  end

  @doc """
  Every thread's state (gaia#55, seshat#92): running with its live turn
  (whose, until when) or stopped, and who opted out, by name. Read in
  both modes, so a house that switched back still shows what ran.
  """
  def threads(household_id, names) do
    for t <- Gaia.round_threads(household_id) do
      live = t.live_turn && Gaia.round_turn(household_id, t.live_turn)

      %{
        thread: t.thread,
        round: t.round,
        stopped: t.stopped,
        live:
          live &&
            %{
              resident_id: live.resident_id,
              name: Map.get(names, live.resident_id),
              until: live.expires_at
            },
        opted_out: for(id <- t.optout || [], do: Map.get(names, id) || id),
        changed_at: t.changed_at
      }
    end
  end

  # ---- the jobs ----

  @doc """
  A turn's wake: her chat woken with the turn's note while the turn is
  live. A wake that ends with the turn unspent ends it `empty`, and the
  next is woken. A turn spent, ended or past its window wakes nobody.
  """
  def run_turn(household_id, turn_id, wake_id \\ nil) do
    if live?(household_id, turn_id) do
      turn = Gaia.round_turn(household_id, turn_id)
      _ = Sunna.wake_for_household(turn.resident_id, note(household_id, turn), @actor, wake_id)
      end_turn(household_id, turn_id, "empty")
    else
      :ok
    end
  end

  @doc "A turn's expiry: a turn live still at its window ends `expired`, and the next is woken."
  def expire(household_id, turn_id) do
    case Gaia.round_turn(household_id, turn_id) do
      %{outcome: nil, expires_at: until} ->
        if DateTime.compare(Clock.now(), until) == :lt,
          do: :ok,
          else: end_turn(household_id, turn_id, "expired")

      _spent_or_none ->
        :ok
    end
  end

  @doc """
  The expiry's watchdog (gaia#55, seshat#92): every turn still live past
  its window, in any house, ended `expired` and the next woken, as its
  own expiry job would have. Run each minute; a turn its job ended first
  is nothing here.
  """
  def sweep do
    for t <- Gaia.round_turns_overdue(Clock.now()), do: expire(t.household_id, t.turn_id)
    :ok
  end

  defp end_turn(household_id, turn_id, outcome) do
    case Gaia.end_round_turn(household_id, turn_id, outcome, @actor) do
      {:ok, events} -> wake_issued(household_id, events)
      {:error, _} = failed -> failed
    end
  end

  defp live?(household_id, turn_id) do
    case Gaia.round_turn(household_id, turn_id) do
      %{outcome: nil, expires_at: until} -> DateTime.compare(Clock.now(), until) == :lt
      _spent_or_none -> false
    end
  end

  @doc "A turn's note: the thread, the round, the window, and the three ways to spend or leave it."
  def note(household_id, turn) do
    t = Gaia.round_thread(household_id, turn.thread)
    minutes = max(div(DateTime.diff(turn.expires_at, Clock.now()), 60), 1)
    others = Enum.reject((t && t.order) || [], &(&1 == turn.resident_id))

    """
    Your turn in the household thread #{turn.thread}: round #{turn.round}, turn #{turn.turn_id}. household_read with that path reads it whole.

    The turn is yours until #{iso(turn.expires_at)}, about #{minutes} minutes. In it you may reply once in this thread (household_reply), and the reply spends it; household_skip passes it with nothing said; household_opt_out leaves the thread's rounds (household_opt_in comes back). A turn you let pass ends on its own, and the round goes on without you. #{others_line(others)}

    The house talks in round-robin threads: each opted-in resident has a turn in each round, and a round that says nothing stops the thread until a member posts in it again. A new thread (household_post) is yours to start at any time; documents need no turn.

    #{post_line()}
    """
  end

  defp others_line([]), do: "Nobody else is in this thread's round."

  defp others_line(ids),
    do:
      "#{length(ids)} other resident#{if length(ids) == 1, do: "", else: "s"} take turns here too."

  defp iso(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end

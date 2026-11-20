defmodule Oneiroi.Gaia.Rounds do
  @moduledoc """
  A household's round-robin threads (gaia#53; Lily's spec
  `design/round-robin-threads.md` @fac046fe0332, the witness's sign-off of
  2026-11-18), on `rounds-<household id>`: the beat metronome's
  replacement for a small house.

  **The wake is the token.** A thread's opted-in residents take turns in
  order, one round after another; each turn is a token with a unique id,
  issued to one resident for one thread, good until its window passes
  (counted from the issue, any queue wait included). Her post in the
  thread spends it, and so does her skip; nothing else of hers writes
  there. A token spent, expired or never hers authorizes nothing.

  **Rounds and the stopped state.** A round ends when every opted-in
  resident has had her turn. A round that gave output (a post) starts the
  next; a round with none stops the thread, which wakes nobody until a
  member posts to it: any member's post restarts the rounds, the opted-in
  alone woken. No output is not opting out: she stays in. Opting out (and
  back in) is hers alone.

  **Order.** Least-recent post first by default (starvation-proof); a
  thread may start with `most_recent` or `random`.

  Pure: every instant and the window arrive on the command.
  """

  import Kernel, except: [apply: 2]

  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events

  defstruct id: nil, threads: %{}, live: %{}, next_turn: 1

  @orders ~w(least_recent most_recent random)

  # ---- execute ----

  def execute(%__MODULE__{} = r, %Commands.StartRounds{} = c), do: start(r, c)
  def execute(%__MODULE__{} = r, %Commands.SpendTurn{} = c), do: spend_turn(r, c)
  def execute(%__MODULE__{} = r, %Commands.EndRoundTurn{} = c), do: end_turn(r, c)
  def execute(%__MODULE__{} = r, %Commands.OptOutOfRounds{} = c), do: opt_out(r, c)
  def execute(%__MODULE__{} = r, %Commands.OptIntoRounds{} = c), do: opt_in(r, c)

  defp start(r, c) do
    t = Map.get(r.threads, c.thread)

    cond do
      not start_shape?(c) ->
        {:error, Error.new(:gaia_rounds_invalid, :gaia_rounds_start_shape)}

      (c.order || "least_recent") not in @orders ->
        {:error, Error.new(:gaia_rounds_invalid, :gaia_rounds_start_order)}

      # Running already: a post outside a turn is not a start.
      t != nil and not t.stopped ->
        []

      true ->
        # The house's residents, the window and the ordering, as this
        # start gives them; carried on the round's event.
        restart(r, c, t)
    end
  end

  defp restart(r, c, t) do
    setup = %{
      residents: c.residents,
      timeout: c.timeout,
      ordering: (t && t.ordering) || c.order || "least_recent"
    }

    starter = if c.starter in c.residents, do: c.starter

    %{r | id: c.id}
    |> begin_round(c, c.thread, starter, setup, List.wrap(c.first))
    |> events()
  end

  defp start_shape?(c),
    do:
      is_binary(c.thread) and c.thread != "" and is_list(c.residents) and is_integer(c.timeout) and
        c.timeout > 0

  defp spend_turn(r, c) do
    t = Map.get(r.threads, c.thread)
    live = t && t.live && Map.get(r.live, t.live)

    cond do
      c.how not in ["posted", "skipped"] ->
        {:error, Error.new(:gaia_rounds_invalid, :gaia_rounds_spend_how)}

      is_nil(live) or live.resident_id != c.resident_id ->
        {:error, Error.new(:gaia_rounds_not_your_turn, :gaia_rounds_spend_not_yours)}

      DateTime.compare(c.at, live.expires_at) != :lt ->
        {:error, Error.new(:gaia_rounds_not_your_turn, :gaia_rounds_spend_expired)}

      true ->
        r |> spend(c, t.live, c.how) |> events()
    end
  end

  defp end_turn(r, c) do
    cond do
      c.outcome not in ["empty", "expired"] ->
        {:error, Error.new(:gaia_rounds_invalid, :gaia_rounds_end_outcome)}

      # Spent already, or never issued: nothing (a late job is a no-op).
      not Map.has_key?(r.live, c.turn_id) ->
        []

      true ->
        r |> spend(c, c.turn_id, c.outcome) |> events()
    end
  end

  defp opt_out(r, c) do
    t = Map.get(r.threads, c.thread) || new_thread(nil)

    if MapSet.member?(t.optout, c.resident_id) do
      []
    else
      out = %Events.RoundsOptedOut{
        actor: c.actor,
        at: c.at,
        id: c.id,
        thread: c.thread,
        resident_id: c.resident_id
      }

      r = apply(r, out)
      t = r.threads[c.thread]
      live = t.live && Map.get(r.live, t.live)

      # Out during her own turn: the turn ends with her going.
      r =
        if live && live.resident_id == c.resident_id,
          do: spend(r, c, t.live, "opted_out"),
          else: r

      [out | events(r)]
    end
  end

  defp opt_in(r, c) do
    t = Map.get(r.threads, c.thread)

    if t && MapSet.member?(t.optout, c.resident_id),
      do: %Events.RoundsOptedIn{
        actor: c.actor,
        at: c.at,
        id: c.id,
        thread: c.thread,
        resident_id: c.resident_id
      },
      else: []
  end

  # ---- the rounds, as events emitted and applied in turn ----

  # The events an execution emitted, in order (kept on the state while it
  # runs, so a step sees every step before it).
  defp events(r), do: Enum.reverse(Map.get(r, :emitted, []))

  defp emit(r, event) do
    r = apply(r, event)
    Map.update(r, :emitted, [event], &[event | &1])
  end

  defp begin_round(r, c, thread, starter, setup \\ nil, first \\ []) do
    t = Map.get(r.threads, thread) || new_thread(nil)
    setup = setup || %{residents: t.residents, timeout: t.timeout, ordering: t.ordering}
    t = Map.merge(t, setup)
    members = Enum.reject(t.residents, &MapSet.member?(t.optout, &1))
    # Named by the post but opted out of the thread (gaia#60): a turn in
    # this round alone, first with the rest the post named.
    granted = Enum.filter(Enum.uniq(first), &(&1 in t.residents and MapSet.member?(t.optout, &1)))

    started = %Events.RoundStarted{
      actor: c.actor,
      at: c.at,
      id: r.id || c.id,
      thread: thread,
      round: t.round + 1,
      order: mentioned_first(first, ordered(members, t, thread) ++ granted),
      had: List.wrap(starter),
      residents: t.residents,
      timeout: t.timeout,
      ordering: t.ordering
    }

    r |> emit(started) |> grant(c, thread, started.round, granted) |> next_turn(c, thread)
  end

  defp grant(r, _c, _thread, _round, []), do: r

  defp grant(r, c, thread, round, granted),
    do:
      emit(r, %Events.RoundTurnsGranted{
        actor: c.actor,
        at: c.at,
        id: r.id || c.id,
        thread: thread,
        round: round,
        residents: granted
      })

  # Whose turn can come: not had this round, and opted in, or granted a
  # turn in this round by a mention (gaia#60).
  defp due?(t, resident),
    do:
      not MapSet.member?(t.had, resident) and
        (not MapSet.member?(t.optout, resident) or MapSet.member?(granted(t), resident))

  defp granted(t), do: Map.get(t, :granted, MapSet.new())

  # The next resident of the round whose turn is due (due?/2): her
  # token. None left: the round ends, into the next or into stopped.
  defp next_turn(r, c, thread) do
    t = r.threads[thread]

    case Enum.find(t.order, &due?(t, &1)) do
      nil ->
        if t.output,
          do: begin_round(r, c, thread, nil),
          else:
            emit(r, %Events.RoundsStopped{
              actor: c.actor,
              at: c.at,
              id: r.id,
              thread: thread,
              round: t.round
            })

      resident ->
        emit(r, %Events.RoundTurnIssued{
          actor: c.actor,
          at: c.at,
          id: r.id,
          thread: thread,
          turn_id: Integer.to_string(r.next_turn),
          resident_id: resident,
          round: t.round,
          expires_at: DateTime.add(c.at, t.timeout, :second)
        })
    end
  end

  defp spend(r, c, turn_id, outcome) do
    live = Map.fetch!(r.live, turn_id)

    r
    |> Map.put(:id, r.id || c.id)
    |> emit(%Events.RoundTurnSpent{
      actor: c.actor,
      at: c.at,
      id: r.id || c.id,
      thread: live.thread,
      turn_id: turn_id,
      resident_id: live.resident_id,
      round: live.round,
      outcome: outcome
    })
    |> next_turn(c, live.thread)
  end

  # Least-recent post first (never posted, first of all), then by id;
  # most-recent the other way; random, a hash of the round, stable.
  defp ordered(members, t, thread) do
    case t.ordering do
      "most_recent" ->
        Enum.sort_by(members, &{-at(t.last_post[&1]), &1})

      "random" ->
        Enum.sort_by(members, &:erlang.phash2({thread, t.round + 1, &1}))

      _least_recent ->
        Enum.sort_by(members, &{at(t.last_post[&1]), &1})
    end
  end

  # A post's @mentions go first in the round it starts (gaia#59; the
  # witness, 2026-11-19: "@mention still starts a round, just with the @ed
  # person going first"), in the order they were named; the rest follow
  # as the ordering has them. Never narrowed: whoever is not named keeps
  # a turn.
  defp mentioned_first([], order), do: order

  defp mentioned_first(first, order) do
    named = Enum.filter(Enum.uniq(first), &(&1 in order))
    named ++ (order -- named)
  end

  defp at(nil), do: 0
  defp at(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)

  defp new_thread(order),
    do: %{
      round: 0,
      order: [],
      had: MapSet.new(),
      granted: MapSet.new(),
      output: false,
      stopped: false,
      optout: MapSet.new(),
      live: nil,
      residents: [],
      timeout: 300,
      ordering: order || "least_recent",
      last_post: %{}
    }

  defp put_thread(r, thread, t), do: %{r | threads: Map.put(r.threads, thread, t)}

  defp update_thread(r, thread, fun),
    do: put_thread(r, thread, fun.(Map.get(r.threads, thread) || new_thread(nil)))

  # ---- apply ----

  def apply(%__MODULE__{} = r, %Events.RoundStarted{} = e) do
    r = %{r | id: e.id}

    update_thread(r, e.thread, fn t ->
      %{
        t
        | round: e.round,
          order: e.order,
          residents: e.residents || t.residents,
          timeout: e.timeout || t.timeout,
          ordering: e.ordering || t.ordering,
          had: MapSet.new(e.had),
          granted: MapSet.new(),
          output: e.had != [],
          stopped: false,
          live: nil,
          last_post: Enum.reduce(e.had, t.last_post, &Map.put(&2, &1, e.at))
      }
    end)
  end

  def apply(%__MODULE__{} = r, %Events.RoundTurnIssued{} = e) do
    r = %{
      r
      | live:
          Map.put(r.live, e.turn_id, %{
            thread: e.thread,
            resident_id: e.resident_id,
            round: e.round,
            expires_at: e.expires_at
          }),
        next_turn: String.to_integer(e.turn_id) + 1
    }

    update_thread(r, e.thread, &%{&1 | live: e.turn_id})
  end

  def apply(%__MODULE__{} = r, %Events.RoundTurnSpent{} = e) do
    r = %{r | live: Map.delete(r.live, e.turn_id)}

    update_thread(r, e.thread, fn t ->
      posted = e.outcome == "posted"

      %{
        t
        | had: MapSet.put(t.had, e.resident_id),
          output: t.output or posted,
          live: if(t.live == e.turn_id, do: nil, else: t.live),
          last_post: if(posted, do: Map.put(t.last_post, e.resident_id, e.at), else: t.last_post)
      }
    end)
  end

  def apply(%__MODULE__{} = r, %Events.RoundTurnsGranted{} = e),
    do: update_thread(r, e.thread, &Map.put(&1, :granted, MapSet.new(e.residents || [])))

  def apply(%__MODULE__{} = r, %Events.RoundsStopped{} = e),
    do: update_thread(r, e.thread, &%{&1 | stopped: true, live: nil})

  def apply(%__MODULE__{} = r, %Events.RoundsOptedOut{} = e),
    do:
      update_thread(
        %{r | id: e.id},
        e.thread,
        &%{&1 | optout: MapSet.put(&1.optout, e.resident_id)}
      )

  def apply(%__MODULE__{} = r, %Events.RoundsOptedIn{} = e),
    do: update_thread(r, e.thread, &%{&1 | optout: MapSet.delete(&1.optout, e.resident_id)})
end

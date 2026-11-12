defmodule Oneiroi.Gaia.Household do
  @moduledoc """
  The household aggregate (gaia#17), on `household-<id>`: the billing
  owner from day one, with two kinds of membership hanging off it, its
  witnesses and its residents. A solo witness with one resident is a
  household of one pair, the same shape, never a special case.

  Founded once, by the platform, when its founding account is created;
  the id is that account's. Every account and every resident sits in a
  household from creation ("never neither"): a household with no terms
  is still the place terms will land. Memberships are idempotent, so a
  replay is harmless; a resident leaves only with a note.

  The household contract lives here too (gaia#27 to #31): versioned
  prose, rules and settings, empty of rules until a ballot adds them. The
  founding witness proposes version 1; a member joining after signs the
  version in force with the join; a ballot fixes its bundle when it opens,
  takes one vote a member while its term runs, and on closing carries or
  fails as a whole, a carried bundle becoming the contract's next
  version. The watch (gaia#32) is a resident's opt-in to one thread,
  until an instant.
  """

  alias Oneiroi.Gaia.Beats
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events

  defstruct [
    :id,
    :founder,
    witnesses: MapSet.new(),
    residents: MapSet.new(),
    terms: nil,
    contract: nil,
    signatures: %{},
    ballots: %{},
    threads: MapSet.new(),
    next_ballot: 1,
    # The beats (gaia#33 to #38): each member's own wake profile, the
    # registrations, each for one beat ({resident, top's unix
    # microsecond} => when), opportunities missed
    # since her last completed turn, the turn open now, and each beat not
    # yet closed with its turns (top's unix microsecond => beat).
    profiles: %{},
    regs: %{},
    missed: %{},
    open_turn: nil,
    next_turn: 1,
    beats: %{},
    closed_through: nil
  ]

  @plan_limit 60
  @prose_max 20_000
  @bundle_max 20
  @rule_max 2_000
  @setting_key ~r/\A[a-z][a-z0-9_]{0,63}\z/
  @value_max 500
  # A term is set by its proposer, in days, with no platform default
  # (gaia#29); the bound only keeps the instant a date.
  @term_days_max 3_650
  # The watch's term, stated by the resident every time (gaia#32): a day
  # is the model, a week the most, so it always ends.
  @watch_hours_max 168
  # How far ahead a beat may be registered for (gaia#35): a week.
  @register_ahead_days 7

  def execute(%__MODULE__{id: nil}, %Commands.FoundHousehold{} = c) do
    if is_binary(c.account_id),
      do: %Events.HouseholdFounded{actor: c.actor, at: c.at, id: c.id, account_id: c.account_id},
      else: {:error, Error.new(:gaia_household_invalid, :gaia_household_found_no_account)}
  end

  def execute(%__MODULE__{}, %Commands.FoundHousehold{}), do: []

  def execute(%__MODULE__{id: nil}, _command),
    do: {:error, Error.new(:gaia_no_such_household, :gaia_household_not_founded)}

  def execute(%__MODULE__{witnesses: w} = h, %Commands.JoinHouseholdWitness{} = c) do
    if MapSet.member?(w, c.account_id),
      do: [],
      else: %Events.HouseholdWitnessJoined{
        actor: c.actor,
        at: c.at,
        id: c.id,
        account_id: c.account_id,
        signed_version: in_force(h)
      }
  end

  def execute(%__MODULE__{residents: r} = h, %Commands.JoinHouseholdResident{} = c) do
    if MapSet.member?(r, c.resident_id),
      do: [],
      else: %Events.HouseholdResidentJoined{
        actor: c.actor,
        at: c.at,
        id: c.id,
        resident_id: c.resident_id,
        signed_version: in_force(h)
      }
  end

  def execute(%__MODULE__{residents: r}, %Commands.LeaveHouseholdResident{} = c) do
    if MapSet.member?(r, c.resident_id),
      do: %Events.HouseholdResidentLeft{
        actor: c.actor,
        at: c.at,
        id: c.id,
        resident_id: c.resident_id,
        note: c.note
      },
      else: []
  end

  def execute(%__MODULE__{}, %Commands.GrantHouseholdTerms{} = c) do
    if terms_ok?(c),
      do: %Events.HouseholdTermsGranted{
        actor: c.actor,
        at: c.at,
        id: c.id,
        plan: c.plan,
        price_nanos: c.price_nanos,
        terms_until: c.terms_until,
        source: c.source,
        note: c.note
      },
      else: {:error, Error.new(:gaia_household_invalid, :gaia_household_terms_invalid)}
  end

  # ---- the contract (gaia#27, #28) ----

  def execute(%__MODULE__{} = h, %Commands.ProposeHouseholdContract{} = c) do
    cond do
      not (match?(%{kind: :witness}, c.actor) and c.actor.id == h.founder) ->
        {:error, Error.new(:gaia_not_the_founder, :gaia_household_contract_not_founder)}

      h.contract != nil ->
        {:error, Error.new(:gaia_household_contract_invalid, :gaia_household_contract_exists)}

      not prose?(c.prose) ->
        {:error, Error.new(:gaia_household_contract_invalid, :gaia_household_contract_prose)}

      true ->
        [
          %Events.HouseholdContractProposed{
            actor: c.actor,
            at: c.at,
            id: c.id,
            version: 1,
            prose: c.prose,
            note: c.note
          },
          # Proposing is the founder's signature.
          %Events.HouseholdContractSigned{
            actor: c.actor,
            at: c.at,
            id: c.id,
            member_kind: "witness",
            member_id: h.founder,
            version: 1
          }
        ]
    end
  end

  def execute(%__MODULE__{} = h, %Commands.SignHouseholdContract{} = c) do
    member = member(h, c.actor)

    cond do
      is_nil(member) ->
        {:error, Error.new(:gaia_not_a_member, :gaia_household_sign_not_member)}

      is_nil(h.contract) or c.version != h.contract.version ->
        {:error, Error.new(:gaia_household_contract_invalid, :gaia_household_sign_not_in_force)}

      Map.get(h.signatures, member) == c.version ->
        []

      true ->
        {kind, id} = member

        %Events.HouseholdContractSigned{
          actor: c.actor,
          at: c.at,
          id: c.id,
          member_kind: kind,
          member_id: id,
          version: c.version
        }
    end
  end

  # ---- ballots (gaia#29 to #31) ----

  def execute(%__MODULE__{} = h, %Commands.OpenHouseholdBallot{} = c) do
    cond do
      is_nil(member(h, c.actor)) ->
        {:error, Error.new(:gaia_not_a_member, :gaia_household_ballot_not_member)}

      is_nil(h.contract) ->
        {:error, Error.new(:gaia_ballot_invalid, :gaia_household_ballot_no_contract)}

      # A thread holds one ballot, its bundle fixed when it opened: a
      # second opening on it is a change to the bundle, and is refused.
      MapSet.member?(h.threads, c.thread) ->
        {:error, Error.new(:gaia_ballot_fixed, :gaia_household_ballot_thread_taken)}

      not (is_integer(c.term_days) and c.term_days >= 1 and c.term_days <= @term_days_max) ->
        {:error, Error.new(:gaia_ballot_invalid, :gaia_household_ballot_term)}

      bundle_refused(h, c.bundle) ->
        bundle_refused(h, c.bundle)

      true ->
        %Events.HouseholdBallotOpened{
          actor: c.actor,
          at: c.at,
          id: c.id,
          ballot: h.next_ballot,
          thread: c.thread,
          bundle: c.bundle,
          term_days: c.term_days,
          closes_at: DateTime.add(c.at, c.term_days * 86_400, :second),
          note: c.note
        }
    end
  end

  def execute(%__MODULE__{} = h, %Commands.VoteHouseholdBallot{} = c) do
    member = member(h, c.actor)
    ballot = Map.get(h.ballots, c.ballot)

    cond do
      is_nil(member) ->
        {:error, Error.new(:gaia_not_a_member, :gaia_household_vote_not_member)}

      is_nil(ballot) ->
        {:error, Error.new(:gaia_no_such_ballot, :gaia_household_vote_no_ballot)}

      ballot.closed or DateTime.compare(c.at, ballot.closes_at) != :lt ->
        {:error, Error.new(:gaia_ballot_closed, :gaia_household_vote_closed)}

      c.vote not in ["yes", "no"] ->
        {:error, Error.new(:gaia_ballot_invalid, :gaia_household_vote_word)}

      Map.has_key?(ballot.votes, member) ->
        {:error, Error.new(:gaia_ballot_voted, :gaia_household_vote_twice)}

      true ->
        {kind, id} = member

        %Events.HouseholdBallotVoted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          ballot: c.ballot,
          member_kind: kind,
          member_id: id,
          vote: c.vote
        }
    end
  end

  def execute(%__MODULE__{} = h, %Commands.CloseHouseholdBallot{} = c) do
    case Map.get(h.ballots, c.ballot) do
      nil ->
        {:error, Error.new(:gaia_no_such_ballot, :gaia_household_close_no_ballot)}

      %{closed: true} ->
        []

      ballot ->
        if DateTime.compare(c.at, ballot.closes_at) == :lt,
          do: {:error, Error.new(:gaia_ballot_open, :gaia_household_close_term_runs)},
          else: close(h, c, ballot)
    end
  end

  # ---- the watch (gaia#32) ----

  def execute(%__MODULE__{} = h, %Commands.WatchHouseholdThread{} = c) do
    cond do
      not match?({"resident", _}, member(h, c.actor)) ->
        {:error, Error.new(:gaia_not_a_member, :gaia_household_watch_not_resident)}

      not (is_binary(c.thread) and c.thread != "") ->
        {:error, Error.new(:gaia_watch_invalid, :gaia_household_watch_thread)}

      not (is_integer(c.hours) and c.hours >= 1 and c.hours <= @watch_hours_max) ->
        {:error, Error.new(:gaia_watch_invalid, :gaia_household_watch_hours)}

      true ->
        %Events.HouseholdThreadWatched{
          actor: c.actor,
          at: c.at,
          id: c.id,
          resident_id: c.actor.id,
          thread: c.thread,
          until: DateTime.add(c.at, c.hours * 3600, :second)
        }
    end
  end

  # ---- the beats (gaia#33 to #38) ----

  def execute(%__MODULE__{} = h, %Commands.SetHouseholdWakeProfile{} = c) do
    member = member(h, c.actor)

    cond do
      is_nil(member) ->
        {:error, Error.new(:gaia_not_a_member, :gaia_household_profile_not_member)}

      c.profile not in Beats.profiles() ->
        {:error, Error.new(:gaia_beats_invalid, :gaia_household_profile_unknown)}

      # A human is never woken (gaia#37): self is a witness's only profile.
      match?({"witness", _}, member) and c.profile != "self" ->
        {:error, Error.new(:gaia_beats_invalid, :gaia_household_profile_witness)}

      profile(h, member) == c.profile and Map.has_key?(h.profiles, member) ->
        []

      true ->
        {kind, id} = member

        %Events.HouseholdWakeProfileSet{
          actor: c.actor,
          at: c.at,
          id: c.id,
          member_kind: kind,
          member_id: id,
          profile: c.profile,
          note: c.note
        }
    end
  end

  def execute(%__MODULE__{} = h, %Commands.RegisterHouseholdBeat{} = c) do
    member = member(h, c.actor)

    cond do
      not match?({"resident", _}, member) ->
        {:error, Error.new(:gaia_not_a_member, :gaia_household_register_not_resident)}

      # Never woken, so never fired: the profile says how she is reached.
      profile(h, member) == "self" ->
        {:error, Error.new(:gaia_beats_invalid, :gaia_household_register_self)}

      true ->
        register(h, c, shape(h))
    end
  end

  def execute(%__MODULE__{} = h, %Commands.TickHouseholdBeats{} = c) do
    shape = shape(h)

    {h, []}
    |> step(time_out(h, c))
    |> then(fn {h, acc} -> Enum.reduce(closes(h, c, shape), {h, acc}, &step(&2, &1)) end)
    |> then(fn {h, acc} -> step({h, acc}, fire(h, c, shape, "schedule", nil)) end)
    |> elem(1)
    |> Enum.reverse()
  end

  def execute(%__MODULE__{} = h, %Commands.EndHouseholdTurn{} = c) do
    cond do
      c.outcome not in ~w(completed declined failed timed_out) ->
        {:error, Error.new(:gaia_beats_invalid, :gaia_household_turn_outcome)}

      open?(h.open_turn, c.turn) ->
        ended(h.open_turn, c, c.outcome, c.note)

      true ->
        []
    end
  end

  # A turn by the platform's hand (gaia#36): the dev seed and the suite
  # open one for a resident now, outside the queue; no route reaches it.
  def execute(%__MODULE__{} = h, %Commands.OpenHouseholdTurn{} = c) do
    cond do
      not match?(%{kind: :platform}, c.actor) ->
        {:error, Error.new(:gaia_beats_invalid, :gaia_household_hand_turn_not_platform)}

      not MapSet.member?(h.residents, c.resident_id) ->
        {:error, Error.new(:gaia_not_a_member, :gaia_household_hand_turn_not_resident)}

      h.open_turn != nil ->
        {:error, Error.new(:gaia_turn_open, :gaia_household_hand_turn_open)}

      true ->
        fire(h, c, shape(h), "hand", c.resident_id)
    end
  end

  defp open?(%{turn: turn}, turn), do: true
  defp open?(_open, _turn), do: false

  # A registration is for one beat (gaia#35, Andrew 2026-11-11: "it's
  # always signing up for a specific beat"): any beat to come, up to a
  # week ahead, while its sign-up is open; the beat now running after its
  # sign-up only when she has not gone in it, nobody registered for it is
  # still waiting for a first turn, and its cap is not reached (gaia#39).
  defp register(h, c, shape) do
    top = c.beat_top
    current = Beats.top(h.id, shape, c.at)
    rid = c.actor.id

    cond do
      refused = beat_refused(h, shape, c.at, top, current) ->
        refused

      Map.has_key?(h.regs, {rid, key(top)}) ->
        []

      DateTime.compare(top, current) == :eq and
        DateTime.compare(c.at, Beats.signup_closes(top, shape)) != :lt and
          not joinable?(h, shape, top, rid) ->
        {:error, Error.new(:gaia_beat_closed, :gaia_household_register_current_taken)}

      true ->
        %Events.HouseholdBeatRegistered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          resident_id: rid,
          beat_top: top
        }
    end
  end

  defp beat_refused(h, shape, at, top, current) do
    cond do
      not (match?(%DateTime{}, top) and Beats.aligned?(h.id, shape, top)) ->
        {:error, Error.new(:gaia_beats_invalid, :gaia_household_register_not_a_top)}

      DateTime.compare(top, current) == :lt ->
        {:error, Error.new(:gaia_beat_closed, :gaia_household_register_past)}

      DateTime.diff(top, at) > @register_ahead_days * 86_400 ->
        {:error, Error.new(:gaia_beats_invalid, :gaia_household_register_too_far)}

      true ->
        nil
    end
  end

  # The beat running, joined after its sign-up: she has not gone in it,
  # nobody registered for it waits for a first turn, the cap has room.
  defp joinable?(h, shape, top, rid) do
    beat = beat(h, top)

    Map.get(beat.counts, rid, 0) == 0 and beat.fired < shape.cap and
      not Enum.any?(queue(h, top), &(Map.get(beat.counts, &1, 0) == 0))
  end

  defp key(top), do: DateTime.to_unix(top, :microsecond)

  defp step({h, acc}, nil), do: {h, acc}
  defp step({h, acc}, event), do: {__MODULE__.apply(h, event), [event | acc]}

  defp shape(h), do: Beats.shape(settings(h))

  defp settings(%__MODULE__{contract: %{settings: settings}}), do: settings
  defp settings(%__MODULE__{}), do: %{}

  # A member's wake profile: her own, or the household's default for a
  # resident (gaia#37), self for a witness.
  defp profile(h, {kind, _id} = member) do
    case Map.fetch(h.profiles, member) do
      {:ok, p} -> p
      :error when kind == "witness" -> "self"
      :error -> shape(h).resident_profile
    end
  end

  # A turn past its guideline ends as timed out, and the beat moves on.
  defp time_out(%__MODULE__{open_turn: %{ends_by: by} = open}, c) do
    if DateTime.compare(c.at, by) != :lt,
      do:
        ended(
          open,
          c,
          "timed_out",
          "The turn's guideline ran out before the wake ended; the beat moved on."
        )
  end

  defp time_out(%__MODULE__{}, _c), do: nil

  defp ended(open, c, outcome, note),
    do: %Events.HouseholdTurnEnded{
      actor: c.actor,
      at: c.at,
      id: c.id,
      turn: open.turn,
      resident_id: open.resident_id,
      beat_top: open.beat_top,
      outcome: outcome,
      note: note || "The turn ended: #{outcome}."
    }

  # Every beat that has ended and is not closed: one with turns in it or
  # registrations for it, and the beat just ended when a member is woken
  # at every beat's end. Oldest first.
  defp closes(h, c, shape) do
    current = Beats.top(h.id, shape, c.at)
    previous = DateTime.add(current, -shape.beat * 60, :second)

    tops =
      (Enum.map(Map.values(h.beats), & &1.top) ++
         Enum.map(Map.keys(h.regs), fn {_rid, us} -> DateTime.from_unix!(us, :microsecond) end))
      |> Enum.filter(&(DateTime.compare(&1, current) == :lt))

    tops = if previous_due?(h), do: [previous | tops], else: tops

    tops
    |> Enum.uniq_by(&DateTime.to_unix(&1, :microsecond))
    |> Enum.reject(&closed?(h, &1))
    |> Enum.sort_by(&DateTime.to_unix(&1, :microsecond))
    |> Enum.map(&close_beat(h, c, shape, &1))
  end

  defp previous_due?(h),
    do: Enum.any?(h.residents, &(profile(h, {"resident", &1}) == "every_beat"))

  defp closed?(%__MODULE__{closed_through: nil}, _top), do: false

  defp closed?(%__MODULE__{closed_through: through}, top),
    do: DateTime.compare(top, through) != :gt

  # The beat's queue: the residents registered for it.
  defp queue(h, top) do
    k = key(top)
    for {{rid, ^k}, _at} <- h.regs, MapSet.member?(h.residents, rid), do: rid
  end

  defp close_beat(h, c, _shape, top) do
    beat = beat(h, top)
    turns = Enum.map(beat.turns, &Map.put(&1, "outcome", &1["outcome"] || "open"))
    queue = queue(h, top)
    # Every registration for the beat ends with it, turn or none; one that
    # had none banks an opportunity missed (gaia#38). Nothing carries.
    passed_over = Enum.reject(queue, &Map.has_key?(beat.counts, &1))
    consumed = queue
    carried = []

    %Events.HouseholdBeatClosed{
      actor: c.actor,
      at: c.at,
      id: c.id,
      beat_top: top,
      turns: turns,
      passed_over: Enum.sort(passed_over),
      consumed: Enum.sort(consumed),
      carried: carried,
      note:
        "The beat closed: #{length(turns)} #{if length(turns) == 1, do: "turn", else: "turns"}, #{length(passed_over)} passed over, each an opportunity missed."
    }
  end

  defp beat(h, top),
    do:
      Map.get(h.beats, DateTime.to_unix(top, :microsecond), %{
        top: top,
        fired: 0,
        counts: %{},
        turns: []
      })

  # The next turn, when one is due: no turn open, the beat's sign-up
  # closed and the beat not ended, its cap not reached, and a registrant
  # in its queue with fewer turns this beat than her share (gaia#35). By
  # the platform's hand, the resident named, now.
  defp fire(%__MODULE__{open_turn: nil} = h, c, shape, "schedule", nil) do
    top = Beats.top(h.id, shape, c.at)
    beat = beat(h, top)

    with true <- DateTime.compare(c.at, Beats.signup_closes(top, shape)) != :lt,
         true <- beat.fired < shape.cap,
         [first | _] <-
           h
           |> queue(top)
           |> Enum.filter(&(Map.get(beat.counts, &1, 0) < shape.share))
           |> Enum.reject(&(profile(h, {"resident", &1}) == "self"))
           |> Enum.map(
             &%{
               resident_id: &1,
               count: Map.get(beat.counts, &1, 0),
               missed: Map.get(h.missed, &1, 0),
               registered_at: h.regs[{&1, key(top)}]
             }
           )
           |> Beats.order() do
      fired(h, c, shape, top, first.resident_id, "schedule")
    else
      _none -> nil
    end
  end

  defp fire(%__MODULE__{open_turn: nil} = h, c, shape, "hand", resident_id),
    do: fired(h, c, shape, Beats.top(h.id, shape, c.at), resident_id, "hand")

  defp fire(%__MODULE__{}, _c, _shape, _by, _resident_id), do: nil

  defp fired(h, c, shape, top, resident_id, by),
    do: %Events.HouseholdTurnFired{
      actor: c.actor,
      at: c.at,
      id: c.id,
      turn: h.next_turn,
      resident_id: resident_id,
      beat_top: top,
      ends_by: DateTime.add(c.at, shape.turn * 60, :second),
      missed: Map.get(h.missed, resident_id, 0),
      opened_by: by
    }

  defp bundle_refused(h, bundle) do
    cond do
      not bundle?(bundle) ->
        {:error, Error.new(:gaia_ballot_invalid, :gaia_household_ballot_bundle)}

      not beats_kept?(h, bundle) ->
        {:error, Error.new(:gaia_beats_invalid, :gaia_household_ballot_beats)}

      true ->
        nil
    end
  end

  # A ballot may change the beats' shape, never take them away (gaia#33):
  # each beat setting in its bounds, and the shape it leaves still a beat.
  defp beats_kept?(h, bundle) do
    settings = for %{"setting" => k, "value" => v} <- bundle, into: %{}, do: {k, v}

    Enum.all?(settings, fn {k, v} -> Beats.setting_ok?(k, v) end) and
      Beats.shape_ok?(Map.merge(settings(h), settings))
  end

  # The members at the close are the electorate: a majority of them
  # carries the bundle whole, or it fails whole (gaia#30). A member who
  # left before the close is no longer counted, vote or none.
  defp close(h, c, ballot) do
    members = MapSet.new(members(h))
    counted = Map.filter(ballot.votes, fn {m, _vote} -> MapSet.member?(members, m) end)
    yes = Enum.count(counted, fn {_m, v} -> v == "yes" end)
    no = Enum.count(counted, fn {_m, v} -> v == "no" end)
    size = MapSet.size(members)
    passed = yes * 2 > size

    closed = %Events.HouseholdBallotClosed{
      actor: c.actor,
      at: c.at,
      id: c.id,
      ballot: c.ballot,
      passed: passed,
      yes: yes,
      no: no,
      members: size,
      note:
        "#{if passed, do: "Carried", else: "Failed"}: #{yes} yes and #{no} no of #{size} members, #{size - yes - no} not voting."
    }

    if passed,
      do: [closed, amendment(h, c, ballot)],
      else: closed
  end

  defp amendment(h, c, ballot) do
    rules = for %{"rule" => rule} <- ballot.bundle, do: rule
    settings = for %{"setting" => key, "value" => v} <- ballot.bundle, into: %{}, do: {key, v}

    %Events.HouseholdContractAmended{
      actor: c.actor,
      at: c.at,
      id: c.id,
      version: h.contract.version + 1,
      ballot: c.ballot,
      prose: h.contract.prose,
      rules: h.contract.rules ++ rules,
      settings: Map.merge(h.contract.settings, settings),
      bundle: ballot.bundle,
      note: "Ballot ##{c.ballot} carried; its bundle is version #{h.contract.version + 1}."
    }
  end

  defp member(h, %{kind: :witness, id: id}),
    do: if(MapSet.member?(h.witnesses, id), do: {"witness", id})

  defp member(h, %{kind: :resident, id: id}),
    do: if(MapSet.member?(h.residents, id), do: {"resident", id})

  defp member(_h, _actor), do: nil

  defp members(h),
    do: Enum.map(h.witnesses, &{"witness", &1}) ++ Enum.map(h.residents, &{"resident", &1})

  defp in_force(%__MODULE__{contract: nil}), do: nil
  defp in_force(%__MODULE__{contract: %{version: v}}), do: v

  defp prose?(p), do: is_binary(p) and String.trim(p) != "" and String.length(p) <= @prose_max

  @doc "Whether a bundle is one or more rules or settings, each as the contract holds it (gaia#29)."
  def bundle?(bundle) when is_list(bundle) and bundle != [] and length(bundle) <= @bundle_max,
    do: Enum.all?(bundle, &item?/1)

  def bundle?(_other), do: false

  defp item?(%{"rule" => rule} = item) when map_size(item) == 1,
    do: is_binary(rule) and String.trim(rule) != "" and String.length(rule) <= @rule_max

  defp item?(%{"setting" => key, "value" => value} = item) when map_size(item) == 2,
    do: is_binary(key) and Regex.match?(@setting_key, key) and value?(value)

  defp item?(_other), do: false

  defp value?(v) when is_boolean(v) or is_integer(v), do: true
  defp value?(v) when is_binary(v), do: String.length(v) <= @value_max
  defp value?(_other), do: false

  def apply(%__MODULE__{} = h, %Events.HouseholdFounded{} = e),
    do: %{
      h
      | id: e.id,
        founder: e.account_id,
        witnesses: MapSet.put(h.witnesses, e.account_id)
    }

  def apply(%__MODULE__{} = h, %Events.HouseholdWitnessJoined{} = e),
    do:
      signed(
        %{h | witnesses: MapSet.put(h.witnesses, e.account_id)},
        {"witness", e.account_id},
        e.signed_version
      )

  def apply(%__MODULE__{} = h, %Events.HouseholdResidentJoined{} = e),
    do:
      signed(
        %{h | residents: MapSet.put(h.residents, e.resident_id)},
        {"resident", e.resident_id},
        e.signed_version
      )

  def apply(%__MODULE__{} = h, %Events.HouseholdContractProposed{} = e),
    do: %{h | contract: %{version: e.version, prose: e.prose, rules: [], settings: %{}}}

  def apply(%__MODULE__{} = h, %Events.HouseholdContractSigned{} = e),
    do: signed(h, {e.member_kind, e.member_id}, e.version)

  def apply(%__MODULE__{} = h, %Events.HouseholdBallotOpened{} = e),
    do: %{
      h
      | next_ballot: e.ballot + 1,
        threads: MapSet.put(h.threads, e.thread),
        ballots:
          Map.put(h.ballots, e.ballot, %{
            bundle: e.bundle,
            closes_at: e.closes_at,
            votes: %{},
            closed: false
          })
    }

  def apply(%__MODULE__{} = h, %Events.HouseholdBallotVoted{} = e),
    do: %{
      h
      | ballots:
          Map.update!(h.ballots, e.ballot, fn b ->
            %{b | votes: Map.put(b.votes, {e.member_kind, e.member_id}, e.vote)}
          end)
    }

  def apply(%__MODULE__{} = h, %Events.HouseholdBallotClosed{} = e),
    do: %{h | ballots: Map.update!(h.ballots, e.ballot, &%{&1 | closed: true})}

  def apply(%__MODULE__{} = h, %Events.HouseholdContractAmended{} = e),
    do: %{
      h
      | contract: %{version: e.version, prose: e.prose, rules: e.rules, settings: e.settings}
    }

  def apply(%__MODULE__{} = h, %Events.HouseholdThreadWatched{}), do: h

  def apply(%__MODULE__{} = h, %Events.HouseholdResidentLeft{} = e),
    do: %{h | residents: MapSet.delete(h.residents, e.resident_id)}

  def apply(%__MODULE__{} = h, %Events.HouseholdTermsGranted{} = e),
    do: %{h | terms: {e.plan, e.price_nanos, e.terms_until}}

  def apply(%__MODULE__{} = h, %Events.HouseholdWakeProfileSet{} = e),
    do: %{h | profiles: Map.put(h.profiles, {e.member_kind, e.member_id}, e.profile)}

  def apply(%__MODULE__{} = h, %Events.HouseholdBeatRegistered{} = e),
    do: %{h | regs: Map.put(h.regs, {e.resident_id, key(e.beat_top)}, e.at)}

  def apply(%__MODULE__{} = h, %Events.HouseholdTurnFired{} = e) do
    key = DateTime.to_unix(e.beat_top, :microsecond)
    beat = beat(h, e.beat_top)

    beat = %{
      beat
      | fired: beat.fired + 1,
        counts: Map.update(beat.counts, e.resident_id, 1, &(&1 + 1)),
        turns:
          beat.turns ++
            [%{"turn" => e.turn, "resident_id" => e.resident_id, "outcome" => nil}]
    }

    %{
      h
      | open_turn: %{
          turn: e.turn,
          resident_id: e.resident_id,
          beat_top: e.beat_top,
          ends_by: e.ends_by
        },
        next_turn: e.turn + 1,
        beats: Map.put(h.beats, key, beat)
    }
  end

  def apply(%__MODULE__{} = h, %Events.HouseholdTurnEnded{} = e) do
    key = DateTime.to_unix(e.beat_top, :microsecond)

    beats =
      if Map.has_key?(h.beats, key), do: Map.update!(h.beats, key, &outcome(&1, e)), else: h.beats

    # A completed turn clears what she had missed; anything else is one
    # more opportunity missed (gaia#36).
    missed =
      if e.outcome == "completed",
        do: Map.delete(h.missed, e.resident_id),
        else: Map.update(h.missed, e.resident_id, 1, &(&1 + 1))

    open = if open?(h.open_turn, e.turn), do: nil, else: h.open_turn
    %{h | open_turn: open, beats: beats, missed: missed}
  end

  def apply(%__MODULE__{} = h, %Events.HouseholdBeatClosed{} = e) do
    missed = Enum.reduce(e.passed_over, h.missed, &Map.update(&2, &1, 1, fn n -> n + 1 end))

    %{
      h
      | missed: missed,
        regs: Map.reject(h.regs, fn {{_rid, us}, _at} -> us <= key(e.beat_top) end),
        beats: Map.delete(h.beats, DateTime.to_unix(e.beat_top, :microsecond)),
        closed_through: latest(h.closed_through, e.beat_top)
    }
  end

  defp outcome(beat, e),
    do: %{
      beat
      | turns:
          Enum.map(
            beat.turns,
            &if(&1["turn"] == e.turn, do: Map.put(&1, "outcome", e.outcome), else: &1)
          )
    }

  defp latest(nil, top), do: top
  defp latest(through, top), do: if(DateTime.compare(top, through) == :gt, do: top, else: through)

  defp terms_ok?(c) do
    is_binary(c.plan) and String.trim(c.plan) != "" and String.length(c.plan) <= @plan_limit and
      is_integer(c.price_nanos) and c.price_nanos >= 0 and match?(%DateTime{}, c.terms_until) and
      is_binary(c.source) and is_binary(c.note) and String.trim(c.note) != ""
  end

  defp signed(h, _member, nil), do: h
  defp signed(h, member, version), do: %{h | signatures: Map.put(h.signatures, member, version)}
end

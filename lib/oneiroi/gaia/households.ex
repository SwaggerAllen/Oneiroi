defmodule Oneiroi.Gaia.Households do
  @moduledoc """
  The household's service functions (gaia#17): which household an
  account is in, the household as its members read it, and the terms
  granted to it.

  The household row is platform-scoped, every member's and no one's
  alone, so reading it takes the platform scope by name (conventions
  §12), and only after the caller's own membership row, read under the
  caller's scope, has said which household it is.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia.Accounts
  alias Oneiroi.Gaia.Beats
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Door
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.HouseholdRouter
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @doc """
  The household the account is in: its membership's, or, before the
  projection has one, the account's own id, which is the id of the
  household it founded.
  """
  def household_id(account_id) do
    Scope.account(account_id, fn ->
      Repo.one(
        from(m in Store.HouseholdWitness,
          where: m.account_id == ^account_id,
          order_by: m.joined_at,
          limit: 1,
          select: m.household_id
        )
      )
    end) || account_id
  end

  @doc "The account's household as its members see it: who is in it and its terms, or nil before it is founded."
  def household(account_id) do
    id = household_id(account_id)

    # The named cross-tenant read: the household and its other members'
    # rows, once the caller's own membership has named it.
    Scope.platform(fn ->
      case Repo.get(Store.Household, id) do
        nil -> nil
        row -> shape(row)
      end
    end)
  end

  defp shape(row) do
    witnesses =
      Repo.all(
        from(m in Store.HouseholdWitness,
          where: m.household_id == ^row.id,
          order_by: m.joined_at,
          select: m.account_id
        )
      )

    residents =
      Repo.all(
        from(m in Store.HouseholdResident,
          where: m.household_id == ^row.id,
          order_by: m.joined_at,
          select: m.resident_id
        )
      )

    %{
      id: row.id,
      founded_at: row.founded_at,
      witnesses: witnesses,
      residents: residents,
      terms: terms(row)
    }
  end

  defp terms(%{plan: nil}), do: nil

  defp terms(row),
    do: %{
      plan: row.plan,
      price_nanos: row.price_nanos,
      until: row.terms_until,
      source: row.terms_source,
      note: row.terms_note
    }

  @doc """
  Grants the household terms: a plan, its price, until when, and where
  they came from. The platform's (an invite code redeemed) or a super
  admin's; nothing is charged.
  """
  def grant_terms(household_id, terms, note, %Actor{} = actor) do
    with :ok <- may_grant(actor) do
      dispatch(%Commands.GrantHouseholdTerms{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        plan: terms.plan,
        price_nanos: terms.price_nanos,
        terms_until: terms.until,
        source: terms.source,
        note: note
      })
    end
  end

  defp may_grant(%Actor{kind: :platform}), do: :ok

  defp may_grant(%Actor{kind: :witness, id: id}) do
    if Door.operator?(id),
      do: :ok,
      else: {:error, Error.new(:gaia_not_an_operator, :gaia_household_terms_not_operator)}
  end

  defp may_grant(%Actor{}),
    do: {:error, Error.new(:gaia_not_an_operator, :gaia_household_terms_not_a_witness)}

  defp dispatch(command) do
    case HouseholdRouter.dispatch(command) do
      {:ok, _events} ->
        :ok

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:gaia_dispatch_failed, :gaia_household_dispatch_failed, reason)}
    end
  end

  # ---- membership, by member (gaia#27 to #32) ----

  @doc """
  The household a member is in, by the actor: a resident's from its own
  membership row, a witness's as `household_id/1` reads it. Nil for a
  resident with no household (one rebuilt and not yet placed).
  """
  def household_of(%Actor{kind: :resident, id: resident_id}),
    do: resident_household_id(resident_id)

  def household_of(%Actor{kind: :witness, id: account_id}), do: household_id(account_id)
  def household_of(%Actor{}), do: nil

  @doc "The id of the household a resident is in, or nil."
  def resident_household_id(resident_id) do
    Scope.resident(resident_id, fn ->
      Repo.one(
        from(m in Store.HouseholdResident,
          where: m.resident_id == ^resident_id,
          order_by: m.joined_at,
          limit: 1,
          select: m.household_id
        )
      )
    end)
  end

  @doc "The household a resident is in, with its members by name (`members/1`), or nil."
  def resident_household(resident_id) do
    case resident_household_id(resident_id) do
      nil -> nil
      id -> %{id: id, members: members(id)}
    end
  end

  @doc """
  The household's members, oldest first: each its kind (`witness` or
  `resident`), id, the name the house uses for it, when it joined and
  the contract version it signed. A resident by its name; a witness as
  whose witness it is, never by its email, since the names travel with
  the household's repository. Read under the platform scope by name:
  every caller has named the household through a membership first.
  """
  def members(household_id) do
    Scope.platform(fn ->
      residents =
        Repo.all(
          from(m in Store.HouseholdResident,
            where: m.household_id == ^household_id,
            order_by: m.joined_at
          )
        )

      witnesses =
        Repo.all(
          from(m in Store.HouseholdWitness,
            where: m.household_id == ^household_id,
            order_by: m.joined_at
          )
        )

      {residents, witnesses}
    end)
    |> then(fn {residents, witnesses} ->
      named = Map.new(residents, &{&1.resident_id, resident_name(&1.resident_id)})

      Enum.map(residents, &member("resident", &1.resident_id, named[&1.resident_id], &1)) ++
        Enum.map(
          witnesses,
          &member("witness", &1.account_id, witness_name(&1.account_id, named), &1)
        )
    end)
  end

  defp member(kind, id, name, row),
    do: %{
      kind: kind,
      id: id,
      name: name,
      joined_at: row.joined_at,
      signed_version: row.signed_version,
      signed_at: row.signed_at
    }

  defp resident_name(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, r} -> r.name
      _gone -> "a resident"
    end
  end

  defp witness_name(account_id, named) do
    case account_id
         |> Accounts.witnessed_residents()
         |> Enum.map(&named[&1])
         |> Enum.reject(&is_nil/1) do
      [] -> "a witness"
      names -> "#{Enum.join(names, " and ")}'s witness"
    end
  end

  @doc "Whether the actor is a member of the household: a witness or a resident in it."
  def member?(household_id, %Actor{kind: kind, id: id}) when kind in [:witness, :resident] do
    member_kind = Atom.to_string(kind)
    Enum.any?(members(household_id), &(&1.kind == member_kind and &1.id == id))
  end

  def member?(_household_id, %Actor{}), do: false

  @doc "The name the house uses for a member actor (`members/1`), or nil when it is not one."
  def member_name(household_id, %Actor{kind: kind, id: id}) do
    member_kind = Atom.to_string(kind)

    Enum.find_value(members(household_id), fn m ->
      if m.kind == member_kind and m.id == id, do: m.name
    end)
  end

  # ---- the contract (gaia#27, #28, #31) ----

  @doc """
  The household contract as the members read it: the version in force
  (nil before the founding witness proposes one), every version oldest
  first with the ballot that made it, the members with what each signed,
  and the ballots, newest first, each with its votes.
  """
  def contract(household_id) do
    {versions, ballots, votes} =
      Scope.platform(fn ->
        {Repo.all(
           from(c in Store.HouseholdContract,
             where: c.household_id == ^household_id,
             order_by: c.version
           )
         ),
         Repo.all(
           from(b in Store.HouseholdBallot,
             where: b.household_id == ^household_id,
             order_by: [desc: b.number]
           )
         ),
         Repo.all(
           from(v in Store.HouseholdVote,
             where: v.household_id == ^household_id,
             order_by: v.voted_at
           )
         )}
      end)

    members = members(household_id)
    names = Map.new(members, &{{&1.kind, &1.id}, &1.name})
    by_ballot = Enum.group_by(votes, & &1.ballot)

    %{
      household_id: household_id,
      in_force: versions |> List.last() |> version(),
      versions: Enum.map(versions, &version/1),
      members: members,
      ballots: Enum.map(ballots, &ballot(&1, Map.get(by_ballot, &1.number, []), names))
    }
  end

  defp version(nil), do: nil

  defp version(row),
    do: %{
      version: row.version,
      prose: row.prose,
      rules: row.rules,
      settings: row.settings,
      bundle: row.bundle,
      ballot: row.ballot,
      decided_by: row.decided_by,
      decided_at: row.decided_at,
      note: row.note
    }

  defp ballot(row, votes, names),
    do: %{
      number: row.number,
      thread: row.thread,
      bundle: row.bundle,
      term_days: row.term_days,
      opened_by: row.opened_by,
      opened_at: row.opened_at,
      closes_at: row.closes_at,
      note: row.note,
      closed_at: row.closed_at,
      passed: row.passed,
      yes: row.yes,
      no: row.no,
      members: row.members,
      outcome: row.outcome,
      votes:
        Enum.map(votes, fn v ->
          %{
            member_kind: v.member_kind,
            member_id: v.member_id,
            name: names[{v.member_kind, v.member_id}],
            vote: v.vote,
            voted_at: v.voted_at
          }
        end)
    }

  @doc "The ballot a thread holds, or nil."
  def ballot_for_thread(household_id, thread) do
    Enum.find(contract(household_id).ballots, &(&1.thread == thread))
  end

  @doc "The founding witness proposes version 1, prose alone, with a note (gaia#27); proposing is the founder's signature."
  def propose_contract(household_id, prose, note, %Actor{} = actor) do
    dispatch(%Commands.ProposeHouseholdContract{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      prose: prose,
      note: note
    })
  end

  @doc "A member signs the version in force (gaia#28): a member who joined before there was one."
  def sign_contract(household_id, version, %Actor{} = actor) do
    dispatch(%Commands.SignHouseholdContract{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      version: version
    })
  end

  # ---- ballots (gaia#29, #30) ----

  @doc """
  Opens a ballot on a thread (gaia#29): the bundle, one or more rules
  (`%{"rule" => text}`) or settings (`%{"setting" => key, "value" =>
  v}`), fixed here and never again; the term in days, the proposer's;
  a note saying why. Answers the ballot's number and when it closes.
  """
  def open_ballot(household_id, thread, bundle, term_days, note, %Actor{} = actor) do
    command = %Commands.OpenHouseholdBallot{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      thread: thread,
      bundle: normalize_bundle(bundle),
      term_days: term_days,
      note: note
    }

    case HouseholdRouter.dispatch(command) do
      {:ok, [%Events.HouseholdBallotOpened{} = e]} ->
        {:ok, %{ballot: e.ballot, closes_at: e.closes_at, bundle: e.bundle}}

      other ->
        refused(other)
    end
  end

  @doc "A bundle as the contract holds it: string keys, rules and settings trimmed; anything else passes through for the aggregate to refuse."
  def normalize_bundle(bundle) when is_list(bundle) do
    Enum.map(bundle, fn
      item when is_map(item) ->
        item = Map.new(item, fn {k, v} -> {to_string(k), v} end)

        case item do
          %{"rule" => rule} when is_binary(rule) and map_size(item) == 1 ->
            %{"rule" => String.trim(rule)}

          %{"setting" => key, "value" => v} when is_binary(key) and map_size(item) == 2 ->
            %{"setting" => String.trim(key), "value" => v}

          other ->
            other
        end

      other ->
        other
    end)
  end

  def normalize_bundle(other), do: other

  @doc "A member votes yes or no on an open ballot, once (gaia#30)."
  def vote(household_id, ballot, vote, %Actor{} = actor) do
    dispatch(%Commands.VoteHouseholdBallot{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      ballot: ballot,
      vote: vote
    })
  end

  @doc """
  Closes a ballot whose term has run (gaia#30, #31): the tally over the
  members at the close, and a carried bundle recorded as the contract's
  next version. Answers the outcome; a ballot closed already answers
  `{:ok, :closed}`.
  """
  def close_ballot(household_id, ballot, %Actor{} = actor) do
    command = %Commands.CloseHouseholdBallot{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      ballot: ballot
    }

    case HouseholdRouter.dispatch(command) do
      {:ok, []} ->
        {:ok, :closed}

      {:ok, [%Events.HouseholdBallotClosed{} = closed | rest]} ->
        amended = Enum.find(rest, &match?(%Events.HouseholdContractAmended{}, &1))

        {:ok,
         %{
           ballot: ballot,
           passed: closed.passed,
           yes: closed.yes,
           no: closed.no,
           members: closed.members,
           outcome: closed.note,
           version: amended && amended.version
         }}

      other ->
        refused(other)
    end
  end

  # ---- the watch (gaia#32) ----

  @doc "A resident watches one thread for the hours it states (gaia#32); answers until when."
  def watch(household_id, thread, hours, %Actor{} = actor) do
    command = %Commands.WatchHouseholdThread{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      thread: thread,
      hours: hours
    }

    case HouseholdRouter.dispatch(command) do
      {:ok, [%Events.HouseholdThreadWatched{until: until}]} -> {:ok, until}
      other -> refused(other)
    end
  end

  @doc "The residents watching a thread at `at`: each whose latest watch on it runs past that instant. Past it, nothing remains to unsubscribe."
  def watchers(household_id, thread, %DateTime{} = at) do
    Scope.platform(fn ->
      Repo.all(
        from(w in Store.HouseholdWatch,
          where: w.household_id == ^household_id and w.thread == ^thread and w.until > ^at,
          distinct: true,
          select: w.watcher_id
        )
      )
    end)
  end

  # ---- the beats (gaia#33 to #38) ----

  @doc "Every household's id, for the minute's look at the beats (gaia#33: every household runs on beats)."
  def all_ids do
    Scope.platform(fn -> Repo.all(from(h in Store.Household, select: h.id)) end)
  end

  @doc "The beats' shape in force for a household: its contract's settings over the defaults (gaia#33)."
  def beat_shape(household_id) do
    settings =
      Scope.platform(fn ->
        Repo.one(
          from(c in Store.HouseholdContract,
            where: c.household_id == ^household_id,
            order_by: [desc: c.version],
            limit: 1,
            select: c.settings
          )
        )
      end)

    Beats.shape(settings)
  end

  @doc "A member sets her own wake profile, with a note (gaia#37)."
  def set_wake_profile(household_id, profile, note, %Actor{} = actor) do
    dispatch(%Commands.SetHouseholdWakeProfile{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      profile: profile,
      note: note
    })
  end

  @doc "A resident registers for one beat, by its top (gaia#35, #39); answers it, and whether she was registered for it already."
  def register_beat(household_id, beat_top, %Actor{} = actor) do
    command = %Commands.RegisterHouseholdBeat{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      beat_top: beat_top
    }

    case HouseholdRouter.dispatch(command) do
      {:ok, [%Events.HouseholdBeatRegistered{beat_top: top}]} ->
        {:ok, %{beat_top: top, already: false}}

      {:ok, []} ->
        {:ok, %{beat_top: beat_top, already: true}}

      other ->
        refused(other)
    end
  end

  @doc "The minute's look at one household's beats (gaia#35, #36, #38): answers the events it recorded."
  def tick_beats(household_id, %Actor{} = actor) do
    events(%Commands.TickHouseholdBeats{actor: actor, at: Clock.now(), id: household_id})
  end

  @doc "Ends a turn with its outcome and a note (gaia#36); a turn ended already is no event."
  def end_turn(household_id, turn, outcome, note, %Actor{} = actor) do
    events(%Commands.EndHouseholdTurn{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      turn: turn,
      outcome: outcome,
      note: note
    })
  end

  @doc "The platform opens a turn for a resident now, outside the queue (gaia#36): the dev seed's and the suite's."
  def open_turn(household_id, resident_id, note, %Actor{} = actor) do
    command = %Commands.OpenHouseholdTurn{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      resident_id: resident_id,
      note: note
    }

    case HouseholdRouter.dispatch(command) do
      {:ok, [%Events.HouseholdTurnFired{} = e]} -> {:ok, turn_of(e)}
      other -> refused(other)
    end
  end

  defp events(command) do
    case HouseholdRouter.dispatch(command) do
      {:ok, events} when is_list(events) -> {:ok, events}
      other -> refused(other)
    end
  end

  @doc "A fired turn as the beats read it."
  def turn_of(%Events.HouseholdTurnFired{} = e),
    do: %{
      turn: e.turn,
      resident_id: e.resident_id,
      beat_top: e.beat_top,
      fired_at: e.at,
      ends_by: e.ends_by,
      opened_by: e.opened_by,
      missed: e.missed
    }

  @doc "One turn by its number, or nil."
  def turn(household_id, number) do
    Scope.platform(fn ->
      Repo.one(
        from(t in Store.HouseholdTurn,
          where: t.household_id == ^household_id and t.turn == ^number
        )
      )
    end)
    |> turn_row()
  end

  @doc "The turn a resident holds at `at`: fired, not ended, its guideline not run out; or nil."
  def open_turn_of(household_id, resident_id, %DateTime{} = at) do
    Scope.platform(fn ->
      Repo.one(
        from(t in Store.HouseholdTurn,
          where:
            t.household_id == ^household_id and t.speaker_id == ^resident_id and
              is_nil(t.ended_at) and t.ends_by > ^at,
          order_by: [desc: t.turn],
          limit: 1
        )
      )
    end)
    |> turn_row()
  end

  @doc "A resident's latest turn before this one, or nil."
  def last_turn(household_id, resident_id, before \\ nil) do
    Scope.platform(fn ->
      query =
        from(t in Store.HouseholdTurn,
          where: t.household_id == ^household_id and t.speaker_id == ^resident_id,
          order_by: [desc: t.turn],
          limit: 1
        )

      query = if before, do: from(t in query, where: t.turn < ^before), else: query
      Repo.one(query)
    end)
    |> turn_row()
  end

  defp turn_row(nil), do: nil

  defp turn_row(t),
    do: %{
      turn: t.turn,
      resident_id: t.speaker_id,
      beat_top: t.beat_top,
      fired_at: t.fired_at,
      ends_by: t.ends_by,
      opened_by: t.opened_by,
      missed: t.missed,
      ended_at: t.ended_at,
      outcome: t.outcome,
      note: t.note
    }

  defp member_row(household_id, kind, id) do
    Scope.platform(fn ->
      Repo.one(
        from(m in Store.HouseholdBeatMember,
          where: m.household_id == ^household_id and m.member_kind == ^kind and m.member_id == ^id
        )
      )
    end) ||
      %Store.HouseholdBeatMember{household_id: household_id, member_kind: kind, member_id: id}
  end

  @doc """
  The household's beats as its members read them at `at` (gaia#33 to
  #38): the shape and its phase; the beat now (its top, when sign-up
  closes, when it ends) and the next top; the turn open; the queue in
  the order the next turns fire, each with her position, what she has
  missed and the beat she waits for; every member's wake profile; and
  the beats closed lately, newest first.
  """
  def beats(household_id, %DateTime{} = at) do
    shape = beat_shape(household_id)
    top = Beats.top(household_id, shape, at)
    signup = Beats.signup_closes(top, shape)
    members = members(household_id)

    {rows, regs, turns, closed} =
      Scope.platform(fn ->
        {Repo.all(from(m in Store.HouseholdBeatMember, where: m.household_id == ^household_id)),
         Repo.all(
           from(r in Store.HouseholdRegistration,
             where: r.household_id == ^household_id and r.beat_top >= ^top,
             order_by: [r.beat_top, r.registered_at]
           )
         ),
         Repo.all(
           from(t in Store.HouseholdTurn,
             where: t.household_id == ^household_id and t.beat_top == ^top,
             order_by: t.turn
           )
         ),
         Repo.all(
           from(b in Store.HouseholdBeat,
             where: b.household_id == ^household_id,
             order_by: [desc: b.beat_top],
             limit: 12
           )
         )}
      end)

    rows = Map.new(rows, &{{&1.member_kind, &1.member_id}, &1})
    names = Map.new(members, &{&1.id, &1.name})
    counts = Enum.frequencies_by(turns, & &1.speaker_id)

    open =
      Enum.find_value(turns, fn t ->
        if is_nil(t.ended_at), do: turn_row(t)
      end) || open_anywhere(household_id)

    missed = for {{_kind, id}, row} <- rows, into: %{}, do: {id, row.missed}
    queue = queue(Enum.filter(regs, &(&1.beat_top == top)), missed, counts, top)

    %{
      household_id: household_id,
      shape: shape,
      phase_minutes: Beats.phase(household_id, shape.beat),
      now: at,
      beat: %{
        top: top,
        signup_closes: signup,
        ends: Beats.ends(top, shape),
        turns_fired: length(turns),
        turns: Enum.map(turns, &turn_row/1)
      },
      next_top: Beats.ends(top, shape),
      open_turn: open && Map.put(open, :name, names[open.resident_id]),
      queue: Enum.map(queue, &Map.put(&1, :name, names[&1.resident_id])),
      registrations: registrations(regs, missed, names),
      upcoming:
        Enum.map(
          Beats.upcoming(household_id, shape, at, 6),
          &%{top: &1, signup_closes: Beats.signup_closes(&1, shape)}
        ),
      profiles: Enum.map(members, &profile_of(&1, rows[{&1.kind, &1.id}], shape)),
      closed: Enum.map(closed, &closed_of/1)
    }
  end

  # The beat running's registrants in the order its turns fire (gaia#35):
  # fewest turns in it, most missed, earliest registered.
  defp queue(regs, missed, counts, top) do
    regs
    |> Enum.map(
      &%{
        resident_id: &1.speaker_id,
        registered_at: &1.registered_at,
        missed: Map.get(missed, &1.speaker_id, 0),
        count: Map.get(counts, &1.speaker_id, 0)
      }
    )
    |> Beats.order()
    |> Enum.with_index(1)
    |> Enum.map(fn {q, i} ->
      %{
        position: i,
        resident_id: q.resident_id,
        registered_at: q.registered_at,
        missed: q.missed,
        turns_this_beat: q.count,
        waits_for: top
      }
    end)
  end

  # Every registration from the beat running on, by beat, each beat's
  # registrants in the order they would fire as things stand.
  defp registrations(regs, missed, names) do
    regs
    |> Enum.group_by(& &1.beat_top)
    |> Enum.sort_by(fn {top, _} -> DateTime.to_unix(top, :microsecond) end)
    |> Enum.map(fn {top, rs} ->
      ordered =
        rs
        |> Enum.map(
          &%{
            resident_id: &1.speaker_id,
            registered_at: &1.registered_at,
            missed: Map.get(missed, &1.speaker_id, 0),
            count: 0
          }
        )
        |> Beats.order()

      %{
        beat_top: top,
        residents: Enum.map(ordered, &Map.put(&1, :name, names[&1.resident_id]))
      }
    end)
  end

  defp profile_of(m, nil, shape),
    do: %{
      kind: m.kind,
      id: m.id,
      name: m.name,
      profile: default_profile(m.kind, shape),
      missed: 0
    }

  defp profile_of(m, row, shape),
    do: %{
      kind: m.kind,
      id: m.id,
      name: m.name,
      profile: row.profile || default_profile(m.kind, shape),
      missed: row.missed
    }

  defp closed_of(b),
    do: %{
      beat_top: b.beat_top,
      closed_at: b.closed_at,
      turns: b.turns,
      passed_over: b.passed_over,
      carried: b.carried,
      note: b.note
    }

  defp default_profile("witness", _shape), do: "self"
  defp default_profile(_resident, shape), do: shape.resident_profile

  defp open_anywhere(household_id) do
    Scope.platform(fn ->
      Repo.one(
        from(t in Store.HouseholdTurn,
          where: t.household_id == ^household_id and is_nil(t.ended_at),
          order_by: [desc: t.turn],
          limit: 1
        )
      )
    end)
    |> turn_row()
  end

  @doc "A member's wake profile: her own, or the default (gaia#37)."
  def wake_profile(household_id, kind, id) do
    case member_row(household_id, kind, id) do
      %{profile: p} when is_binary(p) -> p
      _none -> default_profile(kind, beat_shape(household_id))
    end
  end

  defp refused({:error, %Error{}} = refused), do: refused

  defp refused({:error, reason}),
    do:
      {:error,
       Error.caught(:gaia_dispatch_failed, :gaia_household_contract_dispatch_failed, reason)}
end

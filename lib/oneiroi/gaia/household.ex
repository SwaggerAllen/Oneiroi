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
    next_ballot: 1
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

      not bundle?(c.bundle) ->
        {:error, Error.new(:gaia_ballot_invalid, :gaia_household_ballot_bundle)}

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

  defp terms_ok?(c) do
    is_binary(c.plan) and String.trim(c.plan) != "" and String.length(c.plan) <= @plan_limit and
      is_integer(c.price_nanos) and c.price_nanos >= 0 and match?(%DateTime{}, c.terms_until) and
      is_binary(c.source) and is_binary(c.note) and String.trim(c.note) != ""
  end

  defp signed(h, _member, nil), do: h
  defp signed(h, member, version), do: %{h | signatures: Map.put(h.signatures, member, version)}
end

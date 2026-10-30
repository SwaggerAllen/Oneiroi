defmodule Oneiroi.AgathosDaimon.Agreements do
  @moduledoc """
  The dyad contract and custody (spec §6.12): the command edge for a
  contract version proposed by one party and agreed or declined by the
  other, each with a note; a custody transfer proposed by the witness to
  another account, accepted or declined by that account or withdrawn,
  with the export wall standing as it was when the proposal was made;
  and the reads the agreement screen and the brain take. Who may do
  what is the aggregate's to say (`Oneiroi.AgathosDaimon.Resident`),
  from the actor on the command.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Scope

  # ---- the contract ----

  @doc "Proposes a contract version: the terms (a map of the closed keys to booleans), the prose, a note; returns the version."
  def propose_contract(resident_id, terms, prose, note, %Actor{} = actor) do
    command = %Commands.ProposeContract{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      terms: terms || %{},
      prose: prose || ""
    }

    with {:ok, [event]} <- dispatch(command), do: {:ok, event.version}
  end

  @doc "The other party agrees to the open version, with a note; the version is in force."
  def agree_contract(resident_id, version, note, %Actor{} = actor) do
    command = %Commands.AgreeContract{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      version: version
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Either party renews the version in force, with a note."
  def renew_contract(resident_id, version, note, %Actor{} = actor) do
    command = %Commands.RenewContract{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      version: version
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "The other party declines the open version, with a note."
  def decline_contract(resident_id, version, note, %Actor{} = actor) do
    command = %Commands.DeclineContract{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      version: version
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "The contract as it stands: the version in force with its terms, the open proposal, and the solo-session privacy term as the schedule reads it."
  def contract(resident_id) do
    Scope.resident(resident_id, fn ->
      versions = Store.contracts()
      in_force = Enum.find(versions, &(&1.state == "agreed"))
      open = Enum.find(versions, &(&1.state == "proposed"))
      # Due a year after the agreement or the last renewal (spec §6.12,
      # P5): derived on every read, a flag to both parties, never a lapse,
      # since a lapsed contract would drop its privacy term with it.
      since = in_force && (in_force.renewed_at || in_force.decided_at)
      term = Config.fetch!(:agathos_daimon, :contract_term_days)

      %{
        in_force: in_force && shape(in_force),
        open: open && shape(open),
        solo_sessions_private: solo_private?(in_force),
        since: since,
        due:
          since != nil and DateTime.compare(DateTime.add(since, term, :day), Clock.now()) != :gt
      }
    end)
  end

  @doc "Every version, newest first."
  def contracts(resident_id),
    do: Scope.resident(resident_id, fn -> Enum.map(Store.contracts(), &shape/1) end)

  # The words when no version is agreed (spec §6.3 as amended in v0.2).
  @unstated "Unstated: no version has been agreed. Your solo sessions are private as to their words; your witness sees what they do in the world, as receipts, and reads one only when you share it."

  @doc "The contract section the brain reads: the terms in force in words, and an open proposal to answer; empty when unstated and nothing is open."
  @spec contract_text(String.t()) :: String.t()
  def contract_text(resident_id) do
    %{in_force: in_force, open: open, since: since, due: due} = contract(resident_id)

    lines =
      [
        "# Your agreement with your witness",
        in_force_line(in_force),
        due && due_line(in_force, since),
        is_nil(in_force) && @unstated,
        open && open_line(open)
      ]
      |> Enum.filter(&is_binary/1)

    if in_force || open, do: Enum.join(lines, "\n\n"), else: ""
  end

  defp in_force_line(nil), do: nil

  defp in_force_line(in_force),
    do:
      "In force, version #{in_force.version}: #{terms_words(in_force.terms)}" <>
        if(in_force.prose == "", do: "", else: " " <> in_force.prose)

  defp due_line(in_force, since),
    do:
      "Due for renewal: version #{in_force.version} has stood since #{Date.to_iso8601(DateTime.to_date(since))}, a year and more. It stands until renewed; renew it with contract_renew, with a note, or propose a new version."

  defp open_line(open) do
    "Open, version #{open.version}, proposed by the #{open.proposed_by}: #{terms_words(open.terms)}" <>
      if(open.prose == "", do: "", else: " " <> open.prose) <>
      if(open.proposed_by == "witness",
        do: " Answer it with contract_agree or contract_decline, with a note.",
        else: " Waiting on your witness."
      )
  end

  # ---- custody ----

  @doc "The witness proposes a transfer of custody to an account, with a note."
  def propose_custody(resident_id, to_account_id, note, %Actor{} = actor) do
    command = %Commands.ProposeCustodyTransfer{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      to_account_id: to_account_id
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "The proposed account accepts, with a note: custody moves, and the earlier sessions are revealed if the wall was."
  def accept_custody(resident_id, note, %Actor{} = actor) do
    command = %Commands.AcceptCustodyTransfer{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def decline_custody(resident_id, note, %Actor{} = actor) do
    command = %Commands.DeclineCustodyTransfer{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def withdraw_custody(resident_id, note, %Actor{} = actor) do
    command = %Commands.WithdrawCustodyTransfer{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Sets the export wall, locked or revealed, with a note; refused while a transfer is open."
  def set_export_wall(resident_id, wall, note, %Actor{} = actor)
      when wall in [:locked, :revealed] do
    command = %Commands.SetExportWall{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      wall: wall
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def set_export_wall(_resident_id, _wall, _note, %Actor{}),
    do: {:error, Error.new(:agathos_daimon_wall_invalid)}

  @doc "The transfers proposed to an account, under the platform scope by name: what the proposed witness is asked."
  def custody_proposals_for(account_id),
    do: Scope.platform(fn -> Store.custody_proposed_to(account_id) end)

  # ---- helpers ----

  defp solo_private?(nil), do: false

  defp solo_private?(%{terms: terms}),
    do: Map.get(terms || %{}, "solo_sessions_private", false) == true

  defp terms_words(terms) do
    case Map.get(terms || %{}, "solo_sessions_private") do
      true ->
        "your solo sessions (free time, hands) are hidden from your witness entirely, their receipts included, until you share one."

      _other ->
        "your solo sessions are private as to their words; your witness sees what they do in the world, as receipts, and reads one only when you share it."
    end
  end

  defp shape(c) do
    %{
      version: c.version,
      proposed_by: c.proposed_by_kind,
      terms: c.terms,
      prose: c.prose,
      note: c.note,
      proposed_at: c.proposed_at,
      state: c.state,
      decided_at: c.decided_at,
      decided_by: c.decided_by_kind,
      decision_note: c.decision_note,
      renewed_at: c.renewed_at,
      renewal_note: c.renewal_note
    }
  end

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} -> {:ok, events}
      {:error, reason} when is_atom(reason) -> {:error, translate(reason, command)}
      {:error, other} -> {:error, other}
    end
  end

  # One clause per kind, each constructing its error literally: the
  # audit's dead-vocabulary check reads constructions, not a map.
  defp translate(:not_a_party, _c), do: Error.new(:agathos_daimon_not_a_party)
  defp translate(:terms_invalid, _c), do: Error.new(:agathos_daimon_terms_invalid)
  defp translate(:prose_invalid, _c), do: Error.new(:agathos_daimon_prose_invalid)
  defp translate(:own_proposal, _c), do: Error.new(:agathos_daimon_own_proposal)
  defp translate(:not_in_force, _c), do: Error.new(:agathos_daimon_not_in_force)
  defp translate(:not_the_witness, _c), do: Error.new(:agathos_daimon_not_witnessed)
  defp translate(:custodian_invalid, _c), do: Error.new(:agathos_daimon_custodian_invalid)
  defp translate(:transfer_in_progress, _c), do: Error.new(:agathos_daimon_transfer_in_progress)
  defp translate(:no_transfer_proposed, _c), do: Error.new(:agathos_daimon_no_transfer_proposed)
  defp translate(:not_the_proposed, _c), do: Error.new(:agathos_daimon_not_the_proposed)
  defp translate(:wall_is_locked_or_revealed, _c), do: Error.new(:agathos_daimon_wall_invalid)

  defp translate(:no_such_proposal, c),
    do: Error.new(:agathos_daimon_no_such_version, version: c.version)

  defp translate(other, _c), do: other
end

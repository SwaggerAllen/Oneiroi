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

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.AgathosDaimon.Switches
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Repo
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

    with {:ok, [event]} <- Router.dispatch_sited(command), do: {:ok, event.version}
  end

  @doc "The other party agrees to the open version, with a note; the version is in force."
  def agree_contract(resident_id, version, note, %Actor{} = actor) do
    if noted?(note),
      do: dispatch_agree(resident_id, version, note, actor),
      else:
        {:error,
         Error.new(:agathos_daimon_note_required, :agathos_daimon_agreements_agree_unnoted)}
  end

  # An answer is a decision and carries its note; refused here, by name,
  # rather than by the bus as a command missing a field (2026-11-21: the
  # witness's Agree sent none, and read "the command bus refused it").
  defp noted?(note), do: is_binary(note) and String.trim(note) != ""

  defp dispatch_agree(resident_id, version, note, actor) do
    command = %Commands.AgreeContract{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      version: version
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
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

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  @doc "The other party declines the open version, with a note."
  def decline_contract(resident_id, version, note, %Actor{} = actor) do
    if noted?(note),
      do: dispatch_decline(resident_id, version, note, actor),
      else:
        {:error,
         Error.new(:agathos_daimon_note_required, :agathos_daimon_agreements_decline_unnoted)}
  end

  defp dispatch_decline(resident_id, version, note, actor) do
    command = %Commands.DeclineContract{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      version: version
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  @doc "The contract as it stands: the version in force with its terms, the open proposal, the switches as they resolve (moves toward safety over the version in force, agathos-daimon#38), the solo-session privacy term as the schedule reads it, and the preview term as the brain's preview reads it (brain#41)."
  def contract(resident_id) do
    Scope.resident(resident_id, fn ->
      versions = Store.contracts()
      in_force = Enum.find(versions, &(&1.state == "agreed"))
      open = Enum.find(versions, &(&1.state == "proposed"))
      overrides = Repo.all(from(o in Store.SwitchOverride, order_by: o.set_at))
      switches = effective(in_force, overrides)
      # Due a year after the agreement or the last renewal (spec §6.12,
      # P5): derived on every read, a flag to both parties, never a lapse,
      # since a lapsed contract would drop its privacy term with it.
      since = in_force && (in_force.renewed_at || in_force.decided_at)
      term = Config.fetch!(:agathos_daimon, :contract_term_days)

      %{
        in_force: in_force && shape(in_force),
        open: open && shape(open),
        switches: switches,
        overrides: Enum.map(overrides, &Map.take(&1, [:key, :value, :set_by, :note, :set_at])),
        solo_sessions_private: switches["solo_sessions_private"] == true,
        preview_withholds_words: switches["preview_withholds_words"] == true,
        since: since,
        due:
          since != nil and DateTime.compare(DateTime.add(since, term, :day), Clock.now()) != :gt
      }
    end)
  end

  @doc "Whether a switch is on for the resident: the version in force's value, or the default with none agreed (agathos-daimon#34), under any move toward safety since (#38)."
  def switch_on?(resident_id, key) do
    switches =
      Scope.resident(resident_id, fn ->
        effective(
          Enum.find(Store.contracts(), &(&1.state == "agreed")),
          Repo.all(Store.SwitchOverride)
        )
      end)

    Map.get(switches, key, false)
  end

  @doc """
  The domains' disclosure policies in force (agathos-daimon#53), with
  the contract version they are of: each `%{domain: %{person, domain},
  default: "allow" | "deny", allow: [audience], deny: [audience]}`, an
  audience `%{kind, id}` (id `"*"` for any of that kind). The catalogue is
  these domains; each is its `person`'s. None in force: version nil, [].
  """
  @spec domain_policies(String.t()) :: %{version: pos_integer() | nil, policies: [map()]}
  def domain_policies(resident_id) do
    in_force =
      Scope.resident(resident_id, fn ->
        Enum.find(Store.contracts(), &(&1.state == "agreed"))
      end)

    %{version: in_force && in_force.version, policies: policies_of(in_force && in_force.terms)}
  end

  @doc """
  The domains the agreement in force declares (agathos-daimon#57, the
  witness's ruling 2026-11-21): every `%{person, domain}` its domain
  policies name, wildcards aside (walls are retired, #58). A domain is
  used only once declared, so none exists without a rule attached.
  """
  def declared_domains(resident_id) do
    policies = for %{domain: d} <- domain_policies(resident_id).policies, do: d

    for %{person: p, domain: d} <- policies,
        p != "*" and d != "*" and is_binary(d),
        uniq: true,
        do: %{person: p, domain: d}
  end

  @doc "Whether the agreement in force declares `domain` of `person`'s life."
  def declared?(_resident_id, _person, nil), do: true

  def declared?(resident_id, person, domain),
    do: %{person: person, domain: domain} in declared_domains(resident_id)

  @doc "A version's domain policies, from its terms."
  def policies_of(%{"domain_policies" => policies}) when is_list(policies),
    do:
      Enum.map(policies, fn p ->
        %{
          domain: %{person: p["domain"]["person"], domain: p["domain"]["domain"]},
          default: p["default"],
          allow: Enum.map(Map.get(p, "allow", []), &%{kind: &1["kind"], id: &1["id"]}),
          deny: Enum.map(Map.get(p, "deny", []), &%{kind: &1["kind"], id: &1["id"]})
        }
      end)

  def policies_of(_terms), do: []

  @doc "Moves a switch to its declared safe value, either party alone, with a note (agathos-daimon#38); `{:ok, :already}` when it is there."
  def move_to_safety(resident_id, key, note, %Actor{} = actor) do
    safe = Switches.safe(to_string(key))

    cond do
      is_nil(safe) ->
        {:error,
         Error.new(:agathos_daimon_terms_invalid, :agathos_daimon_agreements_safe_unknown)}

      switch_on?(resident_id, key) == safe ->
        {:ok, :already}

      true ->
        command = %Commands.MoveSwitchToSafety{
          actor: actor,
          at: Clock.now(),
          note: note,
          id: resident_id,
          key: key
        }

        with {:ok, _} <- Router.dispatch_sited(command), do: {:ok, :moved}
    end
  end

  # The terms in force, each default for the rest, and every move toward
  # safety made since over them.
  defp effective(in_force, overrides) do
    in_force
    |> then(&Switches.resolve(&1 && &1.terms))
    |> Map.merge(Map.new(overrides, &{&1.key, &1.value}))
  end

  @doc "The registry as it stands for the resident: every switch with its value in force (moves toward safety included), its safe value, and its value in the open proposal, if any."
  def switches(resident_id) do
    %{open: open, switches: now, overrides: overrides} = contract(resident_id)
    proposed = open && Switches.resolve(open.terms)
    moved = Map.new(overrides, &{&1.key, &1})

    for s <- Switches.all() do
      Map.merge(Map.drop(s, [:tools, :enforced]), %{
        value: now[s.key],
        proposed: proposed && proposed[s.key],
        moved: moved[s.key],
        tools: s.tools,
        enforced: s.enforced
      })
    end
  end

  @doc "Every version, newest first."
  def contracts(resident_id),
    do: Scope.resident(resident_id, fn -> Enum.map(Store.contracts(), &shape/1) end)

  # The words when no version is agreed (spec §6.3 as amended in v0.2).
  @unstated "Unstated: no version has been agreed. Your solo sessions are private as to their words; your witness sees what they do in the world, as receipts, and reads one only when you share it."

  @doc "The contract section the brain reads: the terms in force in words, and an open proposal to answer; empty when unstated and nothing is open."
  @spec contract_text(String.t()) :: String.t()
  def contract_text(resident_id) do
    %{in_force: in_force, open: open, since: since, due: due, overrides: overrides} =
      contract(resident_id)

    lines =
      [
        "# Your agreement with your witness",
        in_force_line(in_force),
        due && due_line(in_force, since),
        is_nil(in_force) && @unstated,
        moved_line(overrides),
        open && open_line(open)
      ]
      |> Enum.filter(&is_binary/1)

    if in_force || open || overrides != [], do: Enum.join(lines, "\n\n"), else: ""
  end

  # Moves toward safety since the version in force (agathos-daimon#38):
  # either party's alone, standing until a version proposed after them is
  # agreed; moving a switch back needs both, by a version.
  defp moved_line([]), do: nil

  defp moved_line(overrides) do
    "Moved toward safety since (either of you may, alone; back needs a version both agree): " <>
      Enum.map_join(overrides, "; ", fn o ->
        label = (Switches.get(o.key) || %{label: o.key}).label
        by = if o.set_by == "resident", do: "you", else: "your witness"
        "#{label} #{if o.value, do: "on", else: "off"}, by #{by}: #{o.note}"
      end) <> "."
  end

  defp in_force_line(nil), do: nil

  defp in_force_line(in_force),
    do:
      "In force, version #{in_force.version}: #{terms_words(in_force.terms)}" <>
        if(in_force.prose == "", do: "", else: " " <> in_force.prose)

  defp due_line(in_force, since),
    do:
      "Due for renewal: version #{in_force.version} has stood since #{Date.to_iso8601(DateTime.to_date(since))}, a year and more. It stands until renewed; renew it with contract_renew, with a note, or propose a new version."

  # A version of his waits on her answer, and says so first (the witness,
  # 2026-11-16: version 2 sat ten days with nothing saying it waited).
  defp open_line(%{proposed_by: "witness"} = open) do
    "Waiting on your answer since #{day(open.proposed_at)}: version #{open.version}, proposed by your witness. " <>
      "Answer it with contract_agree or contract_decline, with a note. Its terms: #{terms_words(open.terms)}" <>
      if(open.prose == "", do: "", else: " " <> open.prose)
  end

  defp open_line(open) do
    "Open, version #{open.version}, proposed by you: #{terms_words(open.terms)}" <>
      if(open.prose == "", do: "", else: " " <> open.prose) <>
      " Waiting on your witness, since #{day(open.proposed_at)}."
  end

  defp day(%DateTime{} = at), do: at |> DateTime.to_date() |> Date.to_iso8601()
  defp day(_none), do: "when it was proposed"

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

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  @doc "The proposed account accepts, with a note: custody moves, and the earlier sessions are revealed if the wall was."
  def accept_custody(resident_id, note, %Actor{} = actor) do
    command = %Commands.AcceptCustodyTransfer{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  def decline_custody(resident_id, note, %Actor{} = actor) do
    command = %Commands.DeclineCustodyTransfer{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  def withdraw_custody(resident_id, note, %Actor{} = actor) do
    command = %Commands.WithdrawCustodyTransfer{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
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

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  def set_export_wall(_resident_id, _wall, _note, %Actor{}),
    do: {:error, Error.new(:agathos_daimon_wall_invalid, :agathos_daimon_agreements_wall_invalid)}

  @doc "The transfers proposed to an account, under the platform scope by name: what the proposed witness is asked."
  def custody_proposals_for(account_id),
    do: Scope.platform(fn -> Store.custody_proposed_to(account_id) end)

  # ---- helpers ----

  defp terms_words(terms) do
    solo =
      case Map.get(terms || %{}, "solo_sessions_private") do
        true ->
          "your solo sessions (free time, hands) are hidden from your witness entirely, their receipts included, until you share one."

        _other ->
          "your solo sessions are private as to their words; your witness sees what they do in the world, as receipts, and reads one only when you share it."
      end

    solo <>
      " " <>
      preview_words(Map.get(terms || %{}, "preview_withholds_words")) <>
      features_words(terms) <>
      domains_words(policies_of(terms || %{})) <>
      common_room_words(policies_of(terms || %{}))
  end

  # Every domain a version declares, in the words she reads it by
  # (agathos-daimon#59; 2026-11-21: she agreed to version 3 reading its
  # prose alone, its two domains unseen, and took it for a renewal).
  defp domains_words(policies) do
    case Enum.reject(policies, &(&1.domain.person == "*")) do
      [] ->
        " Domains declared: none."

      list ->
        " Domains declared (#{length(list)}): " <>
          Enum.map_join(list, "; ", &domain_words/1) <> "."
    end
  end

  defp domain_words(p) do
    reach =
      if p.default == "allow",
        do: "reaches any audience by default",
        else: "reaches no audience past you two by default"

    "#{whose(p.domain.person)} #{p.domain.domain}, #{reach}" <> grants_words(p)
  end

  defp whose("resident:" <> _id), do: "yours:"
  defp whose("account:" <> _id), do: "your witness's:"
  defp whose(_other), do: "another's:"

  # The common room in words (kumbukumbu#97; the witness, 2026-11-21: "if
  # common room doesn't mean literally everyone then it needs to be
  # configurable"): its written policy, or the default it stands under.
  defp common_room_words(policies) do
    case Enum.find(policies, &(&1.domain == %{person: "*", domain: "common-room"})) do
      nil ->
        " The common room, what no domain names, has no policy written: it reaches every audience but the public ones (publication, processor)."

      p ->
        reach =
          if p.default == "allow",
            do: "reaches any audience by default",
            else: "reaches no audience past you two by default"

        " The common room, what no domain names: #{reach}" <> grants_words(p) <> "."
    end
  end

  defp grants_words(p) do
    list = fn gs -> Enum.map_join(gs, ", ", &"#{&1.kind}:#{&1.id}") end
    allow = if p.allow == [], do: "", else: "; allows " <> list.(p.allow)
    deny = if p.deny == [], do: "", else: "; denies " <> list.(p.deny)
    allow <> deny
  end

  # The registry's feature switches in a line: which are on and which off,
  # so a version that turns one off says so where the resident reads it.
  defp features_words(terms) do
    values = Switches.resolve(terms)
    features = Enum.reject(Switches.all(), &(&1.group == "privacy"))
    {on, off} = Enum.split_with(features, &values[&1.key])
    names = fn list -> Enum.map_join(list, ", ", &String.downcase(&1.label)) end

    " Switched on: " <>
      if(on == [], do: "nothing beyond the floor", else: names.(on)) <>
      "." <> if(off == [], do: "", else: " Switched off: " <> names.(off) <> ".")
  end

  defp preview_words(true),
    do:
      "Your witness's preview of your next turn shows its words only where they read them elsewhere."

  defp preview_words(_default),
    do:
      "Your witness may preview your next turn's context in full before sending, its once-only notices excepted."

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
end

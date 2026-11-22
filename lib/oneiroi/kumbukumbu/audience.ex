defmodule Oneiroi.Kumbukumbu.Audience do
  @moduledoc """
  The audience decision (kumbukumbu#79; Lily's `design/audience-policy.md`
  @41423231be51, Scarlett's pencil and the witness's answers): the one
  service every composition and delivery asks whether its inputs may
  reach its audience. Domains say what a memory is about (`Domains`);
  this says where it may land.

  **Inputs.** Every actual input is labelled before its words are used:
  its subject domains (`%{person, domain}` pairs, direct and every
  ancestor's, the caller's closure), or `:common_room` (an explicit
  classification, never an empty set), or `:unclassified` (missing,
  conflicting or failed provenance). Labels accumulate; permissions
  narrow (§3).

  **Audiences.** Resolved, never named (§2.3, §2.8): a kind (`dyad`,
  `conversation`, `person`, `household`, `thread`, `workspace`,
  `correspondent`, `publication`, `export`, `processor`), an id, the
  participants at decision time, its visibility and delivery route. The
  dyad (the resident and her witness) and her own private context are
  always permitted: fail closed governs disclosure, never memory itself
  (§0.2), and unclassified material is never disclosed outside them (the
  witness's answer 3).

  **Policies.** The dyad agreement's `domain_policies` (agathos-daimon#53;
  the witness's call: the dyad holds them). For each label, the domain's
  policy: an explicit deny wins, else an explicit allow, else the
  domain's default (the witness's call, 2026-11-20). A domain with no
  policy is unresolved and denies every audience past the dyad. The
  common room with no policy of its own reaches any audience but a
  publication, an export or a processor, which need one (a configuration
  point, his to change by agreement).

  **Modes.** `:soft` for the resident's own composition: a withheld input
  is named with the domains that conflict, and may be deliberately
  unwrapped (`unwrap/3`, a new decision each time). `:hard` for delivery
  to the audience: a withheld input is the generic `withheld_by_policy`
  and the decision id, nothing more (§5.4).

  **The researcher** (the witness's ruling, 2026-11-20: "let's make the
  researcher an audience"; kumbukumbu#86): the reader's research pass,
  where a research question's words go. A domain with a policy is
  decided by it; one without is decided by
  `KUMBUKUMBU_RESEARCHER_DEFAULT`, `allow` (Lily's lean, his to flip:
  she should have broad freedom to search, and the answers carry the
  asking turn's labels either way) or `deny`.

  Pure but for `decide_for/4`, which reads the policies in force.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Kumbukumbu.Error

  # The common room with no policy of its own is not public by default
  # (her pencil, §9.8): publication, export and processors need a policy.
  # The public audiences the common room does not reach unless its own
  # policy says so (kumbukumbu#97). The export is no audience: it carries
  # her whole record to her, and nothing is kept from it.
  @public ~w(publication processor)
  @common_room %{person: "*", domain: "common-room"}

  @type label :: %{person: String.t(), domain: String.t()}
  @type input :: %{
          required(:id) => String.t(),
          optional(:ref) => String.t(),
          required(:labels) => [label()] | :common_room | :unclassified | :private
        }
  @type audience :: %{
          required(:kind) => String.t(),
          required(:id) => String.t(),
          optional(:participants) => [String.t()],
          optional(:visibility) => String.t(),
          optional(:route) => String.t()
        }

  @doc "A resolved audience: its kind and id, who is in it now, its visibility and route."
  def audience(kind, id, opts \\ []),
    do: %{
      kind: kind,
      id: id,
      participants: Keyword.get(opts, :participants, []),
      visibility: Keyword.get(opts, :visibility, default_visibility(kind)),
      route: Keyword.get(opts, :route, default_route(kind))
    }

  defp default_visibility(kind) when kind in ["dyad", "conversation"], do: "private"
  defp default_visibility("publication"), do: "public"
  defp default_visibility(_kind), do: "shared"

  defp default_route(kind) when kind in ["dyad", "conversation"], do: "none"
  defp default_route(kind) when kind in ["household", "workspace"], do: "household"
  defp default_route(_kind), do: "external"

  @doc "The decision for a resident, against the policies in force in her dyad agreement."
  def decide_for(resident_id, inputs, audience, mode) do
    %{version: version, policies: policies} = AgathosDaimon.domain_policies(resident_id)

    decide(
      inputs,
      audience,
      %{
        version: version,
        policies: policies,
        researcher: Oneiroi.Config.fetch!(:kumbukumbu, :researcher_default)
      },
      mode
    )
  end

  @doc """
  The decision (§3.6): which inputs may reach the audience, which are
  withheld and why, the labels a derived artifact carries (the union of
  every input's), whether any input was unclassified, and the policy
  snapshot it was made under. Re-run at every new audience and at
  delivery; nothing here is inferred from citations.
  """
  def decide(inputs, audience, snapshot, mode) when mode in [:soft, :hard] do
    resolved? = resolved?(audience)

    {allowed, withheld} =
      Enum.reduce(inputs, {[], []}, fn input, {ok, out} ->
        case verdict(input, audience, resolved?, snapshot) do
          :allow -> {[input.id | ok], out}
          {:withhold, reason, conflicts} -> {ok, [withheld(input, reason, conflicts) | out]}
        end
      end)

    decision = %{
      mode: mode,
      audience: audience,
      allowed: Enum.reverse(allowed),
      withheld: Enum.reverse(withheld),
      labels: labels(inputs),
      unclassified: Enum.any?(inputs, &(&1.labels == :unclassified)),
      snapshot: %{version: snapshot.version, policies: used(inputs, snapshot.policies)},
      unwrapped: []
    }

    Map.put(decision, :id, decision_id(decision, inputs))
  end

  @doc """
  What the audience is told of a withheld input (§5.4): in `:soft` mode,
  the resident's own context, the input named and the domains in
  conflict; in `:hard` mode, the generic reason and the decision id.
  """
  def told(%{mode: :soft}, w),
    do: "withheld: #{w.ref || w.id}, #{reason_words(w.reason)}#{conflict_words(w.conflicts)}"

  def told(%{mode: :hard, id: id}, _w), do: "withheld_by_policy (decision #{id})"

  @doc """
  A deliberate unwrap (§5.2): in the resident's own composition, one
  withheld input released by her act, recorded on the decision as a new
  one (a new id). Never in `:hard` mode, where no unwrap exists.
  """
  def unwrap(%{mode: :soft} = decision, input_id, note) when is_binary(note) and note != "" do
    case Enum.split_with(decision.withheld, &(&1.id == input_id)) do
      {[w], rest} ->
        unwrapped = [%{id: w.id, note: note, from: decision.id} | decision.unwrapped]

        decision
        |> Map.merge(%{allowed: decision.allowed ++ [w.id], withheld: rest, unwrapped: unwrapped})
        |> then(&Map.put(&1, :id, decision_id(&1, [])))
        |> then(&{:ok, &1})

      {[], _} ->
        {:error, Error.new(:kumbukumbu_unwrap_refused, :kumbukumbu_audience_unwrap_not_withheld)}
    end
  end

  def unwrap(%{mode: :hard}, _input_id, _note),
    do: {:error, Error.new(:kumbukumbu_unwrap_refused, :kumbukumbu_audience_unwrap_hard)}

  def unwrap(_decision, _input_id, _note),
    do: {:error, Error.new(:kumbukumbu_unwrap_refused, :kumbukumbu_audience_unwrap_no_note)}

  # ---- the verdict for one input ----

  defp verdict(input, audience, resolved?, snapshot) do
    policies = snapshot.policies
    # The researcher's default for a domain with no policy (kumbukumbu#86).
    policies =
      if audience.kind == "researcher", do: researcher(policies, input, snapshot), else: policies

    cond do
      private?(audience) -> :allow
      not resolved? -> {:withhold, :unresolved_audience, []}
      # A private soul line (agathos-daimon#55): dyad-only, no grant path.
      input.labels == :private -> {:withhold, :private, []}
      input.labels == :unclassified -> {:withhold, :unclassified, []}
      input.labels == :common_room -> label_verdicts([@common_room], audience, policies)
      input.labels == [] -> {:withhold, :unclassified, []}
      true -> label_verdicts(input.labels, audience, policies)
    end
  end

  # Before the researcher, a domain's policy decides only where it names
  # the researcher (an explicit allow or deny); otherwise, or with no
  # policy at all, the researcher's default stands in for the policy's
  # own (kumbukumbu#86: her freedom to search, his to tighten).
  defp researcher(policies, %{labels: labels}, snapshot) when is_list(labels) do
    default = Map.get(snapshot, :researcher, "allow")
    for_labels = Enum.map(labels, &researcher_policy(policy(&1, policies), &1, default))
    others = Enum.reject(policies, fn p -> Enum.any?(labels, &(policy(&1, [p]) != nil)) end)
    for_labels ++ others
  end

  defp researcher(policies, _input, _snapshot), do: policies

  defp researcher_policy(nil, label, default),
    do: %{domain: label, default: default, allow: [], deny: []}

  defp researcher_policy(p, _label, default),
    do: if(names_researcher?(p), do: p, else: %{p | default: default})

  defp names_researcher?(p),
    do: Enum.any?(p.allow ++ p.deny, &(&1.kind == "researcher"))

  # Every label must permit; the conflicts are the labels that do not.
  defp label_verdicts(labels, audience, policies) do
    refusals =
      for label <- labels,
          reason = refusal(label, audience, policies),
          reason != nil,
          do: {label, reason}

    case refusals do
      [] -> :allow
      [{_, reason} | _] -> {:withhold, reason, Enum.map(refusals, &elem(&1, 0))}
    end
  end

  defp refusal(label, audience, policies) do
    case policy(label, policies) do
      nil -> if label == @common_room, do: common_room_default(audience), else: :no_policy
      p -> evaluate(p, audience)
    end
  end

  # The common room with no policy: any audience but the public ones.
  defp common_room_default(%{kind: kind}) when kind in @public, do: :not_allowed
  defp common_room_default(_audience), do: nil

  # Deny wins; else an allow; else the default (the witness, 2026-11-20).
  defp evaluate(p, audience) do
    cond do
      Enum.any?(p.deny, &matches?(&1, audience)) -> :denied
      Enum.any?(p.allow, &matches?(&1, audience)) -> nil
      p.default == "allow" -> nil
      true -> :not_allowed
    end
  end

  defp matches?(%{kind: kind, id: "*"}, %{kind: kind}), do: true
  defp matches?(%{kind: kind, id: id}, %{kind: kind, id: id}), do: true
  defp matches?(_grant, _audience), do: false

  defp policy(label, policies),
    do:
      Enum.find(policies, fn p ->
        p.domain.person == label.person and p.domain.domain == label.domain
      end)

  defp private?(%{kind: "dyad"}), do: true
  defp private?(%{kind: "conversation", visibility: "private"}), do: true
  defp private?(_audience), do: false

  defp resolved?(%{kind: kind, id: id}) when is_binary(kind) and is_binary(id) and id != "",
    do: true

  defp resolved?(_audience), do: false

  defp withheld(input, reason, conflicts),
    do: %{id: input.id, ref: Map.get(input, :ref), reason: reason, conflicts: conflicts}

  defp labels(inputs) do
    inputs
    |> Enum.flat_map(fn
      %{labels: list} when is_list(list) -> list
      %{labels: :common_room} -> [@common_room]
      _unclassified -> []
    end)
    |> Enum.uniq()
  end

  defp used(inputs, policies) do
    ls = labels(inputs)
    for p <- policies, Enum.any?(ls, &(&1 == p.domain)), do: p
  end

  defp decision_id(decision, inputs) do
    term =
      {decision.audience.kind, decision.audience.id, decision.allowed,
       Enum.map(decision.withheld, & &1.id), Enum.map(inputs, & &1.id), decision.snapshot.version,
       Enum.map(decision.unwrapped, & &1.id)}

    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 12)
  end

  defp reason_words(:no_policy), do: "its domain has no policy for audiences past the dyad"
  defp reason_words(:denied), do: "a policy denies this audience"
  defp reason_words(:not_allowed), do: "no policy allows this audience"
  defp reason_words(:unclassified), do: "its provenance is unclassified"
  defp reason_words(:unresolved_audience), do: "the audience is not resolved"
  defp reason_words(:private), do: "it is private to you and your witness"

  defp conflict_words([]), do: ""

  defp conflict_words(conflicts),
    do: " (in conflict with this audience: #{Enum.map_join(conflicts, ", ", & &1.domain)})"
end

defmodule Oneiroi.Kumbukumbu.Ledger do
  @moduledoc """
  A turn's input ledger (kumbukumbu#80; Lily's `design/audience-policy.md`
  §3.5: every actual input labelled before its words are used) and the
  check every delivery of a resident's composition makes against it.

  **What a turn's model saw**, each labelled for `Audience.decide/4`:

  - her identity files: `USER.md` unclassified (the witness's file, cut
    by the migration; until then it withholds everything past the dyad),
    the rest the common room;
  - the window's last messages, each its domain, or the common room
    when it has none (the witness's answer 3: the default classification
    is the common room);
  - the lanes filtered to the conversation's current domain (pins, the
    index, the madeleine, the character exemplars): that domain;
  - the timeline's bookmarks, every domain they hold (that lane is not
    filtered);
  - what the turn read deliberately (`TurnReads`).

  A generated answer inherits all of it (§3.5), so a delivery checks the
  union: in `:hard` mode, against the audience it would reach.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Kumbukumbu.Audience
  alias Oneiroi.Kumbukumbu.Domains
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Kumbukumbu.TurnReads
  alias Oneiroi.Scope

  @window 40

  @doc "A turn's inputs, labelled."
  def inputs(resident_id, session_key, turn_ref, window \\ @window) do
    identity(resident_id) ++
      messages(resident_id, session_key, window) ++
      lanes(resident_id, session_key) ++
      timeline(resident_id) ++ TurnReads.of(resident_id, turn_ref)
  end

  @doc """
  Whether a turn's composition may be delivered to `audience`: `{:ok,
  decision}`, or the refusal, which names (to her, in her own context)
  the domains in conflict and the decision id, and is all the audience
  ever learns: nothing is delivered.
  """
  def check(resident_id, session_key, turn_ref, audience) do
    inputs = inputs(resident_id, session_key, turn_ref)
    decision = Audience.decide_for(resident_id, inputs, audience, :hard)

    case decision.withheld do
      [] ->
        {:ok, decision}

      withheld ->
        {:error,
         Error.new(:kumbukumbu_withheld_by_policy, :kumbukumbu_ledger_delivery_withheld,
           decision: decision.id,
           audience: "#{audience.kind}:#{audience.id}",
           conflicts: conflicts(withheld)
         )}
    end
  end

  @doc "The labels of inputs a tool read: a bookmark opened, a transcript turn read."
  def bookmark_input(resident_id, %{number: n} = bookmark) do
    [%{domain_key: key}] = Domains.attach(resident_id, [bookmark])
    %{id: "bookmark/#{n}", ref: "bookmark/#{n}", labels: label(key)}
  end

  # ---- the parts ----

  defp identity(resident_id) do
    for {name, _content} <- AgathosDaimon.identity_context(resident_id),
        do: %{
          id: name,
          ref: name,
          labels: if(name == "USER.md", do: :unclassified, else: :common_room)
        }
  end

  defp messages(_resident_id, nil, _window), do: []

  defp messages(resident_id, session_key, window) do
    rows = Scope.resident(resident_id, fn -> Store.recent_domains(session_key, window) end)

    for r <- rows,
        do: %{
          id: "message/#{session_key}/#{r.sequence}/#{r.position}",
          ref: "transcript/#{session_key}",
          labels: label(Domains.pair(r.person, r.domain))
        }
  end

  defp lanes(resident_id, session_key),
    do: [
      %{
        id: "lanes",
        ref: "the turn's memory lanes",
        labels: label(Domains.current(resident_id, session_key))
      }
    ]

  defp timeline(resident_id) do
    marks = Scope.resident(resident_id, fn -> Store.timeline_anchors() end)

    resident_id
    |> Domains.attach(marks)
    |> Enum.map(&%{id: "bookmark/#{&1.number}", ref: "timeline", labels: label(&1.domain_key)})
  end

  defp label(nil), do: :common_room
  defp label(%{person: _, domain: _} = pair), do: [pair]

  defp conflicts(withheld) do
    withheld
    |> Enum.flat_map(fn
      %{reason: :unclassified} -> ["unclassified"]
      %{conflicts: cs} -> Enum.map(cs, & &1.domain)
    end)
    |> Enum.uniq()
  end
end

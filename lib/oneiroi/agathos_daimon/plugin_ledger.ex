defmodule Oneiroi.AgathosDaimon.PluginLedger do
  @moduledoc """
  The plugins aggregate (agathos-daimon#37, brain#68; the witness,
  2026-11-07: plugins are contract material), on `plugins-<resident_id>`.
  Pure. It holds each plugin's state (installed, on) by key, the
  proposals by number, and whether the slots that existed before plugins
  were carried over.

  The rules, position #68 as the witness ruled it:

  - a first-party plugin (a memory slot) moves only by a proposal one
    party makes and the other agrees: install, remove, on, off;
  - an installable plugin installs, turns on and is removed the same
    way, and is switched off by either party alone, at once;
  - nothing switches itself on: an install leaves a plugin off;
  - every proposal and answer is recorded with its note, agreed or
    declined, never silent;
  - the carry-over is recorded once, as itself, never as a consent.
  """

  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.Events

  defstruct next: 1, plugins: %{}, proposals: %{}, carried: false

  @changes ~w(install remove on off)
  @tiers ~w(first_party installable)

  def execute(%__MODULE__{} = s, %Commands.ProposePlugin{} = c) do
    case propose_refusal(s, c) do
      nil ->
        %Events.PluginProposed{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          number: s.next,
          key: c.key,
          tier: c.tier,
          change: c.change
        }

      refused ->
        refused
    end
  end

  def execute(%__MODULE__{} = s, %Commands.AnswerPlugin{} = c) do
    proposal = Map.get(s.proposals, c.number)

    cond do
      is_nil(proposal) ->
        {:error,
         Error.new(:agathos_daimon_no_such_version, :agathos_daimon_plugin_answer_absent,
           number: c.number
         )}

      not proposal.open ->
        []

      not party?(c.actor) ->
        {:error, Error.new(:agathos_daimon_not_a_party, :agathos_daimon_plugin_answer_party)}

      c.actor.kind == proposal.by ->
        {:error, Error.new(:agathos_daimon_own_proposal, :agathos_daimon_plugin_answer_own)}

      c.agree == true and not fits?(Map.get(s.plugins, proposal.key), proposal.change) ->
        {:error,
         Error.new(:agathos_daimon_plugin_invalid, :agathos_daimon_plugin_answer_stale,
           key: proposal.key,
           change: proposal.change
         )}

      true ->
        answered = %Events.PluginAnswered{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          number: c.number,
          agree: c.agree == true
        }

        if c.agree == true,
          do: [
            answered,
            %Events.PluginChanged{
              actor: c.actor,
              at: c.at,
              id: c.id,
              key: proposal.key,
              tier: proposal.tier,
              change: proposal.change,
              number: c.number
            }
          ],
          else: answered
    end
  end

  def execute(%__MODULE__{} = s, %Commands.SwitchPluginOff{} = c) do
    cond do
      not party?(c.actor) ->
        {:error, Error.new(:agathos_daimon_not_a_party, :agathos_daimon_plugin_off_party)}

      c.tier != "installable" ->
        {:error,
         Error.new(:agathos_daimon_plugin_invalid, :agathos_daimon_plugin_off_first_party,
           key: c.key
         )}

      not fits?(Map.get(s.plugins, c.key), "off") ->
        []

      true ->
        %Events.PluginChanged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          key: c.key,
          tier: c.tier,
          change: "off",
          number: nil
        }
    end
  end

  def execute(%__MODULE__{} = s, %Commands.CarryOverPlugins{} = c) do
    cond do
      c.actor.kind != :platform ->
        {:error, Error.new(:agathos_daimon_not_a_party, :agathos_daimon_plugin_carry_platform)}

      s.carried ->
        []

      true ->
        keys = c.keys |> List.wrap() |> Enum.reject(&Map.has_key?(s.plugins, &1))
        %Events.PluginsCarriedOver{actor: c.actor, at: c.at, id: c.id, keys: keys}
    end
  end

  def apply(%__MODULE__{} = s, %Events.PluginProposed{} = e) do
    proposal = %{key: e.key, tier: e.tier, change: e.change, by: kind(e.actor), open: true}
    %{s | next: e.number + 1, proposals: Map.put(s.proposals, e.number, proposal)}
  end

  def apply(%__MODULE__{} = s, %Events.PluginAnswered{} = e),
    do: %{s | proposals: Map.update!(s.proposals, e.number, &%{&1 | open: false})}

  def apply(%__MODULE__{} = s, %Events.PluginChanged{} = e) do
    before = Map.get(s.plugins, e.key, %{installed: false, on: false, tier: e.tier})

    after_change =
      case e.change do
        "install" -> %{before | installed: true, on: false}
        "remove" -> %{before | installed: false, on: false}
        "on" -> %{before | on: true}
        "off" -> %{before | on: false}
      end

    %{s | plugins: Map.put(s.plugins, e.key, after_change)}
  end

  def apply(%__MODULE__{} = s, %Events.PluginsCarriedOver{} = e) do
    carried = Map.new(e.keys, &{&1, %{installed: true, on: true, tier: "first_party"}})
    %{s | carried: true, plugins: Map.merge(carried, s.plugins)}
  end

  # Why a proposal is refused, or nil: by a party, a known change and
  # tier, never an installable's off (that is either party's directly),
  # fitting the plugin's state, one open proposal a plugin at a time.
  defp propose_refusal(s, c), do: shape_refusal(c) || state_refusal(s, c)

  defp shape_refusal(c) do
    cond do
      not party?(c.actor) ->
        {:error, Error.new(:agathos_daimon_not_a_party, :agathos_daimon_plugin_propose_party)}

      c.change not in @changes or c.tier not in @tiers or not is_binary(c.key) ->
        {:error,
         Error.new(:agathos_daimon_plugin_invalid, :agathos_daimon_plugin_propose_invalid)}

      c.change == "off" and c.tier == "installable" ->
        {:error,
         Error.new(:agathos_daimon_plugin_invalid, :agathos_daimon_plugin_propose_off_direct)}

      true ->
        nil
    end
  end

  defp state_refusal(s, c) do
    cond do
      not fits?(Map.get(s.plugins, c.key), c.change) ->
        {:error,
         Error.new(:agathos_daimon_plugin_invalid, :agathos_daimon_plugin_propose_state,
           key: c.key,
           change: c.change
         )}

      Enum.any?(s.proposals, fn {_n, p} -> p.open and p.key == c.key end) ->
        {:error,
         Error.new(:agathos_daimon_plugin_invalid, :agathos_daimon_plugin_propose_open,
           key: c.key
         )}

      true ->
        nil
    end
  end

  # Whether a change fits a plugin's state: an install of one not
  # installed, an on or off of one installed and the other way, a removal
  # of one installed.
  defp fits?(nil, "install"), do: true
  defp fits?(%{installed: false}, "install"), do: true
  defp fits?(%{installed: true}, "remove"), do: true
  defp fits?(%{installed: true, on: false}, "on"), do: true
  defp fits?(%{installed: true, on: true}, "off"), do: true
  defp fits?(_state, _change), do: false

  defp party?(%{kind: kind}), do: kind in [:resident, :witness]

  defp kind(%{kind: kind}) when is_atom(kind), do: kind
  defp kind(%{"kind" => kind}), do: String.to_existing_atom(kind)
end

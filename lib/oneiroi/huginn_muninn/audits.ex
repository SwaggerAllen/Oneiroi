defmodule Oneiroi.HuginnMuninn.Audits do
  @moduledoc """
  The audits aggregate on `audits-<resident_id>` (spec §6.13). Pure: it
  holds the counters by key (a counter's value is the fold of its
  increments here as in the projection), the steward's audits, and
  nothing of the runs, which are a record and never a rule.
  """

  alias Oneiroi.HuginnMuninn.Commands
  alias Oneiroi.HuginnMuninn.Events

  defstruct [:id, counters: %{}, audits: %{}]

  @key ~r/\A[a-z0-9][a-z0-9_-]{0,39}\z/
  @ops ~w(>= <= == > <)
  @tones ~w(warn fail)
  @label_limit 80

  @doc "What a steward's audit compares with."
  def ops, do: @ops
  @doc "The tones a failing audit may carry."
  def tones, do: @tones

  # ---- counters ----

  def execute(%__MODULE__{counters: counters}, %Commands.DefineCounter{} = c) do
    cond do
      not key_ok?(c.key) ->
        {:error, :key_invalid}

      not label_ok?(c.label) ->
        {:error, :label_invalid}

      Map.has_key?(counters, c.key) ->
        []

      true ->
        %Events.CounterDefined{actor: c.actor, at: c.at, id: c.id, key: c.key, label: c.label}
    end
  end

  def execute(%__MODULE__{counters: counters}, %Commands.IncrementCounter{} = c) do
    cond do
      not Map.has_key?(counters, c.key) ->
        {:error, :no_such_counter}

      not (is_integer(c.by) and c.by != 0) ->
        {:error, :increment_invalid}

      true ->
        %Events.CounterIncremented{
          actor: c.actor,
          at: c.at,
          id: c.id,
          key: c.key,
          by: c.by,
          note: c.note
        }
    end
  end

  def execute(%__MODULE__{counters: counters}, %Commands.RetireCounter{} = c) do
    if Map.has_key?(counters, c.key),
      do: %Events.CounterRetired{actor: c.actor, at: c.at, id: c.id, key: c.key},
      else: {:error, :no_such_counter}
  end

  # ---- the steward's audits ----

  def execute(%__MODULE__{audits: audits}, %Commands.DefineUserAudit{} = c) do
    cond do
      not key_ok?(c.key) ->
        {:error, :key_invalid}

      not label_ok?(c.label) ->
        {:error, :label_invalid}

      c.op not in @ops or not is_integer(c.value) or c.tone not in @tones ->
        {:error, :rule_invalid}

      Map.get(audits, c.key) == rule(c) ->
        []

      true ->
        defined(c)
    end
  end

  def execute(%__MODULE__{audits: audits}, %Commands.RetireUserAudit{} = c) do
    if Map.has_key?(audits, c.key),
      do: %Events.UserAuditRetired{actor: c.actor, at: c.at, id: c.id, key: c.key},
      else: {:error, :no_such_audit}
  end

  def execute(%__MODULE__{}, %Commands.RecordRun{} = c) do
    if c.tone in ["ok" | @tones],
      do: %Events.AuditRun{
        actor: c.actor,
        at: c.at,
        id: c.id,
        key: c.key,
        builtin: c.builtin == true,
        tone: c.tone,
        value: c.value,
        finding: c.finding
      },
      else: {:error, :rule_invalid}
  end

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.CounterDefined{} = e),
    do: %{s | id: e.id, counters: Map.put(s.counters, e.key, 0)}

  def apply(%__MODULE__{} = s, %Events.CounterIncremented{} = e),
    do: %{s | counters: Map.update(s.counters, e.key, e.by, &(&1 + e.by))}

  def apply(%__MODULE__{} = s, %Events.CounterRetired{} = e),
    do: %{s | counters: Map.delete(s.counters, e.key)}

  def apply(%__MODULE__{} = s, %Events.UserAuditDefined{} = e),
    do: %{s | id: e.id, audits: Map.put(s.audits, e.key, rule(e))}

  def apply(%__MODULE__{} = s, %Events.UserAuditRetired{} = e),
    do: %{s | audits: Map.delete(s.audits, e.key)}

  def apply(%__MODULE__{} = s, %Events.AuditRun{} = e), do: %{s | id: e.id}

  # ---- helpers ----

  defp defined(c) do
    %Events.UserAuditDefined{
      actor: c.actor,
      at: c.at,
      id: c.id,
      key: c.key,
      label: c.label,
      figure: c.figure,
      op: c.op,
      value: c.value,
      tone: c.tone,
      counts: c.counts == true
    }
  end

  defp rule(c),
    do: %{
      label: c.label,
      figure: c.figure,
      op: c.op,
      value: c.value,
      tone: c.tone,
      counts: c.counts == true
    }

  defp key_ok?(key), do: is_binary(key) and Regex.match?(@key, key)

  defp label_ok?(label),
    do: is_binary(label) and String.trim(label) != "" and String.length(label) <= @label_limit
end

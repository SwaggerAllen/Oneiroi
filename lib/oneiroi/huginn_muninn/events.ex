defmodule Oneiroi.HuginnMuninn.Events do
  @moduledoc """
  The audits stream's events, version 1 (spec §3.1, §6.12, §6.13):
  `audits-<resident_id>`, one per resident: the counters and their
  increments with their actor (the concession-count pattern), the
  steward's audits, and every run's result with its tone.
  """

  defmodule CounterDefined do
    # A figure of kind counter (F57): a key the steward names; its value
    # is the fold of its increments, never a literal anywhere.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :label]
  end

  defmodule CounterIncremented do
    use Oneiroi.Event, version: 1, fields: [:id, :key, :by, :note]
  end

  defmodule CounterRetired do
    use Oneiroi.Event, version: 1, fields: [:id, :key]
  end

  defmodule UserAuditDefined do
    # A steward's audit (F48): a rule over a figure, with a tone when it
    # fails and whether it counts toward the check-engine light.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :key, :label, :figure, :op, :value, :tone, :counts]
  end

  defmodule UserAuditRetired do
    use Oneiroi.Event, version: 1, fields: [:id, :key]
  end

  defmodule AuditRun do
    # One run of one audit, built-in or the steward's: the tone (ok, warn,
    # fail), the value read, the finding in words.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :builtin, :tone, :value, :finding]
  end
end

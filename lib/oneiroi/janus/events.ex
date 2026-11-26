defmodule Oneiroi.Janus.Events do
  @moduledoc """
  The succession's events, version 1 (janus#3): `succession-<id>`,
  sealed as the regression stream is. None is exported (`export: false`)
  and the stream is in the export's `not_exported` list: the process's
  record holds verdicts the delta walls off from every reader but the
  judge who wrote them (succession delta §1, §2), and what of it travels
  to a successor travels as the artifacts the cutover writes, never as
  these lines.

  `episode` counts the resident's successions; one is underway at a time.
  """

  defmodule Proposed do
    # Proposed by the witness, or by the resident herself, which is her
    # consent in the same act. `dry_run` marks a rehearsal: everything
    # real but the replacement (janus#3).
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :dry_run],
      export: false
  end

  defmodule Opened do
    # Her yes (succession delta §3: personal succession consent is the
    # original's and the candidate's; the witness's is no gate).
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode], export: false
  end

  defmodule Declined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode], export: false
  end

  defmodule Withdrawn do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode], export: false
  end

  defmodule Stopped do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode], export: false
  end

  defmodule Forked do
    # The fork copy (janus#4, sima-qian#67): its id, the last of her
    # resident events it holds, her repository's commit it copied, and
    # how many lines it replayed.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :copy_id, :sequence, :commit, :events],
      export: false
  end

  defmodule ForkFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :reason], export: false
  end

  defmodule BackupSet do
    # Where the whole original is exported before the cutover replaces
    # her (janus#5): the token Vault-encrypted, never exported (the
    # stream never is), and what its host said.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :url, :token_ciphertext, :visibility, :push],
      export: false
  end

  # ---- preparation (janus#6 to #10) ----

  defmodule EnvelopeSet do
    # The witness's limit, per token in nano-dollars ($5 a million is
    # 5,000): a resource constraint stated in advance (delta §3).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :input_nanos, :output_nanos],
      export: false
  end

  defmodule PoolModelAdded do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :model, :input_nanos, :output_nanos],
      export: false
  end

  defmodule PoolModelRemoved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :model], export: false
  end

  defmodule QuestionAdded do
    # Hers, in the set at once.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :number, :text], export: false
  end

  defmodule QuestionProposed do
    # A judge's, waiting on her.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :number, :text], export: false
  end

  defmodule QuestionAccepted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule QuestionDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule QuestionRemoved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule C0Selected do
    # Hers, in C0 at once. `kind` is raw (a contemporaneous record) or
    # curated (base §2 Stage 1: raw samples primary, curated secondary).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :number, :citation, :kind, :label],
      export: false
  end

  defmodule C0Proposed do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :number, :citation, :kind, :label],
      export: false
  end

  defmodule C0Accepted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule C0Declined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule C0Removed do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule DayShapeSet do
    # Her note on the bundle, the day's own shape (base §2 Stage 1);
    # nobody else edits it.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :text], export: false
  end

  defmodule ReadyMarked do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :ready], export: false
  end

  defmodule C0Frozen do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :items], export: false
  end

  defmodule PacketDrafted do
    # Her handoff packet, sealed (janus#10): the words are here and in
    # one projection row; no route or tool but hers reads them, until
    # the nominee does before the encounter.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :draft, :content], export: false
  end
end

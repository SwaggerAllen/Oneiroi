defmodule Oneiroi.Brain.Plugin do
  @moduledoc """
  A plugin (brain#68; the witness, 2026-11-07: "every memory slot should
  be implemented as a plugin"): one slot of the turn's context, under a
  manifest saying what it is, what it reads and where it sits. Every
  memory slot is one, first-party ones included, so a slot is added,
  removed or switched the way any plugin is. The sealed parts of the
  context are not plugins: the prompt, the identity files, the
  contract, the transcript window, the once-only notices, where the
  conversation is, and a compaction summary.

  `sections/2` answers the slot's sections for a turn as the assembly
  records them: a label, a system message and the injection row. `ctx`
  is what the turn computed once for every slot: `text` (the witness's
  words), `vector` (their embedding, or nil), `index` (the ranked index)
  and `session`.

  The helpers every slot builds with live here, a leaf, so a slot and
  the turn that assembles it never depend on each other.
  """

  @type section :: %{label: String.t(), message: map() | nil, injection: map()}

  @callback manifest() :: %{
              key: String.t(),
              name: String.t(),
              about: String.t(),
              place: :prefix | :turn,
              reads: [String.t()]
            }
  @callback sections(turn :: map(), ctx :: map()) :: [section()]

  # A section of the context: a system message and the injection that
  # records it; nothing when the text is empty, so an absent section is
  # absent from both.
  @doc "A section of the context: its system message and its injection row; nothing when the text is empty."
  def section(label, text, reason, extra \\ %{})

  def section(label, text, reason, extra) when is_binary(text) and text != "" do
    [
      %{
        label: label,
        message: %{role: :system, content: text},
        injection: Map.merge(%{tokens: tokens(text), reason: fit(reason)}, extra)
      }
    ]
  end

  def section(_label, _text, _reason, _extra), do: []

  # The injection row's reason column is 255 characters wide, and a
  # longer reason takes the conversations projector down after the turn
  # has answered (decisions round 29), so the write is cut here with a
  # mark that says it was, rather than the projector failing quietly.
  @bytes_per_token 4

  @reason_width 255

  def fit(reason) when is_binary(reason) and byte_size(reason) > @reason_width,
    do: binary_part(reason, 0, @reason_width - 3) <> "..."

  def fit(reason), do: reason

  def tokens(text) when is_binary(text),
    do: div(byte_size(text) + @bytes_per_token - 1, @bytes_per_token)

  def tokens(_other), do: 0

  # A trial reads memory as it stands, refreshing no vector, and bills
  # the reads' embeddings as its calls are billed, under regression to
  # the run's actor, which the resident's ledger view omits (eunomia
  # #10, #12).
  def trial_reads(%{trial?: true, payer: payer}),
    do: %{purpose: :regression, refresh: false, actor: payer}

  def trial_reads(_turn), do: %{}
end

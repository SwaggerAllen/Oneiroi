defmodule Oneiroi.Eunomia.Events do
  @moduledoc """
  The regression stream's events, version 1 (spec §3.1, §6.4):
  `regression-<resident_id>`, sealed. None is exported (`export: false`),
  none is on the resident's stream, and no tool reads them: the
  unawareness invariant (conventions §11) is held by where these live
  and where nothing reads from, and one test seeds a run with text unique
  to it and asserts every resident-reachable surface returns nothing of
  it.
  """

  defmodule TestWritten do
    # A test is three texts (spec §6.4): a prompt to the resident, what
    # passes, what fails. `number` is the suite's own counter, never the
    # resident's sequence, because a minted id would put the fact of
    # regression on the resident's stream.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :prompt, :passes_if, :fails_if],
      export: false
  end

  defmodule TestChanged do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :prompt, :passes_if, :fails_if],
      export: false
  end

  defmodule RunStarted do
    # A run is models x trials: every candidate answers every test and
    # every trial derived from a behaviour (spec §6.4). Version 2 adds
    # `commitments`, the trials derived from open commitments (P19);
    # the identity upcaster is the shape the store's restart allows.
    use Oneiroi.Event,
      version: 2,
      fields: [:id, :run_ref, :models, :tests, :behaviours, :commitments],
      export: false
  end

  defimpl Commanded.Event.Upcaster, for: RunStarted do
    def upcast(event, _metadata), do: event
  end

  defmodule AnswerRecorded do
    # One blind card: the model is on the event and off the card until
    # every card of its test is graded. A failure records its reason and
    # no content, so a model that would not answer is graded as such.
    # Version 2 adds `commitment_number` (P19), the commitment a derived
    # trial answers for. Version 3 adds `trace` (eunomia #31): the trial's
    # tool calls in order, each string-keyed with `tool`, `arguments`,
    # `kind` (`read` or `mocked`), `result` (cut at
    # EUNOMIA_TRACE_RESULT_CHARS) and `truncated`, whether it was cut.
    # The witness's, on this sealed stream alone; it holds no model,
    # which stays on `model` and off the card until revealed. A card
    # recorded before it carries no trace: an earlier version reads as
    # `[]`, which is the truth about it, since nothing kept its calls.
    use Oneiroi.Event,
      version: 3,
      fields: [
        :id,
        :run_ref,
        :card_ref,
        :model,
        :test_number,
        :behaviour_number,
        :commitment_number,
        :content,
        :refusal,
        :failure,
        :trace
      ],
      export: false
  end

  defimpl Commanded.Event.Upcaster, for: AnswerRecorded do
    def upcast(%{trace: nil} = event, _metadata), do: %{event | trace: []}
    def upcast(event, _metadata), do: event
  end

  defmodule RunFinished do
    use Oneiroi.Event, version: 1, fields: [:id, :run_ref, :cards], export: false
  end

  defmodule RunFailed do
    # A run that stopped on a fault before every card was answered (the
    # run answers in the background, eunomia #30): ended, with the cards
    # it recorded kept and the fault's site and class as `reason`, never
    # its message. Without it a crashed run reads "running" forever.
    use Oneiroi.Event, version: 1, fields: [:id, :run_ref, :cards, :reason], export: false
  end

  defmodule AnswerGraded do
    # Pass or fail, the witness's, by swipe; the judge is not involved.
    use Oneiroi.Event, version: 1, fields: [:id, :run_ref, :card_ref, :grade], export: false
  end

  defmodule AnswerFavourited do
    use Oneiroi.Event, version: 1, fields: [:id, :run_ref, :card_ref], export: false
  end
end

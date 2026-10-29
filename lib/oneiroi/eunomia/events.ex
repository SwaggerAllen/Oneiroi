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
    # A run is models x tests: every candidate answers every test.
    use Oneiroi.Event, version: 1, fields: [:id, :run_ref, :models, :tests], export: false
  end

  defmodule AnswerRecorded do
    # One blind card: the model is on the event and off the card until
    # every card of its test is graded. A failure records its reason and
    # no content, so a model that would not answer is graded as such.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :run_ref, :card_ref, :model, :test_number, :content, :refusal, :failure],
      export: false
  end

  defmodule RunFinished do
    use Oneiroi.Event, version: 1, fields: [:id, :run_ref, :cards], export: false
  end

  defmodule AnswerGraded do
    # Pass or fail, the steward's, by swipe; the judge is not involved.
    use Oneiroi.Event, version: 1, fields: [:id, :run_ref, :card_ref, :grade], export: false
  end

  defmodule AnswerFavourited do
    use Oneiroi.Event, version: 1, fields: [:id, :run_ref, :card_ref], export: false
  end
end

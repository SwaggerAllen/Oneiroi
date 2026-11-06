defmodule Oneiroi.AgathosDaimon.Projectors.Asks do
  @moduledoc "Folds the asks streams (agathos-daimon#35) into one row an ask."
  use Oneiroi.Projection, name: "agathos_daimon_asks"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.AgathosDaimon.Events
  alias Oneiroi.AgathosDaimon.Store.Ask

  fold(%Events.AskMade{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :ask,
      %Ask{
        resident_id: e.id,
        number: e.number,
        kind: e.kind,
        subject: e.subject,
        why: e.why,
        asked_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.AskAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :answer,
      from(a in Ask, where: a.resident_id == ^e.id and a.number == ^e.number),
      set: [decision: e.decision, note: e.note, answered_at: e.at]
    )
  end)
end

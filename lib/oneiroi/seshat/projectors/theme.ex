defmodule Oneiroi.Seshat.Projectors.Theme do
  @moduledoc "Folds the theme stream (seshat#56): her proposals and the witness's answers."
  use Oneiroi.Projection, name: "seshat_theme"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Store.ThemeProposal

  fold(%Events.ThemeProposed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :proposal,
      %ThemeProposal{
        resident_id: e.id,
        number: e.number,
        ground: e.ground,
        resident: e.resident,
        witness: e.witness,
        note: e.note,
        proposed_at: e.at
      },
      on_conflict: :nothing
    )
  end)

  fold(%Events.ThemeAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :answer,
      from(p in ThemeProposal, where: p.resident_id == ^e.id and p.number == ^e.number),
      set: [agree: e.agree, answered_by: by(e.actor), answer_note: e.note, answered_at: e.at]
    )
  end)

  defp by(%{kind: kind}), do: to_string(kind)
  defp by(%{"kind" => kind}), do: to_string(kind)
  defp by(_none), do: nil
end

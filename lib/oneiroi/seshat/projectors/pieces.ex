defmodule Oneiroi.Seshat.Projectors.Pieces do
  @moduledoc "Folds the pieces streams (seshat#42) into one review row a piece."
  use Oneiroi.Projection, name: "seshat_pieces"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Store.PieceReview

  fold(%Events.PieceReviewed{} = e, _metadata, fn multi ->
    state = if e.decision == "approve", do: "approved", else: "declined"

    Multi.insert(
      multi,
      :review,
      %PieceReview{
        resident_id: e.id,
        path: e.path,
        state: state,
        note: e.note,
        hash: e.hash,
        decided_at: e.at,
        draft_url: nil,
        drafted_at: nil
      },
      on_conflict: {:replace, [:state, :note, :hash, :decided_at, :draft_url, :drafted_at]},
      conflict_target: [:resident_id, :path]
    )
  end)

  fold(%Events.PieceDrafted{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :drafted,
      from(p in PieceReview, where: p.resident_id == ^e.id and p.path == ^e.path),
      set: [state: "drafted", draft_url: e.draft_url, drafted_at: e.at]
    )
  end)
end

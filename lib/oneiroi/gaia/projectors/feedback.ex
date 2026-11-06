defmodule Oneiroi.Gaia.Projectors.Feedback do
  @moduledoc "Folds the platform reports (gaia#20) into a row a report."
  use Oneiroi.Projection, name: "gaia_feedback"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.Store.Feedback

  fold(%Events.FeedbackFiled{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :feedback,
      %Feedback{
        id: "#{e.id}:#{e.number}",
        stream_key: e.id,
        number: e.number,
        kind: e.kind,
        surface: e.surface,
        body: e.body,
        trace_id: e.trace_id,
        author_kind: e.author_kind,
        author_id: e.author_id,
        account_id: e.account_id,
        resident_id: e.resident_id,
        status: "new",
        filed_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:id]
    )
  end)

  fold(%Events.FeedbackMoved{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :moved,
      from(f in Feedback, where: f.id == ^"#{e.id}:#{e.number}"),
      set: [status: e.status, note: e.note, moved_at: e.at, moved_by: by(e.actor)]
    )
  end)

  defp by(%{kind: kind, id: id}) when is_binary(id), do: "#{kind}:#{id}"
  defp by(%{kind: kind}), do: Atom.to_string(kind)
  defp by(_other), do: nil
end

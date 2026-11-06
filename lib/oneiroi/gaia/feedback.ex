defmodule Oneiroi.Gaia.Feedback do
  @moduledoc """
  The platform reports aggregate (gaia#20), one stream, `feedback`: each
  report numbered from 1, a bug or a feature request, filed by a person
  (their account) or a resident (with the witness's account beside it),
  in the reporter's own words, whole; and its status as it moves, new,
  in work, resolved or closed, each move with a note and its actor.

  Who may move a report is the service's to check (the operator, or the
  triage resident): the aggregate holds what may follow what.
  """

  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events

  defstruct next: 1, statuses: %{}

  @kinds ~w(bug feature_request)
  @statuses ~w(new in_work resolved closed)
  @body 8_000
  @surface 200

  def execute(%__MODULE__{next: n}, %Commands.FileFeedback{} = c) do
    if valid?(c),
      do: %Events.FeedbackFiled{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: n,
        kind: c.kind,
        surface: String.trim(c.surface || ""),
        body: String.trim(c.body),
        trace_id: blank(c.trace_id),
        author_kind: Atom.to_string(c.actor.kind),
        author_id: c.actor.id,
        account_id: c.account_id,
        resident_id: c.resident_id
      },
      else: {:error, Error.new(:gaia_feedback_invalid, :gaia_feedback_file_invalid)}
  end

  def execute(%__MODULE__{statuses: statuses}, %Commands.MoveFeedback{} = c) do
    cond do
      not Map.has_key?(statuses, c.number) ->
        {:error, Error.new(:gaia_no_such_feedback, :gaia_feedback_move_unknown)}

      c.status not in @statuses or not (is_binary(c.note) and String.trim(c.note) != "") ->
        {:error, Error.new(:gaia_feedback_invalid, :gaia_feedback_move_invalid)}

      statuses[c.number] == c.status ->
        []

      true ->
        %Events.FeedbackMoved{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          status: c.status,
          note: c.note
        }
    end
  end

  def apply(%__MODULE__{} = s, %Events.FeedbackFiled{} = e),
    do: %{s | next: e.number + 1, statuses: Map.put(s.statuses, e.number, "new")}

  def apply(%__MODULE__{} = s, %Events.FeedbackMoved{} = e),
    do: %{s | statuses: Map.put(s.statuses, e.number, e.status)}

  defp valid?(c) do
    c.kind in @kinds and is_binary(c.body) and String.trim(c.body) != "" and
      String.length(c.body) <= @body and String.length(c.surface || "") <= @surface and
      is_binary(c.account_id)
  end

  defp blank(nil), do: nil
  defp blank(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))
end

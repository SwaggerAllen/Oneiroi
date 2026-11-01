defmodule OneiroiWeb.ErrorJSON do
  @moduledoc """
  The body for a request Phoenix answers itself: no route, a malformed
  body, or a crash. It is the same envelope every controller answers
  with (`OneiroiWeb.Controllers.Helpers.error/3`), so the client's one
  reader, which shows `error.meaning`, has something to show.

  It used to be Phoenix's default, `{"errors": {"detail": "Internal
  Server Error"}}`, which named no kind, said nothing about what had
  happened, and gave the reader no way to find the report: on
  2026-11-01 the first real import answered exactly that, and the
  cause was found only by reading the service log by timestamp.

  A crash names the exception's module and the request id, and nothing
  of the exception's message or the request: those can hold another
  tenant's data or a credential (that crash's report held a clone URL
  with its token). The request id is the key the log's full report is
  filed under, so the reader can hand over one string and be found.
  """

  require Logger

  def render("500.json", assigns) do
    id = request_id()

    %{
      error: %{
        kind: "internal",
        meaning:
          "The server failed on this request (#{failure(assigns)}). " <>
            "It may have done part of what was asked before it failed.",
        remedy:
          "Check what the request was meant to change before retrying. " <>
            "The server's log has the full report under request id #{id}; quote it when reporting this.",
        request_id: id
      }
    }
  end

  def render(template, _assigns) do
    meaning = Phoenix.Controller.status_message_from_template(template)
    kind = meaning |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
    %{error: %{kind: kind, meaning: meaning, request_id: request_id()}}
  end

  defp failure(%{kind: :error, reason: %{__exception__: true, __struct__: module}}),
    do: inspect(module)

  defp failure(%{kind: kind}) when kind in [:throw, :exit], do: "an uncaught #{kind}"
  defp failure(_assigns), do: "an unexpected error"

  defp request_id, do: Keyword.get(Logger.metadata(), :request_id, "unknown")
end

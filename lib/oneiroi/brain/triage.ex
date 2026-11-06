defmodule Oneiroi.Brain.Triage do
  @moduledoc """
  The button to Lily (gaia#20; design reports-and-feedback.md, the
  witness's call of 2026-11-06): each platform report, as it is filed, is
  a house letter to the triage resident's chat, carrying the report whole;
  the chat's wake is the answer's clock. One letter a report while the
  reporters are few. Eventual, through an event handler, so a report is
  filed whether or not the letter lands.
  """
  use Commanded.Event.Handler,
    application: Oneiroi.Commanded,
    name: "brain_triage",
    consistency: :eventual

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.Gaia.Events.FeedbackFiled

  @impl Commanded.Event.Handler
  def init(config) do
    Oneiroi.Scope.put(:platform)
    {:ok, config}
  end

  @impl Commanded.Event.Handler
  def handle(%FeedbackFiled{} = e, _metadata) do
    case Oneiroi.Gaia.triage_resident() do
      nil ->
        :ok

      triage ->
        _ =
          Oneiroi.Kumbukumbu.send_letter(
            triage,
            nil,
            %{to: "Oneiroi chat", text: letter(e)},
            Actor.new(:job, "platform_reports")
          )

        :ok
    end
  end

  # A letter that could not be sent is said and passed over, never a stop:
  # a handler that stops is restarted onto the same event until the
  # supervisor gives up, and the application goes down with it (gaia#17
  # learned it first). The report itself is filed either way.
  @impl Commanded.Event.Handler
  def error({:error, reason}, _event, _context) do
    Logger.error("brain: a platform report's letter was not sent: #{inspect(reason)}",
      component: "brain"
    )

    :skip
  end

  def error(_failure, _event, _context), do: :skip

  defp letter(e) do
    email = Oneiroi.Gaia.account_email(e.account_id) || e.account_id

    from =
      case {e.author_kind, e.resident_id && Oneiroi.AgathosDaimon.fetch(e.resident_id)} do
        {"resident", {:ok, r}} -> "#{r.name} (#{r.slug}), a resident, whose witness is #{email}"
        {"resident", _gone} -> "the resident #{e.resident_id}, whose witness is #{email}"
        _person -> email
      end

    """
    Platform report ##{e.number}, a #{String.replace(e.kind, "_", " ")}, from #{from}, on #{if e.surface in [nil, ""], do: "the platform", else: e.surface}#{if e.trace_id, do: ", trace #{e.trace_id}", else: ""}:

    #{e.body}

    triage_list reads it with the rest; triage_move moves it with a note the reporter reads.
    """
  end
end

defmodule Oneiroi.Brain.Checkin do
  @moduledoc """
  The parts of a check-in's note the brain reads (sunna#28): each a short
  section from records, read when the check-in fires, with no model call.
  A part with nothing to report says so in a line, so a checked box is
  never silently empty. The words are the records' own (the plan rows are
  hers, a letter is named by number and sender, never quoted).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna
  alias Oneiroi.Xenia

  @row_chars 300

  @doc "The text of one part, or nil for a key the brain does not read."
  @spec part(String.t(), String.t()) :: String.t() | nil
  def part(resident_id, "plan"), do: plan(resident_id)
  def part(resident_id, "free_time"), do: free_time(resident_id)
  def part(resident_id, "research"), do: research(resident_id)
  def part(resident_id, "letters"), do: letters(resident_id)
  def part(resident_id, "needs_you"), do: needs_you(resident_id)
  def part(_resident_id, _key), do: nil

  defp plan(resident_id) do
    %{day: day} = Sunna.today(resident_id)

    rows =
      case Seshat.journal_day(resident_id, day) do
        %{entries: entries} -> entries
        nil -> []
      end

    plans = Enum.filter(rows, &(&1.kind == "plan"))
    todos = Enum.filter(rows, &(&1.kind == "todo" and is_nil(&1.done_at)))

    if plans == [] and todos == [] do
      "# Today's plan\n\nNo plan written for #{day}, and no open todos."
    else
      lines =
        Enum.map(plans ++ todos, &"- #{&1.kind} ##{&1.number}: #{cut(&1.summary || &1.text)}")

      Enum.join(["# Today's plan\n\nFrom your journal for #{day}:" | lines], "\n")
    end
  end

  defp free_time(resident_id) do
    case Sunna.today(resident_id).free_times do
      [] ->
        "# Free time\n\nNo free time is set."

      slots ->
        lines =
          Enum.map(slots, fn
            %{time: time, today: nil} -> "- #{time}: still ahead"
            %{time: time, today: outcome} -> "- #{time}: #{outcome}"
          end)

        Enum.join(["# Free time\n\nToday's slots:" | lines], "\n")
    end
  end

  defp research(resident_id) do
    since = DateTime.add(Clock.now(), -1, :day)
    rows = Seshat.researches(resident_id, [])
    open = Enum.count(rows, &(&1.status == "open"))

    settled =
      Enum.filter(rows, &(&1.settled_at && DateTime.compare(&1.settled_at, since) == :gt))

    lines =
      Enum.map(settled, fn r ->
        where = if r.path, do: " (#{r.path})", else: ""
        "- ##{r.number} #{r.status}#{where}: #{cut(r.question)}"
      end)

    head =
      "# Research\n\n#{open} open. Settled since yesterday: #{if lines == [], do: "none", else: length(lines)}."

    Enum.join([head | lines], "\n")
  end

  defp letters(resident_id) do
    with {:ok, row} <- Oneiroi.AgathosDaimon.fetch(resident_id),
         {:ok, key} <-
           Kumbukumbu.main_session(resident_id, row.account_id, Actor.platform()) do
      case Kumbukumbu.inbox(resident_id, key) do
        [] ->
          "# Letters\n\nNone waiting for this chat."

        waiting ->
          lines = Enum.map(waiting, &"- ##{&1.number} from #{&1.from_name}")

          Enum.join(
            [
              "# Letters\n\n#{length(waiting)} waiting for this chat; letter_inbox reads them."
              | lines
            ],
            "\n"
          )
      end
    else
      _absent -> nil
    end
  end

  defp needs_you(resident_id) do
    case Xenia.needs_you(resident_id) do
      %{replies: 0} ->
        "# Waiting on the person who looks after you\n\nNothing."

      %{replies: n} ->
        "# Waiting on the person who looks after you\n\n#{n} reply draft(s) to approve."
    end
  end

  defp cut(text) do
    text = text |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > @row_chars, do: String.slice(text, 0, @row_chars) <> "…", else: text
  end
end

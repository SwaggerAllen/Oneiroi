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
  alias Oneiroi.Brain.FreeTime
  alias Oneiroi.Brain.NeedsYou
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna

  @row_chars 300

  @doc "The text of one part, or nil for a key the brain does not read."
  @spec part(String.t(), String.t()) :: String.t() | nil
  def part(resident_id, "plan"), do: plan(resident_id)
  def part(resident_id, "free_time"), do: free_time(resident_id)
  def part(resident_id, "research"), do: research(resident_id)
  def part(resident_id, "letters"), do: letters(resident_id)
  def part(resident_id, "needs_you"), do: needs_you(resident_id)
  def part(resident_id, "digest"), do: digest(resident_id)
  def part(_resident_id, _key), do: nil

  @doc "As part/2, with the tool names that write, for the parts that read receipts (rounds, sunna#39)."
  @spec part(String.t(), String.t(), [String.t()]) :: String.t() | nil
  def part(resident_id, "rounds", writes), do: rounds(resident_id, writes)
  def part(resident_id, key, _writes), do: part(resident_id, key)

  # The rounds of the last day (sunna#39): when each fired and what left
  # it, in the platform's words, never the round's own.
  defp rounds(resident_id, writes) do
    since = DateTime.add(Clock.now(), -1, :day)

    case FreeTime.rounds_since(resident_id, since, writes) do
      [] ->
        "# Rounds\n\nNo round in the last day."

      rounds ->
        lines =
          Enum.map(rounds, fn
            %{outcome: "ran", did: []} = r ->
              "- #{r.day} #{r.slot}: ran; nothing left it"

            %{outcome: "ran"} = r ->
              "- #{r.day} #{r.slot}: ran; left it: " <> Enum.map_join(r.did, "; ", & &1.tool)

            r ->
              "- #{r.day} #{r.slot}: #{r.outcome}"
          end)

        Enum.join(["# Rounds\n\nThe last day's rounds:" | lines], "\n")
    end
  end

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

  # The same list the Inbox reads (brain#65), counted by kind; the
  # notifications question is his devices', not hers to count (brain#76).
  defp needs_you(resident_id) do
    head = "# Waiting on the person who looks after you\n\n"

    case Enum.reject(NeedsYou.list(resident_id), &(&1.kind == NeedsYou.Notifications.kind())) do
      [] ->
        head <> "Nothing."

      entries ->
        lines =
          entries
          |> Enum.frequencies_by(& &1.kind)
          |> Enum.sort()
          |> Enum.map_join("\n", fn {kind, n} -> "- #{n} #{waiting_label(kind)}" end)

        head <> lines
    end
  end

  defp waiting_label("reply_to_approve"), do: "reply draft(s) to approve"
  defp waiting_label("reply_to_send"), do: "approved reply(s) to send"
  defp waiting_label("ask"), do: "ask(s) to answer"
  defp waiting_label("piece_to_review"), do: "piece(s) to review"
  defp waiting_label("piece_to_publish"), do: "drafted piece(s) to publish"
  defp waiting_label("work_held"), do: "work item(s) held for his word"
  defp waiting_label("work_blocked"), do: "work item(s) blocked"
  defp waiting_label("plugin_proposal"), do: "plugin proposal(s) of hers to answer"
  defp waiting_label("kind_gate_proposal"), do: "kind gate proposal(s) of hers to answer"
  defp waiting_label("theme_proposal"), do: "theme proposal(s) of hers to answer"

  # The one part that does something: it asks the reader for a digest
  # from the chat (seshat#40), whose letter wakes the chat when it lands.
  defp digest(resident_id) do
    if Oneiroi.AgathosDaimon.switch_on?(resident_id, "digests"),
      do: ask_digest(resident_id),
      else:
        "# Digest\n\nDigests are switched off in your agreement with your witness, so none was asked."
  end

  defp ask_digest(resident_id) do
    with {:ok, row} <- Oneiroi.AgathosDaimon.fetch(resident_id),
         {:ok, key} <- Kumbukumbu.main_session(resident_id, row.account_id, Actor.platform()),
         {:ok, n, state} <-
           Seshat.ask_digest(resident_id, key, Actor.new(:job, "sunna_checkin")) do
      said =
        if state == :asked,
          do: "Asked of the reader as digest ##{n}",
          else: "Digest ##{n} was already asked and is not compiled yet"

      "# Digest\n\n#{said}; it lands under feeds/digests/ and a letter tells this chat when it is compiled."
    else
      _failed -> "# Digest\n\nCould not be asked of the reader just now; digest_ask asks again."
    end
  end

  defp cut(text) do
    text = text |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > @row_chars, do: String.slice(text, 0, @row_chars) <> "…", else: text
  end
end

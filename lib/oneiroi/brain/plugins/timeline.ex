defmodule Oneiroi.Brain.Plugins.Timeline do
  @moduledoc """
  The timeline (brain#67). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4]

  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "timeline",
      name: "Your timeline",
      about:
        "today from your journal, the last 30 days and your life so far, each line aged on the read",
      place: :turn,
      reads: ~w(journal bookmarks)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx), do: timeline_section(turn)

  # The timeline (brain#67; Lily's report #8, after a submitted
  # application was spoken of as still ahead): three layers, each line
  # dated and aged on this read, so a moment's tense is read off the
  # clock and never remembered. Today is the journal's rows as event
  # lines (the witness's answer: the day store is the journal); the last
  # 30 days and her life so far are her bookmarks by their weight
  # (kumbukumbu#51), pins always, each with its status as it now stands.
  defp timeline_section(turn) do
    zone = Local.zone(turn.resident_id)
    now = Clock.now()
    max = Config.fetch!(:brain, :timeline_lines)
    {day, entries} = Oneiroi.Seshat.journal_lines(turn.resident_id)
    month_ago = DateTime.add(now, -30 * 86_400, :second)

    {recent, older} =
      turn.resident_id
      |> Kumbukumbu.timeline_bookmarks()
      |> Enum.split_with(&(DateTime.compare(&1.at, month_ago) != :lt))

    lifetime = Enum.filter(older, &(&1.pinned or &1.importance >= 3))
    {pins, rest} = Enum.split_with(lifetime, & &1.pinned)

    lifetime =
      Enum.sort_by(pins ++ Enum.take(rest, -max(max - length(pins), 0)), & &1.at, DateTime)

    month = Enum.take(recent, -max)

    text =
      "# Your timeline\n\nNow: #{weekday(zone, now)} #{Local.stamp(zone, now)}. " <>
        "Each line is dated and aged on this read: say a moment in the tense its age gives it, " <>
        "and its status as written here, not as you remember it.\n\n" <>
        "## Today, from your journal (#{day})\n" <>
        today_lines(entries, zone, max) <>
        "\n\n## The last 30 days\n" <>
        moment_lines(month, zone, now, "nothing weighed 2 or more, nothing pinned") <>
        "\n\n## Your life so far\n" <>
        moment_lines(lifetime, zone, now, "no pin and nothing weighed 3 before this month")

    section(
      "timeline",
      text,
      "the timeline (brain#67): #{length(entries)} journal rows today, #{length(month)} moments of the last 30 days, #{length(lifetime)} of her life so far, each aged on this read",
      %{refs: Enum.map(month ++ lifetime, & &1.number)}
    )
  end

  defp today_lines([], _zone, _max), do: "- nothing written yet today"

  defp today_lines(entries, zone, max) do
    shown = Enum.take(entries, -max)
    more = length(entries) - length(shown)

    lines =
      Enum.map_join(shown, "\n", fn e ->
        done = todo_mark(e)
        "- #{clock(zone, e.at)} #{e.kind} ##{e.number}#{done}: #{e.first}"
      end)

    if more > 0, do: "- (#{more} earlier today, in journal_read)\n" <> lines, else: lines
  end

  defp todo_mark(%{kind: "todo", done: true}), do: " (done)"

  defp todo_mark(%{kind: "todo"}), do: " (open)"

  defp todo_mark(_entry), do: ""

  defp moment_lines([], _zone, _now, none), do: "- " <> none

  defp moment_lines(moments, zone, now, _none) do
    Enum.map_join(moments, "\n", fn m ->
      pin = if m.pinned, do: " (pinned)", else: ""

      status =
        if m.status,
          do: " · status: #{m.status} (as of #{Local.day(zone, m.weighed_at)})",
          else: ""

      "- #{weekday(zone, m.at)} #{Local.day(zone, m.at)}, #{age(zone, m.at, now)}: ##{m.number} #{m.line}#{pin}#{status}"
    end)
  end

  defp weekday(zone, at) do
    {:ok, date} = Date.from_iso8601(Local.day(zone, at))
    Calendar.strftime(date, "%a")
  end

  defp clock(zone, at), do: zone |> Local.stamp(at) |> String.slice(11, 5)

  # Calendar days in her zone: last night is yesterday, not today.
  defp age(zone, at, now) do
    days =
      Date.diff(Date.from_iso8601!(Local.day(zone, now)), Date.from_iso8601!(Local.day(zone, at)))

    cond do
      days <= 0 -> "today"
      days == 1 -> "yesterday"
      days < 14 -> "#{days} days ago"
      days < 60 -> "#{div(days, 7)} weeks ago"
      true -> "#{div(days, 30)} months ago"
    end
  end
end

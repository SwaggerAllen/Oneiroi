defmodule Oneiroi.Kumbukumbu.Days do
  @moduledoc """
  The resident's local days as ranges of instants (kumbukumbu#57, #58):
  a query's `from` and `to`, each an ISO date or an ISO instant, read in
  her zone, and the per-day counts the navigator draws its track from.
  A date is a whole local day: `from` its first instant, `to` the first
  instant of the day after, so `to=2026-11-10` includes the 10th. An
  instant is taken as given, `from` inclusive and `to` exclusive. The
  day of an instant is its ISO date in her zone, as the schedule reads
  it (`Oneiroi.Sunna.Schedules.local_day/1`).
  """

  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu.Conversation
  alias Oneiroi.Kumbukumbu.Conversations
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  # The longest track one density read draws: a year and a day.
  @max_days 366
  @default_days 30

  @doc """
  A bound of a range as an instant: nil for none, else `{:ok, instant}`
  for an ISO date (its local midnight, or the next day's for `:to`) or an
  ISO instant; `{:error, _}` for anything else.
  """
  @spec bound(String.t(), String.t() | nil, :from | :to) ::
          {:ok, DateTime.t() | nil} | {:error, Error.t()}
  def bound(_zone, nil, _side), do: {:ok, nil}
  def bound(_zone, "", _side), do: {:ok, nil}

  def bound(zone, text, side) when is_binary(text) do
    case {Date.from_iso8601(text), DateTime.from_iso8601(text)} do
      {{:ok, date}, _} ->
        date = if side == :to, do: Date.add(date, 1), else: date
        {:ok, midnight(date, zone)}

      {_, {:ok, at, _offset}} ->
        {:ok, usec(at)}

      _neither ->
        {:error,
         Error.new(:kumbukumbu_range_invalid, :kumbukumbu_days_bound_invalid,
           value: text,
           side: side
         )}
    end
  end

  def bound(_zone, other, side),
    do:
      {:error,
       Error.new(:kumbukumbu_range_invalid, :kumbukumbu_days_bound_not_text,
         value: inspect(other),
         side: side
       )}

  @doc "A range's two bounds, read in the resident's zone."
  @spec range(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, DateTime.t() | nil, DateTime.t() | nil} | {:error, Error.t()}
  def range(resident_id, from, to) do
    zone = Local.zone(resident_id)

    with {:ok, lo} <- bound(zone, from, :from),
         {:ok, hi} <- bound(zone, to, :to),
         do: {:ok, lo, hi}
  end

  @doc """
  Per local day from `from` through `to` (ISO dates, both included; the
  last #{@default_days} days through today when nil), how many bookmarks
  and messages it holds (kumbukumbu#58): every day of the range, empty
  ones as zeros, oldest first. Messages are counted under `scope`, which
  decides the sessions seen, and of one session when `key` is given;
  bookmarks under the resident's own.
  """
  @spec counts(Scope.t(), String.t(), String.t() | nil, String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, Error.t()}
  def counts(scope, resident_id, from, to, key) do
    zone = Local.zone(resident_id)

    with {:ok, first, last} <- days(zone, from, to) do
      lo = midnight(first, zone)
      hi = midnight(Date.add(last, 1), zone)

      bookmarks =
        Map.new(Scope.resident(resident_id, fn -> Store.bookmark_days(zone, lo, hi) end))

      messages =
        Map.new(Scope.run(scope, fn -> Store.message_days(resident_id, zone, lo, hi, key) end))

      days =
        for date <- Date.range(first, last) do
          day = Date.to_iso8601(date)
          %{day: day, bookmarks: Map.get(bookmarks, day, 0), messages: Map.get(messages, day, 0)}
        end

      {:ok, %{from: Date.to_iso8601(first), to: Date.to_iso8601(last), zone: zone, days: days}}
    end
  end

  @doc """
  The sessions of each local day from `from` through `to` (ISO dates,
  both included), as the witness's calendar reads them (kumbukumbu#59):
  day to `[%{key, kind, title, locked, first_at, last_at, messages}]`,
  first spoken in first; a day with none is left out. The sessions are
  those `scope` lists for this resident, and a session is on each day it
  holds a message the scope reads, with that day's first and last
  instant and its count. A locked session (private and unshared, #28)
  shows none of its messages to the account, so it is on the day it
  opened and the day it was last spoken in, with the row's two instants
  and no count: the receipts the session list already gives. Never a
  word of any message.
  """
  @spec sessions(Scope.t(), String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, %{String.t() => [map()]}} | {:error, Error.t()}
  def sessions(scope, resident_id, from, to) do
    zone = Local.zone(resident_id)

    with {:ok, first, last} <- days(zone, from, to) do
      lo = midnight(first, zone)
      hi = midnight(Date.add(last, 1), zone)
      span = {Date.to_iso8601(first), Date.to_iso8601(last)}

      {rows, seen} =
        Scope.run(scope, fn ->
          {Enum.filter(Store.sessions(), &(&1.resident_id == resident_id)),
           Store.session_days(resident_id, zone, lo, hi)}
        end)

      seen = Enum.group_by(seen, &elem(&1, 0))

      days =
        rows
        |> Enum.flat_map(&placed(&1, Map.get(seen, &1.key, []), zone, span))
        |> Enum.group_by(fn {day, _entry} -> day end, fn {_day, entry} -> entry end)
        |> Map.new(fn {day, entries} ->
          {day, Enum.sort_by(entries, &{DateTime.to_unix(&1.first_at, :microsecond), &1.key})}
        end)

      {:ok, days}
    end
  end

  defp placed(s, seen, zone, span) do
    cond do
      s.private and not s.shared ->
        last_at = Conversations.last_at(s)

        for day <- Enum.uniq([Local.day(zone, s.opened_at), Local.day(zone, last_at)]),
            within?(day, span),
            do: {day, session_entry(s, true, s.opened_at, last_at, nil)}

      seen != [] ->
        for {_key, day, first_at, last_at, n} <- seen,
            do: {day, session_entry(s, false, first_at, last_at, n)}

      within?(Local.day(zone, s.opened_at), span) ->
        [{Local.day(zone, s.opened_at), session_entry(s, false, s.opened_at, s.opened_at, 0)}]

      true ->
        []
    end
  end

  defp within?(day, {first, last}), do: day >= first and day <= last

  defp session_entry(s, locked, first_at, last_at, messages),
    do: %{
      key: s.key,
      kind: s.kind,
      title: Conversation.title(s),
      locked: locked,
      first_at: usec(first_at),
      last_at: usec(last_at),
      messages: messages
    }

  defp days(zone, from, to) do
    today = Clock.now() |> DateTime.shift_zone!(zone) |> DateTime.to_date()

    with {:ok, last} <- date(to, today),
         {:ok, first} <- date(from, Date.add(last, 1 - @default_days)) do
      span = Date.diff(last, first) + 1

      if span in 1..@max_days,
        do: {:ok, first, last},
        else:
          {:error,
           Error.new(:kumbukumbu_range_invalid, :kumbukumbu_days_span_invalid,
             from: Date.to_iso8601(first),
             to: Date.to_iso8601(last),
             max: @max_days
           )}
    end
  end

  defp date(nil, default), do: {:ok, default}
  defp date("", default), do: {:ok, default}

  defp date(text, _default) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} ->
        {:ok, date}

      _other ->
        {:error, Error.new(:kumbukumbu_range_invalid, :kumbukumbu_days_date_invalid, value: text)}
    end
  end

  defp date(other, _default),
    do:
      {:error,
       Error.new(:kumbukumbu_range_invalid, :kumbukumbu_days_date_not_text, value: inspect(other))}

  # The first instant of a local day, in UTC: a midnight the zone skips
  # is the first instant after the gap, one it repeats is the earlier.
  defp midnight(%Date{} = date, zone) do
    at =
      case DateTime.new(date, ~T[00:00:00.000000], zone) do
        {:ok, at} -> at
        {:ambiguous, first, _second} -> first
        {:gap, _before, after_gap} -> after_gap
      end

    at |> DateTime.shift_zone!("Etc/UTC") |> usec()
  end

  defp usec(%DateTime{} = at) do
    {us, _precision} = at.microsecond
    at |> DateTime.shift_zone!("Etc/UTC") |> Map.put(:microsecond, {us, 6})
  end
end

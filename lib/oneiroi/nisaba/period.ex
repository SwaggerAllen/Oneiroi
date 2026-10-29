defmodule Oneiroi.Nisaba.Period do
  @moduledoc """
  A budget line's period and the key an instant falls in: a day, an ISO
  week or a month, in UTC. Pure, so the aggregate can ask it (conventions
  §6): the instant comes from the command, never from a clock here.
  """

  @periods ~w(day week month)a

  @type t :: :day | :week | :month

  @doc "The periods a budget line may name."
  @spec all() :: [t()]
  def all, do: @periods

  @doc "The key `at` falls in under `period`: `2026-10-29`, `2026-W44` or `2026-10`."
  @spec key(t(), DateTime.t()) :: String.t()
  def key(:day, %DateTime{} = at), do: at |> DateTime.to_date() |> Date.to_iso8601()

  def key(:week, %DateTime{} = at) do
    {year, week} = at |> DateTime.to_date() |> Date.to_erl() |> :calendar.iso_week_number()
    "#{year}-W#{String.pad_leading(Integer.to_string(week), 2, "0")}"
  end

  def key(:month, %DateTime{year: y, month: m}),
    do: "#{y}-#{String.pad_leading(Integer.to_string(m), 2, "0")}"

  @doc "The half-open range `[from, to)` of the period `at` falls in."
  @spec range(t(), DateTime.t()) :: {DateTime.t(), DateTime.t()}
  def range(period, %DateTime{} = at) do
    date = DateTime.to_date(at)

    {first, next} =
      case period do
        :day ->
          {date, Date.add(date, 1)}

        :week ->
          first = Date.add(date, 1 - Date.day_of_week(date))
          {first, Date.add(first, 7)}

        :month ->
          first = Date.beginning_of_month(date)
          {first, first |> Date.end_of_month() |> Date.add(1)}
      end

    {DateTime.new!(first, ~T[00:00:00.000000], "Etc/UTC"),
     DateTime.new!(next, ~T[00:00:00.000000], "Etc/UTC")}
  end

  @doc "A period from its wire string, or nil."
  @spec parse(term()) :: t() | nil
  def parse(string) when is_binary(string),
    do: Enum.find(@periods, &(Atom.to_string(&1) == string))

  def parse(atom) when atom in @periods, do: atom
  def parse(_other), do: nil
end

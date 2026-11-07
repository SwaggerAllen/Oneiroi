defmodule Oneiroi.Brain.Plugins.State do
  @moduledoc """
  The state store (agathos-daimon#32, brain#47). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Apsu.Clock

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "state",
      name: "Where things stand",
      about: "your present, in your words, one line per key",
      place: :turn,
      reads: ~w(state)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx), do: state_section(turn)

  # The state store (agathos-daimon#32, brain#47): her present in her
  # own words, first after the identity files and the contract, read
  # fresh on every turn and overwritten in place. Placed here rather
  # than in the stable prefix: the prefix is what an adapter's session is
  # given once, and a present given once is the stale present this cures
  # (the sixth caught error, a migration called planned the day it was
  # done). Caching loses nothing: everything after the contract already
  # changes on every turn.
  @state_keys ~w(where day numbers noticing)

  defp state_section(turn) do
    lines = Oneiroi.AgathosDaimon.state_lines(turn.resident_id)
    by_key = Map.new(lines, &{&1.key, &1})
    others = lines |> Enum.map(& &1.key) |> Enum.reject(&(&1 in @state_keys)) |> Enum.sort()
    now = Clock.now()
    zone = Local.zone(turn.resident_id)

    body =
      Enum.map_join(@state_keys ++ others, "\n", fn key ->
        case Map.get(by_key, key) do
          nil ->
            "- **#{key}**: (not written yet)"

          line ->
            "- **#{key}** (verified #{freshness(line.verified_at, now, zone)}): #{line.text}"
        end
      end)

    text =
      "# Where things stand\n\nYour present, in your words, one line per key, each with when you last verified it. " <>
        "When a line changes, or you confirm it still holds, rewrite it with state_set; it is overwritten, " <>
        "and the transcript and your repository keep every version. Add a key of your own when one earns it; " <>
        "clear it with state_clear when it stops. Keep it small: this is the present, not the archive.\n\n" <>
        body

    section(
      "state",
      text,
      "the state store (agathos-daimon#32): #{length(lines)} line(s) of the resident's present, read fresh, overwritten in place"
    )
  end

  defp freshness(at, now, zone) do
    stamp = Local.stamp(zone, at)

    case DateTime.diff(now, at, :day) do
      0 -> "#{stamp}, today"
      1 -> "#{stamp}, a day ago"
      days -> "#{stamp}, #{days} days ago"
    end
  end
end

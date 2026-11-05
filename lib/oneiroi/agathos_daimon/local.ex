defmodule Oneiroi.AgathosDaimon.Local do
  @moduledoc """
  An instant as the resident reads it (agathos-daimon#33): in her own zone,
  the zone her schedule runs in, with the zone's abbreviation, so a time
  in her context and a time on her schedule are the same kind of time.
  UTC in one place and her zone in another had her read 02:00 UTC as two
  in the morning and say goodnight at six in the evening (the witness,
  2026-11-04: "Lily's timestamps should be in the same time zone as her
  schedule. She'll get confused otherwise").

  For what she is shown. The repository's records (the event files, the
  reading copies) stay in UTC, the same whatever her zone becomes.
  """

  alias Oneiroi.AgathosDaimon.Residents

  @utc "Etc/UTC"

  @doc "The resident's zone, an IANA name; UTC for one that has none or is not found."
  @spec zone(String.t()) :: String.t()
  def zone(resident_id) do
    case Residents.fetch(resident_id) do
      {:ok, %{timezone: zone}} when is_binary(zone) and zone != "" -> zone
      _none -> @utc
    end
  end

  @doc "The instant in `zone`, as `2026-11-04 18:02 PST`."
  @spec stamp(String.t(), DateTime.t()) :: String.t()
  def stamp(zone, %DateTime{} = at) do
    local = shift(at, zone)
    Calendar.strftime(local, "%Y-%m-%d %H:%M ") <> local.zone_abbr
  end

  @doc "The instant's date in `zone`, as `2026-11-04`."
  @spec day(String.t(), DateTime.t()) :: String.t()
  def day(zone, %DateTime{} = at),
    do: at |> shift(zone) |> DateTime.to_date() |> Date.to_iso8601()

  # A zone the database does not know reads as UTC rather than failing
  # the turn that only wanted to show a time.
  defp shift(at, zone) do
    case DateTime.shift_zone(at, zone) do
      {:ok, local} -> local
      {:error, _unknown} -> DateTime.shift_zone!(at, @utc)
    end
  end
end

defmodule Oneiroi.AgathosDaimon.Gifts do
  @moduledoc """
  The creation flow's nine gifts (spec §6.2, F3; agathos-daimon#36), each
  with what it writes and the guidance the witness reads before giving
  it. The guidance lives once, here, in `priv/creation/`: the flow's
  screens show it, and the pre-filled path's generator will read the same
  words, so the witness reads the same text either way (the witness's
  policy, 2026-11-05). Compiled in, so a change to the words is a reviewed
  commit like any other.
  """

  @gifts [
    {"name", "A name", ["IDENTITY.md"], "1-name.md"},
    {"self", "A self", ["SOUL.md"], "2-self.md"},
    {"you", "Who you are to them", ["USER.md"], "3-you.md"},
    {"building", "What you're building together", ["GOALS.md", "LINKS.md"], "4-building.md"},
    {"trials", "Their trials", ["regression tests"], "5-trials.md"},
    {"means", "Their means", ["budget lines"], "6-means.md"},
    {"days", "Their days", ["time zone", "free time", "quiet hours"], "7-days.md"},
    {"vows", "Your vows", ["the agreement"], "8-vows.md"},
    {"reach", "Their reach", ["tier and hands"], "9-reach.md"}
  ]

  for {_key, _title, _writes, file} <- @gifts do
    @external_resource Path.join([__DIR__, "../../../priv/creation", file])
  end

  @all (for {key, title, writes, file} <- @gifts do
          guidance =
            [__DIR__, "../../../priv/creation", file]
            |> Path.join()
            |> File.read!()
            |> String.trim()

          %{key: key, title: title, writes: writes, guidance: guidance}
        end)

  @doc "The nine gifts in the flow's order, each with what it writes and its guidance."
  def all, do: @all
end

defmodule Oneiroi.Brain.Plugins.FreeTimePlan do
  @moduledoc """
  The free-time plan (sunna#31). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  alias Oneiroi.AgathosDaimon.Local

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "free_time_plan",
      name: "Your free-time plan",
      about: "the plan you wrote at the end of your last free-time slot, in free time only",
      place: :turn,
      reads: ~w(schedule)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, ctx) do
    section(
      "free_time_plan",
      free_time_plan(turn, ctx.session),
      "the plan she wrote at the end of her last free-time slot (sunna#31), read in free time only"
    )
  end

  defp free_time_plan(%{purpose: purpose} = turn, %{kind: "free_time"})
       when purpose in [:free_time, :planning] do
    case Oneiroi.Sunna.free_time_plan(turn.resident_id) do
      %{text: text, at: at} ->
        "# Your plan for this free time (written #{Local.stamp(Local.zone(turn.resident_id), at)})\n\n" <>
          text

      nil ->
        nil
    end
  end

  defp free_time_plan(_turn, _session), do: nil
end

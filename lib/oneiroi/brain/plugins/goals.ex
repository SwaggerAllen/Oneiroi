defmodule Oneiroi.Brain.Plugins.Goals do
  @moduledoc """
  Her wanting between slots (brain#55). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  alias Oneiroi.Brain.Introspection

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "goals_between",
      name: "Your goals between slots",
      about: "your own goals file, in free time only",
      place: :turn,
      reads: ~w(repository)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, ctx) do
    section(
      "goals_between",
      free_time_goals(turn, ctx.session),
      "the resident's own goals file (<SLUG>-GOALS.md at her repository's root), read at the start of each free-time turn and in no other conversation (brain#55)"
    )
  end

  # Her wanting between slots (brain#55; the witness's call, 2026-11-05):
  # the file she keeps beside his GOALS.md, LILY-GOALS.md for Lily, read
  # in free time and nowhere else. She edits it with her own tools; this
  # only reads what is there.
  @goals_limit 12_000

  defp free_time_goals(%{purpose: purpose} = turn, %{kind: "free_time"})
       when purpose in [:free_time, :planning] do
    # Through introspection's repository reader, which holds a path to
    # the repository's root, rather than a file opened here.
    with {:ok, %{slug: slug}} <- Oneiroi.AgathosDaimon.fetch(turn.resident_id),
         name = String.upcase(slug) <> "-GOALS.md",
         {:ok, text, _next, _total} <- Introspection.read({:repo, turn.resident_id}, name),
         text when text != "" <- String.trim(text) do
      "# Your goals between slots (#{name}, yours to keep)\n\n" <>
        String.slice(text, 0, @goals_limit)
    else
      _absent -> nil
    end
  end

  defp free_time_goals(_turn, _session), do: nil
end

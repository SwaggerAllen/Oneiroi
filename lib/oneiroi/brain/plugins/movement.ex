defmodule Oneiroi.Brain.Plugins.Movement do
  @moduledoc """
  Where things can resume (spec §6.4, P34). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4]

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "movement",
      name: "Where things can resume",
      about: "resume points from the nightly pass, newest first",
      place: :turn,
      reads: ~w(resume_points)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx) do
    resumable = Oneiroi.Eunomia.resumable(turn.resident_id)

    section(
      "movement",
      resumable.text,
      "where things can resume (spec §6.4, P34): #{resumable.shown} of #{resumable.total} resume points from the nightly pass, newest first, loaded every turn because dormant is not abandoned",
      %{text: resumable.text, refs: resumable.refs}
    )
  end
end

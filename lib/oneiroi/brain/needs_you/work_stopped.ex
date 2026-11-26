defmodule Oneiroi.Brain.NeedsYou.WorkStopped do
  @moduledoc """
  Her work line rested by a stopped run (sunna#109): the activity the
  stop ended, its task, who stopped it (the witness's Stop, or her safe
  word: said here, on his bell, never on the house's record of the
  activity), and the conversation the run ran in. It stands until one of
  them resumes the line.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Sunna

  @doc "The entry kind."
  @spec kind() :: String.t()
  def kind, do: "work_stopped"

  @impl true
  def stages, do: [%{kind: kind(), screen: "queue"}]

  @impl true
  def entries(resident_id) do
    case Sunna.work_stopped(resident_id) do
      %{} = s ->
        [
          %Entry{
            kind: kind(),
            ref: s.act || "line",
            since: s.at,
            screen: "queue",
            about: %{
              task: s.task,
              household: s.household,
              act: s.act,
              session_key: s.session_key,
              by: s.by,
              words: words(s.by)
            }
          }
        ]

      nil ->
        []
    end
  end

  defp words("witness"), do: "Her work line rests: you stopped its run"
  defp words("safe_word"), do: "Her work line rests: she stopped its run with her safe word"
  defp words(_unknown), do: "Her work line rests after a stopped run"
end

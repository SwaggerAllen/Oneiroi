defmodule Oneiroi.Seshat.Household.Records do
  @moduledoc """
  Files the platform renders into the household repository from rows
  (spec §6.10, repo first): the house queue's task index documents under
  `tasks/` (sunna#80, lily:design/queue-ia §4) and the cutover's record
  of the old queue under `records/` (§6.2). Only those two folders; a
  file whose words are unchanged is not written again, so a render that
  changes nothing makes no commit.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files

  @folders ["records/", "tasks/"]

  @doc false
  # `files`: `[{path, text}]`. Answers the commit, or `:nothing`.
  def write(household_id, files, message, %Actor{} = actor) do
    if Enum.all?(files, fn {path, text} -> allowed?(path) and is_binary(text) end) do
      with {:ok, _view} <- Core.provision(household_id) do
        Files.locked(household_id, &commit_changed(&1, household_id, files, message, actor))
      end
    else
      {:error, Error.new(:seshat_household_invalid, :seshat_household_records_path)}
    end
  end

  defp commit_changed(view, household_id, files, message, actor) do
    changes =
      for {path, text} <- files,
          Files.file(view, path) != text,
          do: {:put, path, text, Map.get(view.files, path)}

    case changes do
      [] -> {:ok, :nothing}
      changes -> Files.commit(view, changes, message, Core.author(household_id, actor))
    end
  end

  defp allowed?(path),
    do:
      is_binary(path) and Enum.any?(@folders, &String.starts_with?(path, &1)) and
        not String.contains?(path, "..") and String.ends_with?(path, [".md", ".json"])
end

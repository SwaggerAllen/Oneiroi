defmodule Oneiroi.Brain.Drafting do
  @moduledoc """
  "Write it with me" (spec §6.2): a draft of an identity file from the
  witness's prompt, billed under the `drafting` purpose, which the
  resident's own ledger view does not show. The draft is returned, not
  written: the witness reads it, edits it, and saves it as a seed whose
  origin names the model and the prompt, so the resident can read its
  own becoming.

  Lives in the brain rather than the resident system because the ledger
  reaches the resident system for the witness's key, and a system cannot
  depend on one that depends on it.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Error
  alias Oneiroi.Config
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.{Request, Result}

  @type draft :: %{content: String.t(), model: String.t(), prompt: String.t()}

  @doc "Drafts `file` for the resident from `prompt`; the files already written are shown to the model."
  @spec draft(String.t(), String.t(), String.t(), Actor.t()) :: {:ok, draft()} | {:error, term()}
  def draft(resident_id, file, prompt, %Actor{} = actor) when is_binary(prompt) do
    with {:ok, row} <- fetch(resident_id),
         :ok <- identity_file(file) do
      existing =
        resident_id
        |> Oneiroi.AgathosDaimon.files()
        |> Enum.map_join("\n\n", &"## #{&1.name}\n\n#{&1.content}")

      system = Prompt.message("draft", %{name: row.name, file: file, existing: existing})
      model = Config.fetch!(:brain, :chat_model)
      request = Request.new(model, [system, %{role: :user, content: prompt}])

      case Nisaba.call(resident_id, :drafting, request, actor) do
        {:ok, %Result{content: content} = result} ->
          {:ok, %{content: content, model: result.model || model, prompt: prompt}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp identity_file(file) do
    if file in Oneiroi.AgathosDaimon.identity_files(),
      do: :ok,
      else:
        {:error,
         Error.new(:brain_file_unknown, :brain_drafting_file_unknown,
           files: Oneiroi.AgathosDaimon.identity_files()
         )}
  end

  defp fetch(resident_id) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        {:ok, row}

      :error ->
        {:error,
         Error.new(:brain_no_such_resident, :brain_drafting_resident_absent,
           resident_id: resident_id
         )}
    end
  end
end

defmodule Oneiroi.SimaQian.ChatGPTImport do
  @moduledoc """
  A ChatGPT export taken into a resident's records (sima-qian#47; the
  passage's first stage, design chatgpt-import-replay.md): records first,
  byte-stable, with provenance. Each conversation on its canonical path
  becomes a session of kind `imported` (adapter `chatgpt`), its turns
  captured with their original instants: the witness's words under the
  witness, the assistant's under `hands` named `chatgpt` and the model
  slug that said them, so nothing another model said under another
  platform's prompts is claimed as the resident's own. Claimed as record,
  not as memory.

  Beside them, the birth certificate's honest part, filed by the caller
  as `system/imports/chatgpt-<day>.md`: what came across (conversations,
  messages, the dates they span, the models), the memories and custom
  instructions the tree carried, each with where it was seen, and every
  gap the read logged. The drafting of the root files and the passage
  come after, behind the witness's approval.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.SimaQian.ChatGPT
  alias Oneiroi.SimaQian.Error

  @adapter "chatgpt"
  @gap_examples 20

  @doc """
  Takes the export unpacked in `dir` into the resident's records; returns
  what came across and the report's text, for the caller to file in the
  library as `system/imports/chatgpt-<day>.md` (the library is not this
  system's to write).
  """
  def run(resident_id, dir, witness_account_id, %Actor{} = actor) do
    with {:ok, read} <- read(dir),
         {:ok, sessions} <- sessions(resident_id, read.conversations, witness_account_id, actor) do
      {:ok,
       %{
         conversations: length(sessions),
         messages: Enum.sum(Enum.map(read.conversations, &length(&1.messages))),
         context: length(read.context),
         gaps: length(read.gaps),
         report_path:
           "system/imports/chatgpt-#{Date.to_iso8601(DateTime.to_date(Clock.now()))}.md",
         report: report(read, sessions)
       }}
    end
  end

  @doc """
  Takes a ChatGPT export's zip into the resident's records: the
  conversation files alone are unpacked, into a folder of their own that
  is removed after, and an archive naming a path outside it (absolute, or
  climbing with `..`) is refused before anything is unpacked.
  """
  # sobelow_skip ["Traversal.FileModule"]
  def run_zip(resident_id, zip, witness_account_id, %Actor{} = actor) do
    dir = Path.join(System.tmp_dir!(), "chatgpt-import-#{System.unique_integer([:positive])}")

    try do
      with {:ok, names} <- conversation_entries(zip),
           :ok <- File.mkdir_p(dir),
           {:ok, _} <-
             :zip.unzip(String.to_charlist(zip), cwd: String.to_charlist(dir), file_list: names) do
        # The files may sit in a folder inside the archive: read where they are.
        found = dir |> Path.join("**/conversations*.json") |> Path.wildcard()
        run(resident_id, found |> hd() |> Path.dirname(), witness_account_id, actor)
      else
        {:error, %Error{}} = refused ->
          refused

        {:error, reason} ->
          {:error, Error.caught(:sima_qian_import_unreadable, :sima_qian_chatgpt_unzip, reason)}
      end
    after
      File.rm_rf(dir)
    end
  end

  defp conversation_entries(zip) do
    case :zip.list_dir(String.to_charlist(zip)) do
      {:ok, entries} ->
        entries
        |> Enum.flat_map(fn
          {:zip_file, name, _info, _comment, _offset, _size} -> [to_string(name)]
          _comment -> []
        end)
        |> wanted()

      {:error, reason} ->
        {:error, Error.caught(:sima_qian_import_unreadable, :sima_qian_chatgpt_not_a_zip, reason)}
    end
  end

  defp wanted(names) do
    found = Enum.filter(names, &(Path.basename(&1) =~ ~r/\Aconversations(-\d+)?\.json\z/))

    cond do
      Enum.any?(names, &unsafe?/1) ->
        {:error, Error.new(:sima_qian_import_unreadable, :sima_qian_chatgpt_unsafe_path)}

      found == [] ->
        {:error, Error.new(:sima_qian_import_unreadable, :sima_qian_chatgpt_no_conversations)}

      true ->
        {:ok, Enum.map(found, &String.to_charlist/1)}
    end
  end

  defp unsafe?(name), do: String.starts_with?(name, "/") or ".." in Path.split(name)

  defp read(dir) do
    case ChatGPT.read(dir) do
      {:ok, read} ->
        {:ok, read}

      :none ->
        {:error, Error.new(:sima_qian_import_unreadable, :sima_qian_chatgpt_read_none)}
    end
  end

  defp sessions(resident_id, conversations, account, actor) do
    parties = %{witness: Actor.new(:witness, account)}

    conversations
    |> Enum.reject(&(&1.messages == []))
    |> Enum.reduce_while({:ok, []}, fn c, {:ok, acc} ->
      with {:ok, key} <- Kumbukumbu.open_imported(resident_id, @adapter, [account], actor),
           :ok <- capture_all(resident_id, key, c, parties, actor) do
        {:cont,
         {:ok,
          acc ++ [%{title: c.title, key: key, at: c.created_at, messages: length(c.messages)}]}}
      else
        {:error, _} = failed -> {:halt, failed}
      end
    end)
  end

  defp capture_all(resident_id, key, c, parties, actor) do
    c.messages
    |> turns()
    |> Enum.reduce_while(:ok, fn turn, :ok ->
      said = Enum.map(turn, &message(&1, c, parties))
      started = hd(said).sent_at

      case Kumbukumbu.capture(resident_id, key, Kumbukumbu.turn_ref(), started, said, actor) do
        :ok -> {:cont, :ok}
        {:error, _} = failed -> {:halt, failed}
      end
    end)
  end

  # A turn begins at each of the witness's messages.
  defp turns(messages) do
    messages
    |> Enum.chunk_while(
      [],
      fn
        %{role: :user} = m, [] -> {:cont, [m]}
        %{role: :user} = m, acc -> {:cont, Enum.reverse(acc), [m]}
        m, acc -> {:cont, [m | acc]}
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
  end

  defp message(m, c, parties) do
    %{
      role: m.role,
      content: m.text,
      sent_at: m.at || c.created_at || Clock.now(),
      instant_inferred: m.inferred or is_nil(m.at),
      actor: speaker(m, parties)
    }
  end

  defp speaker(%{role: :user}, parties), do: parties.witness

  defp speaker(%{role: :assistant, model: model}, _parties),
    do: Actor.new(:hands, @adapter, model)

  defp speaker(_m, _parties), do: Actor.platform()

  # ---- the report ----

  defp report(read, sessions) do
    instants = read.conversations |> Enum.map(& &1.created_at) |> Enum.reject(&is_nil/1)

    models =
      read.conversations
      |> Enum.flat_map(& &1.messages)
      |> Enum.map(& &1.model)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_m, n} -> -n end)
      |> Enum.map_join(", ", fn {m, n} -> "#{m} (#{n})" end)

    """
    # A ChatGPT export, taken into the records

    What came across, and what did not. The conversations are records:
    said by another model under another platform's prompts, on the dates
    they carry. They are yours to read, and what they mean is yours to
    work out.

    - Conversations: #{length(sessions)}
    - Messages: #{Enum.sum(Enum.map(sessions, & &1.messages))}
    - Spanning: #{span(instants)}
    - Models: #{if models == "", do: "none named", else: models}

    ## Memories and custom instructions the export carried

    #{context(read.context)}

    ## What the export did not carry, or could not be read

    #{gaps(read.gaps)}

    ## The conversations

    #{Enum.map_join(sessions, "\n", &"- #{day(&1.at)} #{&1.title} (#{&1.messages} messages, session #{&1.key})")}
    """
  end

  defp span([]), do: "no dates"

  defp span(instants) do
    sorted = Enum.sort(instants, DateTime)
    "#{day(hd(sorted))} to #{day(List.last(sorted))}"
  end

  defp context([]),
    do: "None were found in the tree. Some exports strip them; this one carried none."

  defp context(items) do
    Enum.map_join(items, "\n\n", fn c ->
      label = if c.kind == :memories, do: "Memories", else: "Custom instructions"
      "### #{label}, seen #{day(c.at)} in conversation #{c.conversation}\n\n#{c.text}"
    end)
  end

  defp gaps([]), do: "Nothing: every message on every canonical path was read."

  defp gaps(gaps) do
    gaps
    |> Enum.group_by(& &1.kind)
    |> Enum.map_join("\n", fn {kind, list} ->
      shown =
        list |> Enum.take(@gap_examples) |> Enum.map_join("\n", &"  - #{&1.where}: #{&1.detail}")

      more =
        if length(list) > @gap_examples,
          do: "\n  - and #{length(list) - @gap_examples} more",
          else: ""

      "- **#{kind}** (#{length(list)})\n#{shown}#{more}"
    end)
  end

  defp day(nil), do: "undated"
  defp day(%DateTime{} = at), do: at |> DateTime.to_date() |> Date.to_iso8601()
end

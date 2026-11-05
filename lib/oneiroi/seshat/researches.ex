defmodule Oneiroi.Seshat.Researches do
  @moduledoc """
  Research (seshat#38, spec F24): a named question for the reader's
  research pass, the pages to start from, and its notes when they land.
  The pass itself is the reader's, on the witness's machine (xenia#15,
  #16); this is the library's half: the stream, the documents, and the
  letter to the conversation that asked.

  An answer is written under `research/<number>-<slug>/`, the research
  kind's layout: `task.md` with the question, who asked, the summary and
  the sources, and one note per page read, each saying where it came
  from. The notes are the reader's words about other people's pages, so
  they are written by the platform on the resident's behalf (`core`), as
  the oracle's are, and the actor says who wrote them.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Router
  alias Oneiroi.Seshat.Store

  # Notes past these are cut: a pass that read more has said enough.
  @max_sources 20
  @note_chars 20_000

  @doc "Asks the reader's research pass a named question, with the pages to start from; its number."
  def ask(resident_id, session_key, question, urls, %Actor{} = actor) do
    command = %Commands.AskResearch{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      question: question,
      urls: urls |> List.wrap() |> Enum.map(&to_string/1),
      session_key: session_key
    }

    with {:ok, [event]} <- dispatch(command), do: {:ok, event.number}
  end

  @doc """
  Writes the notes for question `number` (`%{summary, sources: [%{url,
  title, notes}]}`) under research/, records it answered, and tells the
  conversation that asked; the folder's path.
  """
  def answer(resident_id, number, %{} = found, %Actor{} = actor) do
    with %Store.Research{status: "open"} = row <- research(resident_id, number) || absent(number),
         dir = "research/#{number}-#{slug(row.question)}",
         sources = found |> field(:sources) |> List.wrap() |> Enum.take(@max_sources),
         {:ok, notes} <- write_notes(resident_id, dir, sources, actor),
         {:ok, _} <-
           Documents.write(resident_id, dir <> "/task.md", task(row, found, notes), actor,
             core: true
           ),
         {:ok, _events} <-
           dispatch(%Commands.AnswerResearch{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             number: number,
             path: dir,
             sources: Enum.map(notes, & &1.url)
           }) do
      tell(resident_id, row, "answered: #{dir}/task.md, #{length(notes)} source(s) read.")
      {:ok, dir}
    else
      %Store.Research{} -> {:error, settled(number)}
      other -> other
    end
  end

  @doc "Records question `number` as failed, with the reason in words, and tells the conversation that asked."
  def fail(resident_id, number, reason, %Actor{} = actor) do
    command = %Commands.FailResearch{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      reason: to_string(reason || "")
    }

    with {:ok, events} <- dispatch(command) do
      if events != [],
        do:
          resident_id
          |> research(number)
          |> then(&tell(resident_id, &1, "could not be done: #{reason}"))

      :ok
    end
  end

  @doc "The research questions, newest first; `status:` narrows."
  def researches(resident_id, opts \\ []),
    do: Scope.resident(resident_id, fn -> Store.researches(opts) end)

  @doc "One research question by number, or nil."
  def research(resident_id, number),
    do: Scope.resident(resident_id, fn -> Store.research(number) end)

  defp write_notes(resident_id, dir, sources, actor) do
    sources
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {source, i}, {:ok, acc} ->
      url = to_string(field(source, :url) || "")
      title = to_string(field(source, :title) || url)
      notes = source |> field(:notes) |> to_string() |> String.slice(0, @note_chars)
      path = "#{dir}/#{i}-#{slug(title)}.md"
      content = "# #{title}\n\nSource: #{url}\n\n#{notes}\n"

      case Documents.write(resident_id, path, content, actor, core: true) do
        {:ok, _} -> {:cont, {:ok, acc ++ [%{url: url, title: title, path: path}]}}
        {:error, _} = failed -> {:halt, failed}
      end
    end)
  end

  defp task(row, found, notes) do
    listed =
      Enum.map_join(notes, "\n", fn n -> "- [#{n.title}](#{n.url}): #{Path.basename(n.path)}" end)

    started = if row.urls == [], do: "nothing named", else: Enum.join(row.urls, ", ")

    """
    # #{row.question}

    Research ##{row.number}, asked by #{row.asked_by} on #{Local.day(Local.zone(row.resident_id), row.asked_at)}; started from #{started}. Read by the reader on the witness's machine, within the research allowlist.

    #{found |> field(:summary) |> to_string() |> String.trim()}

    ## Sources

    #{if listed == "", do: "None read.", else: listed}
    """
  end

  # The asking conversation is told by a house letter, as the oracle's is;
  # a question nobody asked from a conversation tells nobody.
  defp tell(_resident_id, %{session_key: nil}, _what), do: :ok
  defp tell(_resident_id, nil, _what), do: :ok

  defp tell(resident_id, row, what) do
    _ =
      Kumbukumbu.letter_to_session(
        resident_id,
        row.session_key,
        "The reader, on research ##{row.number} (#{row.question}): #{what}",
        Actor.platform()
      )

    :ok
  end

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp field(_other, _key), do: nil

  defp absent(number),
    do:
      {:error,
       Error.new(:seshat_no_such_research, :seshat_researches_answer_absent, number: number)}

  defp settled(number),
    do: Error.new(:seshat_research_settled, :seshat_researches_answer_settled, number: number)

  # A filename from the first words: lower case, letters and digits
  # joined by `-`, at most six words.
  defp slug(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.split()
    |> Enum.take(6)
    |> Enum.join("-")
    |> case do
      "" -> "research"
      slug -> slug
    end
  end

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error,
         Error.caught(:seshat_dispatch_failed, :seshat_researches_dispatch_failed, reason)}
    end
  end
end

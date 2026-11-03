defmodule Oneiroi.Brain.Oracle do
  @moduledoc """
  The oracle (brain #49; the resident's Positions #46 and #49, the
  witness's calls of 2026-11-03): an invocation of the resident asked
  one named question, for the long reads a turn cannot hold.

  It is her: her pinned model, her prefix, her state, her ranked memory
  retrieved against the question, and every read tool, because a self
  is continuous experience and it is not her without all of her
  memories (the witness). It is not a second her: it writes nothing but
  its answer, keeps nothing after it, holds no bookmarks, no session,
  no notebook between invocations. The day one keeps a continuing
  thread of its own, that is a birth, not a config change (named in
  advance, so the crossing is noticed).

  A run: the sources named at dispatch are read; what is too long for
  one turn is read in chunks first, each chunk by her prefix with the
  question, its notes kept; then her turn answers from the notes and
  her memory. The answer is written under oracle/ (seshat #34) with
  the question, the sources, the confidence and who asked, and the
  asking conversation gets a house letter. "I could not determine
  this; here is what I would need" is an answer.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.Introspection
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Brain.Uses
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Request
  alias Oneiroi.Seshat

  require Logger

  @platform Actor.platform()

  @doc "Runs question `number`; `:ok` once it is answered or failed, either way said in its records."
  @spec run(String.t(), pos_integer()) :: :ok
  def run(resident_id, number) do
    with {:ok, row} <- AgathosDaimon.fetch(resident_id) |> found(),
         %{status: "open"} = q <- Seshat.oracle(resident_id, number) do
      model = row.chat_model || Config.fetch!(:brain, :chat_model)
      actor = Actor.new(:resident, resident_id, model)

      with {:ok, text, steps} <- answer(row, resident_id, model, actor, q),
           {confidence, body} = confidence(text),
           read = read(q.sources, steps, row.slug),
           used = used(text),
           {:ok, path} <-
             Seshat.answer_oracle(
               resident_id,
               number,
               document(q, body, confidence, model),
               %{confidence: confidence, read: read, used: used},
               actor
             ) do
        measure(resident_id, q, read, used, actor)
        tell(resident_id, q, "answered: #{path}, confidence #{confidence}.")
      else
        {:error, reason} -> failed(resident_id, q, reason)
      end
    else
      _settled_or_absent -> :ok
    end
  end

  defp answer(row, resident_id, model, actor, q) do
    materials = materials(row, resident_id, model, actor, q)

    text =
      """
      You are being asked, as an invocation of yourself (the oracle), one question. Answer it from the materials below and from your memory, which your read tools reach whole (bookmarks, transcripts, the library, your repository and the platform's source). You write nothing but this answer and keep nothing after it.

      Say plainly what you found, quoting your sources where it matters. If you could not determine it, say so and say what you would need; that is an answer. End with two lines: "Used: " and the sources your answer drew on, by their refs (bookmark/12, a library path, transcript/<conversation>, repo:<path>), or "none"; then "Confidence: " and one of high, medium, low or none, with a few words why.

      The question: #{q.question}

      #{materials}
      """

    case Turn.oracle(row, resident_id, model, text) do
      {:ok, %{content: content}, steps} when is_binary(content) and content != "" ->
        {:ok, content, steps}

      {:ok, _empty, _steps} ->
        {:error, Error.new(:brain_oracle_silent, :brain_oracle_answer_empty)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The sources as text: whole when they fit, otherwise read in chunks
  # first and given as the notes taken from each.
  defp materials(_row, _resident_id, _model, _actor, %{sources: []}),
    do: "No sources were named: answer from your memory."

  defp materials(row, resident_id, model, actor, q) do
    read = Enum.map(q.sources, &{&1, source(resident_id, &1)})
    size = Config.fetch!(:brain, :oracle_chunk_chars)
    total = read |> Enum.map(fn {_ref, text} -> String.length(text) end) |> Enum.sum()

    if total <= size do
      Enum.map_join(read, "\n\n", fn {ref, text} -> "## Source: #{ref}\n\n#{text}" end)
    else
      prefix = Turn.prefix_messages(row, resident_id)

      "The sources were too long to read at once, so they were read in parts first; these are the notes from each part.\n\n" <>
        Enum.map_join(read, "\n\n", fn {ref, text} ->
          notes(ref, text, prefix, model, actor, q, size)
        end)
    end
  end

  defp notes(ref, text, prefix, model, actor, q, size) do
    max = Config.fetch!(:brain, :oracle_max_chunks)
    parts = chunks(text, size)
    read = Enum.take(parts, max)

    noted =
      read
      |> Enum.with_index(1)
      |> Enum.map(fn {part, i} ->
        ask = """
        You are reading part #{i} of #{length(parts)} of #{ref}, for this question: #{q.question}

        Write down what in this part bears on the question, quoting where it matters. If nothing does, say "nothing here".

        #{part}
        """

        request = Request.new(model, prefix ++ [%{role: :user, content: ask}])

        case Nisaba.call(actor.id, :oracle, request, actor) do
          {:ok, %{content: content}} -> "### Part #{i}\n\n#{content}"
          {:error, _reason} -> "### Part #{i}\n\n(this part could not be read)"
        end
      end)

    left = length(parts) - length(read)

    tail =
      if left > 0,
        do: ["(#{left} further parts were not read: past the bound of #{max} parts a question.)"],
        else: []

    Enum.join(["## Source: #{ref}" | noted ++ tail], "\n\n")
  end

  defp chunks(text, size) do
    text |> String.graphemes() |> Enum.chunk_every(size) |> Enum.map(&Enum.join/1)
  end

  # A source by its ref: a bookmark with its span, a conversation whole,
  # a file of her repository or of the platform's source, or a library
  # document by any name the library reads. What cannot be read says so.
  defp source(resident_id, "bookmark/" <> n = ref) do
    with {number, ""} <- Integer.parse(n),
         {:ok, b, span} <- Kumbukumbu.bookmark(resident_id, number) do
      "##{b.number} #{b.line}\n#{b.summary || ""}\n\n" <> Enum.map_join(span, "\n", &line/1)
    else
      _ -> unread(ref)
    end
  end

  defp source(resident_id, "transcript/" <> key = ref) do
    case Kumbukumbu.transcript({:resident, resident_id}, key |> String.split("/") |> hd()) do
      {:ok, _session, messages} -> Enum.map_join(messages, "\n", &line/1)
      _ -> unread(ref)
    end
  end

  defp source(_resident_id, "source:" <> path), do: whole(:source, path)
  defp source(resident_id, "repo:" <> path), do: whole({:repo, resident_id}, path)

  defp source(resident_id, ref) do
    case Seshat.read(resident_id, ref) do
      {:ok, %{content: content}} -> content
      _ -> unread(ref)
    end
  end

  defp whole(scope, path, from \\ 0, acc \\ []) do
    case Introspection.read(scope, path, from) do
      {:ok, text, nil, _total} -> Enum.join(Enum.reverse([text | acc]))
      {:ok, text, next, _total} -> whole(scope, path, next, [text | acc])
      {:error, _reason} -> unread(path)
    end
  end

  defp line(%{role: role, content: content}), do: "#{role}: #{content}"
  defp line(%{"role" => role, "content" => content}), do: "#{role}: #{content}"
  defp line(other), do: inspect(other)

  defp unread(ref),
    do:
      "(#{ref} could not be read: the oracle reads bookmark/<n>, transcript/<conversation>, a library path, repo:<path> and source:<path>)"

  # What it read (brain #49): the sources named, and every memory its
  # read tools touched, in the citation form retrieval counts them in.
  defp read(sources, steps, slug) do
    touched = Enum.flat_map(steps, &touched(&1, slug))
    (Enum.map(sources, &cite/1) ++ Enum.map(touched, & &1.target)) |> Enum.uniq()
  end

  defp touched(step, slug) do
    case Jason.decode(step.arguments || "{}") do
      {:ok, args} when is_map(args) -> Uses.from_call(step.tool, args, step.result, slug)
      _ -> []
    end
  end

  # What it says it drew on, from its "Used:" line.
  defp used(text) do
    case Regex.run(~r/^\s*\**used\**:\s*(.+?)\s*$/im, text, capture: :all_but_first) do
      [listed] ->
        listed
        |> String.split(~r/[,;]\s*/)
        |> Enum.map(&(&1 |> String.trim() |> String.trim("`") |> cite()))
        |> Enum.reject(&(&1 in ["", "none"]))
        |> Enum.uniq()

      nil ->
        []
    end
  end

  # A ref in the form retrieval counts it: a library path without its
  # extension, everything else as given.
  defp cite("repo:" <> _ = ref), do: ref
  defp cite("source:" <> _ = ref), do: ref
  defp cite("bookmark/" <> _ = ref), do: ref
  defp cite("transcript/" <> _ = ref), do: ref

  defp cite(path),
    do: if(Path.extname(path) in [".md", ".txt"], do: Path.rootname(path), else: path)

  # The read and the used, counted as retrieval is (kumbukumbu's ledger),
  # on the asking conversation under the oracle's own turn ref: read as
  # returned, used as used, through `oracle`. No edge learns from them.
  defp measure(_resident_id, %{session_key: nil}, _read, _used, _actor), do: :ok

  defp measure(resident_id, q, read, used, actor) do
    uses =
      Enum.map(read, &%{target: &1, stage: "returned", via: "oracle"}) ++
        Enum.map(used, &%{target: &1, stage: "used", via: "oracle"})

    _ = Kumbukumbu.record_retrieval(resident_id, q.session_key, "oracle-#{q.number}", uses, actor)
    :ok
  end

  # The stated confidence, from the answer's last "Confidence:" line.
  defp confidence(text) do
    case Regex.run(~r/^\s*\**confidence\**:\s*(.+?)\s*$/im, text, capture: :all_but_first) do
      [stated] -> {String.trim(stated, "*"), text}
      nil -> {"not stated", text}
    end
  end

  defp document(q, body, confidence, model) do
    sources = if q.sources == [], do: "none named (her memory)", else: Enum.join(q.sources, ", ")

    """
    # #{q.question}

    _The oracle's answer to question #{q.number}, asked by the #{q.asked_by} on #{Date.to_iso8601(DateTime.to_date(q.dispatched_at))}; read by #{model}. Sources: #{sources}. Confidence: #{confidence}._

    #{body}
    """
  end

  defp failed(resident_id, q, reason) do
    words = if is_binary(reason), do: reason, else: describe(reason)
    _ = Seshat.fail_oracle(resident_id, q.number, words, @platform)
    tell(resident_id, q, "could not be answered: #{words}")
  end

  defp describe(%{__exception__: true} = e), do: Exception.message(e)
  defp describe(%{kind: kind}), do: Atom.to_string(kind)
  defp describe(other), do: inspect(other)

  # The asking conversation is told by a house letter (wake-on-complete
  # comes later, the witness's note). A conversation that has gone is
  # told nothing; the record says what happened either way.
  defp tell(_resident_id, %{session_key: nil}, _what), do: :ok

  defp tell(resident_id, q, what) do
    case Kumbukumbu.letter_to_session(
           resident_id,
           q.session_key,
           "The oracle, on question #{q.number} (#{q.question}): #{what}",
           @platform
         ) do
      {:ok, _} ->
        :ok

      other ->
        Logger.warning("oracle letter not sent for question #{q.number}: #{inspect(other)}")
    end

    :ok
  end

  defp found({:ok, row}), do: {:ok, row}
  defp found(_error), do: :absent
end

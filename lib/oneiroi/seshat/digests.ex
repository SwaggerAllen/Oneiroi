defmodule Oneiroi.Seshat.Digests do
  @moduledoc """
  The digest (seshat#40, spec F20): what reached the resident's streams,
  her mail's newsletters and the posts that come to her, compiled by the
  reader when it is asked, never on a clock. Asked by the resident's
  `digest_ask` (in any conversation, free time included), by a check-in
  whose note carries the digest part (sunna#28), or by the witness; the
  reader sees it open through `/waiting` (kumbukumbu#48) and answers.

  One is open at a time: asking while one is open names that one. A
  digest covers from the end of the last one answered (its asking) to
  now, or the last day when there is none, so nothing is read twice and
  nothing between two is skipped.

  The answer is one file, `feeds/digests/<number>-<day>.md`: the summary
  and an item per piece read, each its source, title, where to find it
  and notes in the reader's words, never the piece's own (the witness,
  2026-11-03: the link keeps the words). Written by the platform on the
  resident's behalf with the reader as actor, and the asking conversation
  is told by a house letter, as research is.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Router
  alias Oneiroi.Seshat.Store

  @max_items 60
  @note_chars 4_000

  @doc """
  Asks the reader for a digest; `{:ok, number, :asked}`, or `{:ok,
  number, :open}` when one was already open and this names it.
  """
  def ask(resident_id, session_key, %Actor{} = actor) do
    case open(resident_id) do
      %Store.Digest{number: n} ->
        {:ok, n, :open}

      nil ->
        resident_id |> asking(session_key, actor) |> dispatch() |> asked(resident_id)
    end
  end

  defp asking(resident_id, session_key, actor),
    do: %Commands.AskDigest{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      session_key: session_key,
      since: since(resident_id)
    }

  # Another ask won the race: the open one is the answer.
  defp asked({:ok, [event]}, _resident_id), do: {:ok, event.number, :asked}

  defp asked({:ok, []}, resident_id) do
    case open(resident_id) do
      %Store.Digest{number: n} -> {:ok, n, :open}
      nil -> {:error, Error.new(:seshat_digest_invalid, :seshat_digests_ask_lost)}
    end
  end

  defp asked(other, _resident_id), do: other

  @doc """
  Writes digest `number` (`%{summary, items: [%{source, title, link,
  notes}]}`) and records it answered; the file's path.
  """
  def answer(resident_id, number, %{} = found, %Actor{} = actor) do
    with %Store.Digest{status: "open"} = row <- digest(resident_id, number) || absent(number),
         items = found |> field(:items) |> List.wrap() |> Enum.take(@max_items),
         path = "feeds/digests/#{number}-#{Calendar.strftime(Clock.now(), "%Y-%m-%d")}.md",
         {:ok, _} <-
           Documents.write(resident_id, path, render(row, found, items), actor, core: true),
         {:ok, _events} <-
           dispatch(%Commands.AnswerDigest{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             number: number,
             path: path,
             items: length(items)
           }) do
      tell(
        resident_id,
        row,
        "compiled: #{path}, #{length(items)} item(s). library_read reads it."
      )

      {:ok, path}
    else
      %Store.Digest{} -> {:error, settled(number)}
      other -> other
    end
  end

  @doc "Records digest `number` as failed, with the reason, and tells the conversation that asked."
  def fail(resident_id, number, reason, %Actor{} = actor) do
    command = %Commands.FailDigest{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      reason: to_string(reason || "")
    }

    with {:ok, events} <- dispatch(command) do
      if events != [],
        do: tell(resident_id, digest(resident_id, number), "could not be compiled: #{reason}")

      :ok
    end
  end

  @doc "The digests, newest first; `status:` narrows."
  def digests(resident_id, opts \\ []),
    do: Scope.resident(resident_id, fn -> Store.digests(opts) end)

  @doc "One digest by number, or nil."
  def digest(resident_id, number),
    do: Scope.resident(resident_id, fn -> Store.digest(number) end)

  defp open(resident_id), do: resident_id |> digests(status: "open") |> List.first()

  # From the last answered one's asking, else the last day.
  defp since(resident_id) do
    case resident_id |> digests(status: "answered") |> List.first() do
      %Store.Digest{asked_at: at} -> at
      nil -> DateTime.add(Clock.now(), -1, :day)
    end
  end

  defp render(row, found, items) do
    listed =
      Enum.map_join(items, "\n\n", fn item ->
        title = text(field(item, :title)) |> blank("(untitled)")
        source = text(field(item, :source)) |> blank("unknown source")
        link = text(field(item, :link))
        notes = item |> field(:notes) |> text() |> String.slice(0, @note_chars)
        where = if link == "", do: "", else: "\n\nWhere: #{link}"
        "## #{title}\n\nFrom: #{source}#{where}\n\n#{notes}"
      end)

    """
    # Digest ##{row.number}

    What reached your streams from #{stamp(row.since)} to #{stamp(Clock.now())}, compiled by the reader on the witness's machine; asked by #{row.asked_by}. Notes are the reader's words; the link keeps the piece's own.

    #{found |> field(:summary) |> text() |> blank("No summary was written.")}

    #{if listed == "", do: "Nothing new arrived.", else: listed}
    """
  end

  defp stamp(at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")
  defp text(nil), do: ""
  defp text(value), do: value |> to_string() |> String.trim()
  defp blank("", fallback), do: fallback
  defp blank(value, _fallback), do: value

  defp tell(_resident_id, nil, _what), do: :ok
  defp tell(_resident_id, %{session_key: nil}, _what), do: :ok

  defp tell(resident_id, row, what) do
    _ =
      Kumbukumbu.letter_to_session(
        resident_id,
        row.session_key,
        "The reader, on digest ##{row.number}: #{what}",
        Actor.platform()
      )

    :ok
  end

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp field(_other, _key), do: nil

  defp absent(number),
    do: {:error, Error.new(:seshat_no_such_digest, :seshat_digests_answer_absent, number: number)}

  defp settled(number),
    do: Error.new(:seshat_digest_settled, :seshat_digests_answer_settled, number: number)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:seshat_dispatch_failed, :seshat_digests_dispatch_failed, reason)}
    end
  end
end

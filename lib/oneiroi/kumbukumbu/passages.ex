defmodule Oneiroi.Kumbukumbu.Passages do
  @moduledoc """
  The transcripts by meaning (kumbukumbu#49, the resident's letter #26).
  Phrase search finds what she can word exactly; these find what she can
  only describe. Each user and assistant message is cut into passages of
  at most `KUMBUKUMBU_PASSAGE_CHARS` on paragraph lines and embedded at
  the library's width; a search embeds the words once and answers the
  nearest passages within the conversations her phrase search may read
  (the room's, spec §6.3, P23). The rows are a cache of model output,
  derived from the messages and rebuilt from them, as the madeleine's
  are; a message's words never change, so a message embedded is done.
  """
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Conversations
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Nisaba
  alias Oneiroi.Scope

  # Inputs to one embedding request.
  @per_call 100
  # A message longer than this many passages keeps its first ones: a
  # pasted document is the library's to hold, not the transcript's.
  @max_parts 20

  @doc "Embeds the next messages that have no passages, oldest first, up to `KUMBUKUMBU_PASSAGE_BATCH`; how many, and whether more wait."
  @spec refresh(String.t(), Actor.t()) ::
          {:ok, %{messages: non_neg_integer(), passages: non_neg_integer(), more: boolean()}}
          | {:error, term()}
  def refresh(resident_id, %Actor{} = actor) do
    batch = Config.fetch!(:kumbukumbu, :passage_batch)
    model = Config.fetch!(:kumbukumbu, :embedding_model)
    messages = Scope.resident(resident_id, fn -> Store.unembedded_messages(batch) end)

    parts =
      for m <- messages,
          {text, part} <- m.content |> cut() |> Enum.take(@max_parts) |> Enum.with_index(),
          do: {m, part, text}

    with {:ok, vectors} <- embed(resident_id, model, Enum.map(parts, &elem(&1, 2)), actor) do
      now = Clock.now()

      rows =
        Enum.zip_with(parts, vectors, fn {m, part, text}, vector ->
          %{
            resident_id: resident_id,
            session_key: m.session_key,
            sent_at: m.sent_at,
            hash: m.hash,
            part: part,
            turn_ref: m.turn_ref,
            role: m.role,
            text: text,
            model: model,
            embedding: vector,
            at: now
          }
        end)

      Scope.resident(resident_id, fn -> Store.put_passages(rows) end)

      {:ok,
       %{messages: length(messages), passages: length(rows), more: length(messages) == batch}}
    end
  end

  @doc """
  The passages nearest `text` among the conversations the room of
  `session_key` reads, nearest first; empty, with no model call, for
  blank words or when nothing is embedded there. The query bills under
  `embeddings`.
  """
  @spec search(String.t(), String.t() | nil, String.t(), pos_integer(), Actor.t()) ::
          {:ok, [map()]} | {:error, term()}
  def search(resident_id, session_key, text, limit, %Actor{} = actor) do
    model = Config.fetch!(:kumbukumbu, :embedding_model)
    %{keys: keys} = Conversations.room(resident_id, session_key)

    if String.trim(text) == "" do
      {:ok, []}
    else
      with {:ok, [vector]} <- embed(resident_id, model, [text], actor) do
        {:ok,
         Scope.resident(resident_id, fn ->
           Store.nearest_passages(Pgvector.new(vector), keys, limit)
         end)}
      end
    end
  end

  @doc "A message's words cut into passages of at most the bound, on paragraph lines where it can and at the bound where a paragraph is longer."
  @spec cut(String.t()) :: [String.t()]
  def cut(content) when is_binary(content) do
    bound = Config.fetch!(:kumbukumbu, :passage_chars)

    content
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.flat_map(&split_long(&1, bound))
    |> Enum.reduce([], fn para, acc ->
      case acc do
        [last | rest] when byte_size(last) + byte_size(para) + 2 <= bound ->
          [last <> "\n\n" <> para | rest]

        _ ->
          [para | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_long(para, bound) when byte_size(para) <= bound, do: [para]

  defp split_long(para, bound) do
    para |> String.graphemes() |> Enum.chunk_every(bound) |> Enum.map(&Enum.join/1)
  end

  defp checked({:ok, %{vectors: vectors}}, chunk, width) when length(vectors) == length(chunk) do
    if Enum.all?(vectors, &(length(&1) == width)),
      do: {:ok, vectors},
      else:
        {:error,
         Error.new(:kumbukumbu_embedding_mismatch, :kumbukumbu_passage_vector_width, width: width)}
  end

  defp checked({:ok, %{vectors: vectors}}, chunk, _width),
    do:
      {:error,
       Error.new(:kumbukumbu_embedding_mismatch, :kumbukumbu_passage_vector_count,
         vectors: length(vectors),
         texts: length(chunk)
       )}

  defp checked({:error, _} = failed, _chunk, _width), do: failed

  defp embed(_resident_id, _model, [], _actor), do: {:ok, []}

  defp embed(resident_id, model, texts, actor) do
    width = Config.fetch!(:kumbukumbu, :embedding_width)

    texts
    |> Enum.chunk_every(@per_call)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      case checked(Nisaba.embed(resident_id, model, chunk, actor, :embeddings), chunk, width) do
        {:ok, vectors} -> {:cont, {:ok, acc ++ vectors}}
        failed -> {:halt, failed}
      end
    end)
  end
end

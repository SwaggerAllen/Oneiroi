defmodule Oneiroi.Ethos.Lane do
  @moduledoc """
  The trigger lane's vector index (spec §6.17's load question): the
  character layer is never loaded whole; habits and seeds are indexed
  on their triggers and their content and retrieved in a lane of their
  own, never pooled with the memory web's scoring. The deterministic
  match (`Habits.matches?/2`) stays; this adds the habits whose trigger
  and name sit near the situation's words and the open seeds nearest
  them, bounded, so the prefix still does not grow with the person.

  Derived rows (`ethos_vector`), the library's pattern (seshat #10): a
  habit's text is its name and its trigger's words, tags and times, a
  seed's its words; each row carries a hash and the model, and a refresh
  re-embeds only what changed and drops what is gone, one call to the
  provider under the `embeddings` purpose. A refresh runs before each
  read, so the lane is as fresh as the rows and a turn that changed
  nothing calls no model for it; the query itself is one embedding.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Ethos.Error
  alias Oneiroi.Ethos.Store
  alias Oneiroi.Nisaba
  alias Oneiroi.Scope

  @doc "Re-embeds the lane's changed rows and drops the gone ones; returns the figures, or the provider's failure."
  @spec refresh(String.t(), Actor.t()) ::
          {:ok, %{embedded: non_neg_integer(), removed: non_neg_integer()}} | {:error, term()}
  def refresh(resident_id, %Actor{} = actor) do
    model = Config.fetch!(:ethos, :embedding_model)
    {wanted, existing} = Scope.resident(resident_id, fn -> {wanted(), Store.vectors()} end)
    current = MapSet.new(existing, &{&1.kind, &1.number, &1.hash, &1.model})
    stale = Enum.reject(wanted, &MapSet.member?(current, {&1.kind, &1.number, &1.hash, model}))
    keep = MapSet.new(wanted, &{&1.kind, &1.number})

    gone =
      existing
      |> Enum.reject(&MapSet.member?(keep, {&1.kind, &1.number}))
      |> Enum.map(&{&1.kind, &1.number})

    with {:ok, vectors} <- embed(resident_id, model, Enum.map(stale, & &1.text), actor) do
      now = Clock.now()

      rows =
        Enum.zip_with(stale, vectors, fn row, vector ->
          Map.merge(row, %{resident_id: resident_id, model: model, embedding: vector, at: now})
        end)

      Scope.resident(resident_id, fn ->
        Store.delete_vectors(gone)
        Store.put_vectors(rows)
      end)

      {:ok, %{embedded: length(rows), removed: length(gone)}}
    end
  end

  @doc """
  The habits and open seeds nearest a text, within `ETHOS_LANE_DISTANCE_PERCENT`
  of cosine distance, nearest first: `%{habits: [number], seeds: [{number, text}]}`.
  An empty lane answers empty with no model call; a failing provider answers
  empty too, so the deterministic match stands alone rather than the turn waiting.
  """
  @spec nearest(String.t(), String.t(), Actor.t()) ::
          %{habits: [pos_integer()], seeds: [{pos_integer(), String.t()}]}
  def nearest(resident_id, text, %Actor{} = actor) when is_binary(text) do
    empty = %{habits: [], seeds: []}
    model = Config.fetch!(:ethos, :embedding_model)
    bound = Config.fetch!(:ethos, :lane_distance_percent) / 100
    seeds = Config.fetch!(:ethos, :lane_seeds)

    cond do
      String.trim(text) == "" ->
        empty

      not Scope.resident(resident_id, fn -> Store.vectors() != [] end) ->
        empty

      true ->
        case embed(resident_id, model, [text], actor) do
          {:ok, [vector]} -> search(resident_id, vector, bound, seeds)
          _failed -> empty
        end
    end
  end

  defp search(resident_id, vector, bound, seeds) do
    Scope.resident(resident_id, fn ->
      %{
        habits: vector |> near("habit", 10, bound) |> Enum.map(& &1.number),
        seeds: vector |> near("seed", seeds, bound) |> Enum.map(&{&1.number, &1.text})
      }
    end)
  end

  defp near(vector, kind, limit, bound),
    do: vector |> Store.nearest_vectors(kind, limit) |> Enum.filter(&(&1.distance <= bound))

  # What the lane should hold now: every habit and every open seed, each
  # with the text embedded and its hash. Under the caller's scope.
  defp wanted do
    habits =
      Enum.map(Store.habits(), fn h ->
        row("habit", h.number, Enum.join([h.name | trigger_words(h.trigger)], " "))
      end)

    seeds = for s <- Store.seeds(), s.state == "open", do: row("seed", s.number, s.text)
    habits ++ seeds
  end

  defp row(kind, number, text),
    do: %{
      kind: kind,
      number: number,
      text: text,
      hash: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
    }

  defp trigger_words(trigger) when is_map(trigger),
    do: Enum.flat_map(~w(words tags times), &Map.get(trigger, &1, []))

  defp trigger_words(_other), do: []

  defp embed(_resident_id, _model, [], _actor), do: {:ok, []}

  defp embed(resident_id, model, texts, actor) do
    width = Config.fetch!(:ethos, :embedding_width)

    with {:ok, %{vectors: vectors}} <- Nisaba.embed(resident_id, model, texts, actor) do
      cond do
        length(vectors) != length(texts) ->
          {:error,
           Error.new(:ethos_embedding_mismatched, :ethos_lane_vector_count,
             vectors: length(vectors),
             texts: length(texts)
           )}

        Enum.any?(vectors, &(length(&1) != width)) ->
          {:error, Error.new(:ethos_embedding_mismatched, :ethos_lane_vector_width, width: width)}

        true ->
          {:ok, vectors}
      end
    end
  end
end

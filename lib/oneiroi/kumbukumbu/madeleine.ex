defmodule Oneiroi.Kumbukumbu.Madeleine do
  @moduledoc """
  The madeleine layer (spec §6.3, P10, Muninn: "involuntary recall, the
  way a smell drags you into a room you haven't stood in for years"):
  gated, non-repeating associative recall, adjacent but unheard, chosen
  by an embedding index, excluded from limit-adjacent material, logged
  with its reason. One bookmark a turn at most, surfaced by nearness to
  the turn's words and never by rank, in a section of its own that the
  index's scoring never sees.

  The gates, each a reason the row can say: the bookmark sits within
  `KUMBUKUMBU_MADELEINE_DISTANCE_PERCENT` of cosine distance from the
  words; it was not in the index for `KUMBUKUMBU_MADELEINE_UNHEARD_DAYS`
  (unheard); it was not recalled for `KUMBUKUMBU_MADELEINE_REPEAT_DAYS`
  (non-repeating, the injection's own log through `last_recalled_at`);
  it is not pinned (the pins are in the index already); and it is not
  within the same distance of the limits, the dyad contract's text, which
  the prefix holds and serendipity leaves alone (P2). The rows are a
  cache of model output, the character layer's lane pattern (ethos #16):
  refreshed before each read, embedding only what changed.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Nisaba
  alias Oneiroi.Scope

  @type recall :: %{bookmark: Store.Bookmark.t(), distance: float(), reason: String.t()}

  @doc "Re-embeds the changed bookmarks and the limits, drops the gone; the figures, or the provider's failure."
  @spec refresh(String.t(), Actor.t()) ::
          {:ok, %{embedded: non_neg_integer(), removed: non_neg_integer()}} | {:error, term()}
  def refresh(resident_id, %Actor{} = actor) do
    model = Config.fetch!(:kumbukumbu, :embedding_model)
    limits = AgathosDaimon.contract_text(resident_id)
    {wanted, existing} = Scope.resident(resident_id, fn -> {wanted(limits), Store.vectors()} end)
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
  One bookmark adjacent to the words and unheard, with its reason, or
  nil: when the words are blank, the index is empty (no model call), the
  provider fails, or every near bookmark is gated out.
  """
  @spec recall(String.t(), String.t(), Actor.t(), [String.t()] | nil) :: recall() | nil
  def recall(resident_id, text, %Actor{} = actor, keys \\ nil) when is_binary(text) do
    model = Config.fetch!(:kumbukumbu, :embedding_model)

    cond do
      String.trim(text) == "" ->
        nil

      not Scope.resident(resident_id, fn ->
        Enum.any?(Store.vectors(), &(&1.kind == "bookmark"))
      end) ->
        nil

      true ->
        case embed(resident_id, model, [text], actor) do
          {:ok, [vector]} -> choose(resident_id, vector, keys)
          _failed -> nil
        end
    end
  end

  # `keys` is the room (spec §6.3, P23): a bookmark of a session outside
  # it is not adjacent to anything said here, whatever its distance.
  defp choose(resident_id, vector, keys) do
    bound = Config.fetch!(:kumbukumbu, :madeleine_distance_percent) / 100
    now = Clock.now()
    unheard = DateTime.add(now, -Config.fetch!(:kumbukumbu, :madeleine_unheard_days), :day)
    repeat = DateTime.add(now, -Config.fetch!(:kumbukumbu, :madeleine_repeat_days), :day)

    Scope.resident(resident_id, fn ->
      limits = Store.vector("limits", 0)

      rows =
        Store.bookmarks()
        |> Enum.filter(&(is_nil(keys) or &1.session_key in keys))
        |> Map.new(&{&1.number, &1})

      vector
      |> Store.nearest_vectors("bookmark", 10)
      |> Enum.filter(&(&1.distance <= bound))
      |> Enum.find_value(fn near ->
        gate(near, rows[near.number], limits, bound, unheard, repeat, now)
      end)
    end)
  end

  # Every gate, and the reason a chosen one can say for itself.
  defp gate(_near, nil, _limits, _bound, _unheard, _repeat, _now), do: nil

  defp gate(near, b, limits, bound, unheard, repeat, now) do
    to_limits = to_limits(near, limits)

    cond do
      b.pinned_at ->
        nil

      before?(b.last_indexed_at, unheard) == false ->
        nil

      before?(b.last_recalled_at, repeat) == false ->
        nil

      to_limits && to_limits <= bound ->
        nil

      true ->
        %{bookmark: b, distance: round3(near.distance), reason: reason(b, near, to_limits, now)}
    end
  end

  # Unstated limits are no words to be adjacent to: the contract section
  # is empty then and the brain never reads them either, so the gate is
  # void and the reason says so rather than measuring against nothing.
  defp to_limits(_near, nil), do: nil

  defp to_limits(near, limits),
    do: cosine_distance(Pgvector.to_list(near.embedding), Pgvector.to_list(limits.embedding))

  defp reason(b, near, to_limits, now) do
    "adjacent and unheard: ##{b.number} at #{round3(near.distance)} from this turn's words, " <>
      "#{ago(b.last_indexed_at, now, "in the index")}, #{ago(b.last_recalled_at, now, "recalled")}, " <>
      "#{if to_limits, do: "#{round3(to_limits)} from the limits", else: "no limits stated"}, not pinned"
  end

  defp ago(nil, _now, what), do: "never #{what}"
  defp ago(at, now, what), do: "last #{what} #{DateTime.diff(now, at, :day)} days ago"

  # nil (never) is before any instant.
  defp before?(nil, _instant), do: true
  defp before?(at, instant), do: DateTime.compare(at, instant) == :lt

  @doc "The cosine distance between two vectors as lists; 1.0 when either is all zeros."
  @spec cosine_distance([number()], [number()]) :: float()
  def cosine_distance(a, b) do
    dot = a |> Enum.zip(b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()

    norm =
      :math.sqrt(Enum.sum(Enum.map(a, &(&1 * &1)))) *
        :math.sqrt(Enum.sum(Enum.map(b, &(&1 * &1))))

    if norm == 0, do: 1.0, else: 1 - dot / norm
  end

  # What the index should hold: every bookmark's words, and the limits as
  # kind "limits", number 0; nothing at all while there is no bookmark,
  # so a resident with none pays for no embedding on any turn. Under
  # the caller's scope.
  defp wanted(limits) do
    case Enum.map(Store.bookmarks(), &row("bookmark", &1.number, words(&1))) do
      [] -> []
      bookmarks when limits in [nil, ""] -> bookmarks
      bookmarks -> [row("limits", 0, limits) | bookmarks]
    end
  end

  defp words(b), do: Enum.join(Enum.reject([b.line, b.summary], &(&1 in [nil, ""])), " ")

  defp row(kind, number, text),
    do: %{
      kind: kind,
      number: number,
      text: text,
      hash: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
    }

  defp embed(_resident_id, _model, [], _actor), do: {:ok, []}

  defp embed(resident_id, model, texts, actor) do
    width = Config.fetch!(:kumbukumbu, :embedding_width)

    with {:ok, %{vectors: vectors}} <- Nisaba.embed(resident_id, model, texts, actor) do
      cond do
        length(vectors) != length(texts) ->
          {:error, "the provider answered #{length(vectors)} vectors for #{length(texts)} texts"}

        Enum.any?(vectors, &(length(&1) != width)) ->
          {:error, "the provider answered a vector of another width than #{width}"}

        true ->
          {:ok, vectors}
      end
    end
  end

  defp round3(x), do: Float.round(x / 1, 3)
end

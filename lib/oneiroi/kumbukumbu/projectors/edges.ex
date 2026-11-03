defmodule Oneiroi.Kumbukumbu.Projectors.Edges do
  @moduledoc """
  Folds what retrieval did into learned edges (kumbukumbu #46): rule 1
  as a turn's index is recorded (its seed and what it returned), rules 3
  and 4 once the turn's `memory_feedback` says what helped. A turn with
  no feedback learns rule 1 alone, so a forgotten call never demotes
  anything. Decay is computed from the events' own instants, so a
  rebuild reproduces every weight. The arithmetic is
  `Oneiroi.Kumbukumbu.Edges`'.
  """
  use Oneiroi.Projection, name: "kumbukumbu_edges"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Edges
  alias Oneiroi.Kumbukumbu.Events
  alias Oneiroi.Kumbukumbu.Store.{Bookmark, Edge, EdgeTurn}

  fold(%Events.RetrievalRecorded{} = e, _metadata, fn multi ->
    Multi.run(multi, :edges, fn repo, _changes -> {:ok, learn(repo, e)} end)
  end)

  defp learn(repo, e) do
    uses = Enum.map(e.uses, &normal/1)
    seeds = numbers(uses, &(&1.stage == "seed"))
    returned = numbers(uses, &(&1.stage == "returned"))
    # Rule 1 reads the ranked returns alone: an explored one was drawn at
    # random, so its co-return with the seed says nothing about it. It
    # learns from use, as everything returned does.
    ranked = numbers(uses, &(&1.stage == "returned" and &1.via == "index"))
    used = numbers(uses, &(&1.stage == "used"))
    feedback? = Enum.any?(uses, &(&1.via == "feedback"))
    indexed? = seeds != [] or Enum.any?(uses, &(&1.via in ["index", "explored"]))
    alpha = Config.fetch!(:kumbukumbu, :edge_alpha_permille) / 1000
    beta = Config.fetch!(:kumbukumbu, :edge_beta_permille) / 1000

    turn = remember(repo, e, returned, used, indexed?, feedback?)
    apply_changes(repo, e, Edges.co_returned(seeds, ranked, alpha))

    if turn.indexed and turn.feedback and is_nil(turn.learned_at) do
      exempt = corrections(repo, e.resident_id, turn.returned)
      apply_changes(repo, e, Edges.used(turn.used, turn.returned, exempt, alpha, beta))

      repo.update_all(
        from(t in EdgeTurn, where: t.resident_id == ^e.resident_id and t.turn_ref == ^e.turn_ref),
        set: [learned_at: e.at]
      )
    end

    :ok
  end

  # The turn's returned and used numbers, gathered across its recordings
  # (an adapter's turn records once per tool call; a platform turn its
  # tools before its index), with whether its index and its feedback
  # have each arrived: the use rules wait for both, in either order.
  defp remember(repo, e, returned, used, indexed?, feedback?) do
    row =
      repo.one(
        from(t in EdgeTurn, where: t.resident_id == ^e.resident_id and t.turn_ref == ^e.turn_ref)
      ) ||
        %EdgeTurn{resident_id: e.resident_id, turn_ref: e.turn_ref, returned: [], used: []}

    row = %{
      row
      | returned: Enum.uniq(row.returned ++ returned),
        used: Enum.uniq(row.used ++ used),
        indexed: row.indexed || indexed?,
        feedback: row.feedback || feedback?
    }

    repo.insert!(row,
      on_conflict: {:replace, [:returned, :used, :indexed, :feedback]},
      conflict_target: [:resident_id, :turn_ref]
    )

    row
  end

  defp corrections(_repo, _resident_id, []), do: MapSet.new()

  defp corrections(repo, resident_id, numbers) do
    from(b in Bookmark,
      where:
        b.resident_id == ^resident_id and b.number in ^numbers and b.register == "correction",
      select: b.number
    )
    |> repo.all()
    |> MapSet.new()
  end

  defp apply_changes(_repo, _e, []), do: :ok

  defp apply_changes(repo, e, changes) do
    half_life = Config.fetch!(:kumbukumbu, :edge_half_life_days)
    floor = Config.fetch!(:kumbukumbu, :edge_floor_permille) / 1000
    froms = changes |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    existing =
      from(x in Edge, where: x.resident_id == ^e.resident_id and x.from_number in ^froms)
      |> repo.all()
      |> Map.new(&{{&1.from_number, &1.to_number}, &1})

    changes
    |> Enum.group_by(fn {from, to, _delta} -> {from, to} end, fn {_f, _t, delta} -> delta end)
    |> Enum.each(fn {{from, to}, deltas} ->
      start =
        case existing[{from, to}] do
          nil -> 0.0
          edge -> Edges.decayed(edge.w, edge.touched_at, e.at, half_life)
        end

      w = Enum.reduce(deltas, start, &Edges.bump(&2, &1))
      write(repo, e, from, to, w, floor)
    end)
  end

  defp write(repo, e, from, to, w, floor) when abs(w) < floor do
    repo.delete_all(
      from(x in Edge,
        where: x.resident_id == ^e.resident_id and x.from_number == ^from and x.to_number == ^to
      )
    )
  end

  defp write(repo, e, from, to, w, _floor) do
    repo.insert!(
      %Edge{resident_id: e.resident_id, from_number: from, to_number: to, w: w, touched_at: e.at},
      on_conflict: {:replace, [:w, :touched_at]},
      conflict_target: [:resident_id, :from_number, :to_number]
    )
  end

  defp numbers(uses, keep) do
    for %{target: "bookmark/" <> n} = use <- uses,
        keep.(use),
        {number, ""} <- [Integer.parse(n)],
        do: number
  end

  defp normal(use) do
    %{
      target: Map.get(use, :target) || Map.get(use, "target"),
      stage: Map.get(use, :stage) || Map.get(use, "stage"),
      via: Map.get(use, :via) || Map.get(use, "via")
    }
  end
end

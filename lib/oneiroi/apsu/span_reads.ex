defmodule Oneiroi.Apsu.SpanReads do
  @moduledoc """
  The span rows read (apsu#28): the slowest units of work in a window,
  narrowed by name, kind, the resident served or a trace; and a summary
  by name, so the question "which calls are slow, and what were they
  doing" is one read: each row's time, its time in queries and waiting
  for a connection, its slowest exports and the events it dispatched.
  Platform-wide and contentless; the operator's.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @limit 100

  @doc "The slowest span rows since `hours` ago, at most `limit`, narrowed by `name` (a phrase), `kind`, `subject` (a resident id) and `trace_id`."
  @spec spans(map()) :: [map()]
  def spans(filters) do
    since = since(filters)
    limit = min(filters[:limit] || @limit, 500)

    query =
      from(s in "apsu_span",
        where: s.at >= ^since,
        order_by: [desc: s.duration_ms],
        limit: ^limit,
        select: %{
          at: s.at,
          kind: s.kind,
          name: s.name,
          subject_id: type(s.subject_id, Ecto.UUID),
          trace_id: s.trace_id,
          duration_ms: s.duration_ms,
          db_count: s.db_count,
          db_ms: s.db_ms,
          queue_ms: s.queue_ms,
          exports: s.exports,
          events: s.events,
          failed: s.failed,
          sampled: s.sampled
        }
      )

    query =
      Enum.reduce(filters, query, fn
        {:name, n}, q when is_binary(n) and n != "" ->
          from(s in q, where: ilike(s.name, ^"%#{String.replace(n, ~r/[%_\\\\]/, "")}%"))

        {:kind, k}, q when is_binary(k) and k != "" ->
          from(s in q, where: s.kind == ^k)

        {:trace_id, t}, q when is_binary(t) and t != "" ->
          from(s in q, where: s.trace_id == ^t)

        {:subject, id}, q when is_binary(id) ->
          case Ecto.UUID.dump(id) do
            {:ok, bin} -> from(s in q, where: s.subject_id == ^bin)
            :error -> from(s in q, where: false)
          end

        {:min_ms, ms}, q when is_integer(ms) ->
          from(s in q, where: s.duration_ms >= ^ms)

        _other, q ->
          q
      end)

    Scope.platform(fn -> Repo.all(query) end)
  end

  @doc """
  Each unit of work's name in the window with how many rows it has (the
  slow and the sampled), their p50, p95 and longest, and their mean time
  in queries and waiting for a connection, slowest p95 first. A summary
  of the rows, not of all traffic: the rows are the slow and a sample;
  the metrics count everything.
  """
  @spec summary(map()) :: [map()]
  def summary(filters) do
    since = since(filters)

    Scope.platform(fn ->
      Repo.all(
        from(s in "apsu_span",
          where: s.at >= ^since,
          group_by: [s.kind, s.name],
          order_by: [
            desc: fragment("percentile_cont(0.95) within group (order by ?)", s.duration_ms)
          ],
          limit: 50,
          select: %{
            kind: s.kind,
            name: s.name,
            rows: count(s.id),
            slow: fragment("count(*) filter (where not ?)", s.sampled),
            p50_ms:
              fragment(
                "round(percentile_cont(0.5) within group (order by ?))::int",
                s.duration_ms
              ),
            p95_ms:
              fragment(
                "round(percentile_cont(0.95) within group (order by ?))::int",
                s.duration_ms
              ),
            max_ms: max(s.duration_ms),
            mean_db_ms: fragment("round(avg(?))::int", s.db_ms),
            mean_queue_ms: fragment("round(avg(?))::int", s.queue_ms),
            mean_queries: fragment("round(avg(?))::int", s.db_count)
          }
        )
      )
    end)
  end

  defp since(filters) do
    hours = filters[:hours] || 24
    DateTime.add(Clock.now(), -min(max(hours, 1), 24 * 30) * 3600, :second)
  end
end

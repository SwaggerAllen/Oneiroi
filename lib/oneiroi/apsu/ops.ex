defmodule Oneiroi.Apsu.Ops do
  @moduledoc """
  The ops read surface's in-process half (apsu#23; design/logging-and-
  alerting.md step 1, the witness's word: "a formal, owned querying
  surface"). Two tables this process owns:

  - **The failure ring**: the last `APSU_FAILURE_RING` warnings and
    errors the logger saw, each as structured facts (when, level,
    component, error kind, site and cause, trace id) and its message
    trimmed and scrubbed by the same patterns as the log's own line. It
    lives in this process, not in a backend, so it can be read within the
    minute even when the backends are down: the failure log must not
    share the failure's domain. It is gone on a restart; the logs outside
    keep the long record.
  - **The beats**: when each adapter last asked Oneiroi what waits for
    it, so a reader that went silent is seen the first time anyone asks.

  A logger handler writes the ring; it never raises into the caller.
  """
  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.LogRedacting

  @failures :apsu_failures
  @beats :apsu_beats
  @handler :apsu_failure_ring
  @message_chars 300

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: :apsu_ops)

  @impl GenServer
  def init(opts) do
    Oneiroi.Guardrails.apply!(Keyword.fetch!(opts, :component), :apsu_ops)
    :ets.new(@failures, [:named_table, :public, :ordered_set, write_concurrency: true])
    :ets.new(@beats, [:named_table, :public, :set, read_concurrency: true])
    _ = :logger.remove_handler(@handler)

    :ok =
      :logger.add_handler(@handler, __MODULE__, %{
        level: :warning,
        config: %{size: Oneiroi.Config.fetch!(:apsu, :failure_ring)}
      })

    {:ok, %{}}
  end

  @impl GenServer
  def terminate(_reason, _state), do: :logger.remove_handler(@handler)

  # ---- the logger handler ----

  @doc false
  def log(%{level: level, meta: meta, msg: msg}, %{config: %{size: size}}) do
    key = {System.os_time(:microsecond), System.unique_integer([:monotonic])}

    :ets.insert(
      @failures,
      {key,
       %{
         at: DateTime.from_unix!(elem(key, 0), :microsecond),
         level: level,
         component: meta[:component] && to_string(meta[:component]),
         error_kind: meta[:error_kind] && to_string(meta[:error_kind]),
         error_site: meta[:error_site] && to_string(meta[:error_site]),
         error_cause: meta[:error_cause] && inspect(meta[:error_cause]),
         trace_id: meta[:trace_id] && to_string(meta[:trace_id]),
         message: message(msg)
       }}
    )

    trim(size)
  rescue
    # The ring is a convenience; the log line itself is the record. A
    # handler that raises is removed by the logger, and the ring would
    # go quiet for the rest of the process.
    # oneiroi:allow error_site: a logger handler must not raise into the logger
    _ -> :ok
  catch
    # oneiroi:allow error_site: a logger handler must not raise into the logger
    _, _ -> :ok
  end

  defp message({:string, text}), do: scrub(text)
  defp message({:report, report}), do: scrub(inspect(report))
  defp message({format, args}) when is_list(args), do: scrub(:io_lib.format(format, args))
  defp message(other), do: scrub(inspect(other))

  defp scrub(text) do
    text
    |> IO.chardata_to_string()
    |> String.slice(0, @message_chars)
    |> LogRedacting.redact()
  end

  defp trim(size) do
    if :ets.info(@failures, :size) > size do
      case :ets.first(@failures) do
        :"$end_of_table" -> :ok
        oldest -> :ets.delete(@failures, oldest)
      end
    end

    :ok
  end

  # ---- reads ----

  @doc "The ring, newest first, narrowed by any of kind, site, component, trace id."
  def failures(filters \\ %{}) do
    @failures
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&matches?(&1, filters))
    |> Enum.reverse()
  end

  defp matches?(row, filters) do
    Enum.all?(filters, fn
      {_key, nil} -> true
      {key, value} -> Map.get(row, key) == value
    end)
  end

  @doc "The jobs Oban discarded since an instant: worker, when, the attempt, the last error trimmed and scrubbed; never the arguments."
  def discarded_jobs(%DateTime{} = since) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.all(
        from(j in Oban.Job,
          where: j.state == "discarded" and j.discarded_at >= ^since,
          order_by: [desc: j.discarded_at],
          limit: 50,
          select: %{worker: j.worker, at: j.discarded_at, errors: j.errors, attempt: j.attempt}
        )
      )
    end)
    |> Enum.map(fn j ->
      last = j.errors |> List.wrap() |> List.last()
      %{worker: j.worker, at: j.at, attempt: j.attempt, error: last && scrub(last["error"] || "")}
    end)
  end

  @doc "An adapter asked what waits for it, now."
  def beat(name) when is_binary(name),
    do: :ets.insert(@beats, {name, Clock.now()})

  @doc "When the adapter last asked, or nil since this process started."
  def last_beat(name) do
    case :ets.lookup(@beats, name) do
      [{^name, at}] -> at
      [] -> nil
    end
  end
end

defmodule Oneiroi.Worker do
  @moduledoc """
  What every Oban worker adopts (conventions §7, §10):

      defmodule Oneiroi.SimaQian.AttestationWorker do
        use Oneiroi.Worker, queue: :sima_qian_nightly
        def run(%{"resident_id" => id}), do: ...
      end

  `perform/1` is this module's: it restores the trace id the enqueuing
  side put in the args (`Oneiroi.Apsu.Jobs`), sets the component on
  the logger, and takes the platform scope on the process before calling
  `run/1`, because a worker is a cross-tenant job by construction and is
  named in its system doc. Workers are replay-safe: `run/1` must survive
  a duplicate run, and the unique-job key on the enqueue side is what
  keeps duplicates rare rather than impossible.
  """

  defmacro __using__(opts) do
    queue = Keyword.fetch!(opts, :queue)
    unique = Keyword.get(opts, :unique, period: 60)
    # Oban's own default unless a worker says otherwise. A worker that
    # must not run twice says 1: Lifeline (`Oneiroi.Apsu.oban_config/0`)
    # retries a job orphaned mid-run while it has attempts left, and
    # discards it when it has none.
    max_attempts = Keyword.get(opts, :max_attempts, 20)

    quote do
      use Oban.Worker,
        queue: unquote(queue),
        unique: unquote(unique),
        max_attempts: unquote(max_attempts)

      require Logger

      @impl Oban.Worker
      def perform(%Oban.Job{args: args}) do
        Logger.metadata(
          component: unquote(queue) |> Atom.to_string() |> String.split("_") |> hd(),
          trace_id: Map.get(args, "trace_id")
        )

        Oneiroi.Scope.put(:platform)
        run(Map.delete(args, "trace_id"))
      end
    end
  end
end

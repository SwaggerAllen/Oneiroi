defmodule Oneiroi.Projection do
  @moduledoc """
  What a system's Ecto projector adopts (conventions §6, §12):

      defmodule Oneiroi.Resident.Projectors.Resident do
        use Oneiroi.Projection, name: "resident_resident"

        fold %ResidentCreated{} = e, _metadata, fn multi ->
          Ecto.Multi.insert(multi, :row, %Row{...})
        end
      end

  A projector is a cross-tenant job by nature: it folds every resident's
  events into rows, so it runs under the platform scope, taken on the
  process at start and set on the connection inside every projection
  transaction by `fold/3`, which is the library's `project/3` with that
  one step prepended. That is the one place the platform scope is taken
  by machinery rather than by a named call; every other cross-tenant read
  is a `Oneiroi.Scope.platform/1` a reviewer can see.
  """

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)

    quote do
      # Atoms rather than aliases, for the reason `Oneiroi.Router` gives:
      # both are read when the projector runs, and a literal alias here
      # would put every projector on the compile-connected graph.
      use Commanded.Projections.Ecto,
        application: Module.concat([Oneiroi, Commanded]),
        repo: Module.concat([Oneiroi, Repo]),
        name: unquote(name),
        consistency: :strong

      import Oneiroi.Projection, only: [fold: 3]

      @impl Commanded.Event.Handler
      def init(config) do
        Oneiroi.Scope.put(:platform)
        {:ok, config}
      end
    end
  end

  @doc "The library's `project/3`, with the platform scope set on the connection first."
  defmacro fold(event, metadata, lambda) do
    quote do
      project(unquote(event), unquote(metadata), fn multi ->
        # The multi runs in the handler's process, so the process scope
        # is taken here as well as on the connection: `init/1` runs in a
        # different process than `handle/2` in the library's own startup.
        multi =
          Ecto.Multi.run(multi, :oneiroi_scope, fn repo, _changes ->
            Oneiroi.Scope.put(:platform)
            Oneiroi.Scope.set_on_connection(repo, :platform)
          end)

        unquote(lambda).(multi)
      end)
    end
  end
end

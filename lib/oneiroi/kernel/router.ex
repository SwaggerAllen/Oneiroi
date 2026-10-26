defmodule Oneiroi.Router do
  @moduledoc """
  What a system's command router adopts:

      defmodule Oneiroi.Resident.Router do
        use Oneiroi.Router,
          aggregate: "Oneiroi.Resident.Resident",
          prefix: "resident-",
          commands: "Oneiroi.Resident.Commands",
          dispatching: ~w(CreateResident MintId ...)
      end

  It names `Oneiroi.Commanded` and installs the actor middleware, so the
  validator cannot be forgotten on a router. Strong consistency by
  default: a dispatch returns once the projections have applied the
  events, which is what lets a request read its own write and lets a test
  assert on a projection without sleeping. Dispatch returns the events it
  wrote, which is what a caller that needs an allocated id reads.

  The aggregate and the commands are named as strings and the
  application and the middleware built with `Module.concat/1`, never
  written as aliases: Commanded's `identify`, `dispatch` and `middleware`
  are macros, and the compiler treats a literal alias handed to a macro
  as a compile-time dependency whether or not the expansion needs the
  module compiled first. None of these does. The application and the
  middleware are read at dispatch time, and a command is needed only as
  a struct, which the atom this macro expands to gives as an export
  dependency, the precise one. The ratchet
  (`mix xref graph --label compile-connected --fail-above 0`) is armed
  at 0 and this is what keeps every router off that graph; the first
  version wrote the aliases and put both routers on it.
  """

  defmacro __using__(opts) do
    # The options arrive as AST (a `~w` sigil is a macro call), so each is
    # evaluated here, where the module names become atoms.
    opts = Enum.map(opts, fn {key, ast} -> {key, ast |> Code.eval_quoted() |> elem(0)} end)
    aggregate = Module.concat([Keyword.fetch!(opts, :aggregate)])
    prefix = Keyword.fetch!(opts, :prefix)
    namespace = Keyword.fetch!(opts, :commands)
    commands = Enum.map(Keyword.fetch!(opts, :dispatching), &Module.concat([namespace, &1]))

    quote do
      use Commanded.Commands.Router,
        application: Module.concat([Oneiroi, Commanded]),
        default_consistency: :strong,
        default_dispatch_return: :events

      middleware(Module.concat([Oneiroi, Commanded, Middleware, Actor]))
      identify(unquote(aggregate), by: :id, prefix: unquote(prefix))
      dispatch(unquote(commands), to: unquote(aggregate))
    end
  end
end

defmodule Oneiroi.Command do
  @moduledoc """
  What every command carries (conventions §6): the actor, the instant,
  and, for a decision, the note.

      defmodule Oneiroi.AgathosDaimon.Commands.CreateResident do
        use Oneiroi.Command, fields: [:id, :name, :slug]
      end

  `actor` and `at` are enforced keys, so a command cannot be built without
  them, and the router middleware checks them again at dispatch so a
  hand-built struct with a nil actor is refused rather than written.
  """

  defmacro __using__(opts) do
    fields = Keyword.get(opts, :fields, [])
    decision? = Keyword.get(opts, :decision, false)
    extra = if decision?, do: [:note], else: []

    quote do
      @enforce_keys [:actor, :at]
      defstruct [:actor, :at] ++ unquote(extra) ++ unquote(fields)

      @doc "Whether this command carries a note the resident reads first."
      def __decision__?, do: unquote(decision?)
    end
  end
end

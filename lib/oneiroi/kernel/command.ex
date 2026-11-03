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

  `bounds:` names the fields that are names rather than words (a tag, a
  label, a key, a slug) and the most characters each may hold:

      use Oneiroi.Command, fields: [:key, :label], bounds: [key: 64, label: 120]

  The middleware checks them at dispatch, before any event exists, and
  refuses an overlong one as `<field>_too_long`. Free text is never
  bounded here: what the database does not demand, the command does not
  ask (conventions §6, 2026-11-03). A bound belongs on the command and
  not the projection: an event already stored has to project, and a
  projection that refuses one is the outage of 2026-11-03.
  """

  defmacro __using__(opts) do
    fields = Keyword.get(opts, :fields, [])
    decision? = Keyword.get(opts, :decision, false)
    extra = if decision?, do: [:note], else: []

    # Each bound with its refusal's name, made here at compile time so no
    # atom is ever made from input.
    bounds =
      for {field, max} <- Keyword.get(opts, :bounds, []) do
        unless field in fields,
          do: raise(ArgumentError, "bound on #{field}, which is not a field")

        unless is_integer(max) and max > 0, do: raise(ArgumentError, "bound #{inspect(max)}")
        {field, max, :"#{field}_too_long"}
      end

    quote do
      @enforce_keys [:actor, :at]
      defstruct [:actor, :at] ++ unquote(extra) ++ unquote(fields)

      @doc "Whether this command carries a note the resident reads first."
      def __decision__?, do: unquote(decision?)

      @doc "The fields that are names, each with its most characters and its refusal."
      def __bounds__, do: unquote(Macro.escape(bounds))
    end
  end
end

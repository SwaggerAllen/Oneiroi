defmodule Oneiroi.Event do
  @moduledoc """
  What every event in the log is (conventions §6, spec §3.1):

      defmodule Oneiroi.Resident.Events.ResidentCreated do
        use Oneiroi.Event, version: 1, fields: [:id, :name, :slug]
      end

  Every event carries `actor` (an `Oneiroi.Actor`) and `at` (the instant,
  taken at the command edge from the injected clock, never inside an
  aggregate), and a decision event (`decision: true`) carries `note`, the
  text the resident reads first. The command middleware refuses a command
  without an actor or, for a decision, without a note, so an event without
  them cannot be written.

  `redact:` names fields the records export writes as null (a second
  factor's ciphertext): the log holds them, the repository never does.
  `export: false` keeps an event out of the records export altogether:
  the export's own bookkeeping (`ExportWritten`, `BackupCommitted`) is a
  fact about the repository, kept in the log for the dashboard and the
  next run, and exporting it meant every nightly backup changed the
  export it had just made, so an unchanged resident never converged on
  a commit-free night.
  `instants:` names fields besides `at` that hold a `DateTime`, so the
  decoder restores them from the log's ISO-8601 strings; an instant field
  left off the list comes back as a string and fails the projection's
  `:utc_datetime_usec` column on insert, which is what `expires_at` did
  the first time a session was projected.

  Shapes are immutable contracts: `version:` is the event's declared
  version, listed in its system's `events/0`, and a change to the shape is
  a new version with a `Commanded.Event.Upcaster` applied on read. The
  struct derives `Jason.Encoder` for Commanded's JSON serializer and
  implements the decoder that restores the actor and the instant from the
  log, which is what makes `records/events/*.jsonl` a replayable record.

  This module is the macro and nothing else; the restoring is
  `Oneiroi.Event.Codec`. A module used at compile time by every event is
  on the compile-connected graph the moment it has a dependency of its
  own (`mix xref graph --label compile-connected`, the ratchet at 0), so
  the half that calls `Oneiroi.Actor` lives where only the generated
  code, at runtime, reaches it.
  """

  # Lexical only: the alias is resolved inside the quote, so the generated
  # module calls the codec and this one never does.
  alias Oneiroi.Event.Codec

  defmacro __using__(opts) do
    version = Keyword.fetch!(opts, :version)
    fields = Keyword.get(opts, :fields, [])
    decision? = Keyword.get(opts, :decision, false)
    redact = Keyword.get(opts, :redact, [])
    instants = [:at | Keyword.get(opts, :instants, [])]
    export? = Keyword.get(opts, :export, true)
    extra = if decision?, do: [:note], else: []

    quote do
      @derive Jason.Encoder
      @enforce_keys [:actor, :at]
      defstruct [:actor, :at] ++ unquote(extra) ++ unquote(fields)

      @doc "The event's declared version (conventions §6)."
      def __version__, do: unquote(version)

      @doc "Fields the export writes as null: ciphertext and the like never enter a repository (spec §2.2)."
      def __redact__, do: unquote(redact)

      @doc "Whether the records export carries this event (false for the export's own bookkeeping)."
      def __export__?, do: unquote(export?)

      @doc "The fields holding an instant, restored from the log as `DateTime`."
      def __instants__, do: unquote(instants)

      @doc "Whether this event carries a note the resident reads first."
      def __decision__?, do: unquote(decision?)

      @doc "The event's type name as the log records it."
      def __type__, do: inspect(__MODULE__)

      defimpl Commanded.Serialization.JsonDecoder do
        def decode(event), do: Codec.restore(event, event.__struct__.__instants__())
      end
    end
  end
end

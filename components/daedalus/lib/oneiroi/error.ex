defmodule Oneiroi.Error do
  @moduledoc """
  A component's error struct, built from its `errors/0` registry
  (v5 §2.2, conventions §8):

      defmodule Engine.Error do
        @moduledoc "Engine's boundary failure vocabulary."
        use Oneiroi.Error, component: Engine
      end

  and `{:error, %Engine.Error{kind: :engine_grammar_invalid}}` is the
  spelling at the boundary, unchanged — callers still match on the
  struct, and the meaning and remedy they would otherwise repeat at every
  construction site come from the declaration.

  ## Why the registry rather than an AST pass

  §2.14 asks for declared↔constructed both ways. The expensive direction
  is a check hunting `kind:` keys, which is a check guessing at what
  construction looks like: it would have to know every spelling of a
  struct literal, a `struct/2` call and a builder, and it would be wrong
  about the next one. The cheap direction is to make construction go
  through something the registry answers. `new/2` resolves its kind
  against `errors/0` and raises on anything the component did not
  declare, so the vocabulary a caller can build is the vocabulary the
  composer validated — and the meaning, remedy, runbook and admin link
  ride along rather than being copied.

  What is left for the audit is the direction no constructor can see: a
  kind declared and never constructed, which is dead vocabulary in a
  catalog operators read. That check is `mix oneiroi.audit`'s.

  ## The grade, stated rather than implied

  Two things this is *not*, both worth naming because the alternative is
  a reader assuming them:

    * **Construction-time, not compile-time.** Elixir validates a struct
      literal's *keys* at compile time and never its values, so no
      generator can make `%Engine.Error{kind: :invented}` a compile
      error. The residue is one narrow shape — a hand-built literal that
      bypasses `new/2` — rather than the open set an AST pass would have
      had to cover, and writing one means writing the module, the field
      and the atom by hand, which is a different act from forgetting to
      register.
    * **Resolved at runtime, deliberately.** Reading `errors/0` while
      compiling the error module would make `Engine.Error` wait for
      `Engine` — and conventions §8's own spelling has `Engine`
      constructing `%Engine.Error{}`, which makes `Engine` wait for
      `Engine.Error`. That is a compile cycle and a deadlocked build, on
      the canonical usage, for a check the previous paragraph says is not
      available anyway. `xref`'s cycle prohibition is already a hard gate
      (conventions §2); a mechanism whose adoption trips it is not a
      mechanism.

  ## Every error carries its site

  `kind` is what went wrong, in the vocabulary a client and an operator
  share: one kind is built in many places. `site` is where: an atom,
  prefixed with the owning component's slug, written once in the whole
  project at the one line that builds the error or catches the failure
  it wraps. An operator holding a response or a log line greps the site
  and lands on that line.

  The failure this prevents: on 2026-11-01 the first real import
  answered a bare 500. The cause was found only by reading the service
  log by timestamp, and several producers of one kind meant even a
  well-formed error could not say which of them it came from.

  `new/3` builds an error this code decided on. `caught/4` wraps a
  failure that did not start here: an exception, an exit, a library's
  `{:error, reason}`. It records the cause's *class* (`describe/1`): the
  exception module, the bare atom, a tuple's tag. Never its message or
  payload, which is where a credential or another tenant's data rides.
  The crash report that leaked a token on 2026-11-01 printed exactly
  that.

  `mix oneiroi.audit`'s `error_site` check holds the sites to being
  literal, prefixed and unique, and `Oneiroi.Component.API` refuses an
  export's `{:error, _}` that carries none (`:raise` under test, a
  warning otherwise).

  ## Remedy presence is not re-checked here

  `remedy:` is required by the registry row, so the composer has already
  failed the build on a kind without one (ORC-22). The struct carries it
  from the declaration rather than re-deriving it, which is what keeps
  the declaration the single copy.

  ## The catalog is not a file

  The generated error catalog is a rendering of the inventory on demand
  and never something committed (docs/non-goals.md's
  no-hand-maintained-inventories rule). It ships with the docs-site
  composition, which conventions §13 defers.
  """

  @fields [:kind, :site, :meaning, :remedy, :runbook, :admin, :details, :cause]

  @doc "The struct fields every component error carries, in order."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc """
  Builds `kind` for `component`, or raises naming the declared vocabulary.

  The generated `new/2` delegates here so the resolution rule has one
  implementation rather than one per adopting module.
  """
  @spec build!(module(), module(), atom(), atom(), keyword(), atom() | nil) :: struct()
  def build!(struct_module, component, kind, site, details, cause \\ nil) do
    site!(component, site)

    case Enum.find(declared(component), &match?({^kind, _meaning, _opts}, &1)) do
      {^kind, meaning, opts} ->
        struct!(struct_module,
          kind: kind,
          site: site,
          meaning: meaning,
          remedy: Keyword.get(opts, :remedy),
          runbook: Keyword.get(opts, :runbook),
          admin: Keyword.get(opts, :admin),
          details: details,
          cause: cause
        )

      nil ->
        raise ArgumentError,
              "#{inspect(kind)} is not a kind #{inspect(component)} declares in errors/0 " <>
                "(declared: #{inspect(kinds(component))})"
    end
  end

  # The audit holds sites to literal, prefixed and unique; this holds the
  # prefix at runtime too, so a site built from a variable cannot borrow
  # another component's name.
  defp site!(component, site) do
    prefix = "#{component.slug()}_"

    unless is_atom(site) and site not in [nil, true, false] and
             String.starts_with?(Atom.to_string(site), prefix) do
      raise ArgumentError,
            "#{inspect(site)} is not a site for #{inspect(component)}: " <>
              "a site is an atom starting #{prefix}, written once at the line that builds the error"
    end
  end

  @doc """
  A failure's class, safe to log and to answer with: an exception's
  module, a bare atom, a tuple's leading atom, a struct's module, or,
  for one of this platform's own errors, its site.
  Everything else is `:term`. Never a message, a payload or a field,
  because those are where a credential or a tenant's data rides.
  """
  @spec describe(term()) :: atom()
  def describe(%{__exception__: true, __struct__: module}), do: module
  # One of ours, wrapped again: its site is the more useful cause, and it
  # chains one site to the next.
  def describe(%{__struct__: _module, site: site, kind: kind} = error)
      when is_atom(site) and not is_nil(site) and is_atom(kind) do
    if sited?(error), do: site, else: error.__struct__
  end

  def describe(%{__struct__: module}), do: module
  def describe(atom) when is_atom(atom), do: atom

  def describe(tuple) when is_tuple(tuple) and tuple_size(tuple) > 0 and is_atom(elem(tuple, 0)),
    do: elem(tuple, 0)

  def describe(_other), do: :term

  @doc "Whether `term` is a component error carrying its site."
  @spec sited?(term()) :: boolean()
  def sited?(%{__struct__: module, site: site, kind: kind})
      when is_atom(site) and not is_nil(site) and is_atom(kind) do
    function_exported?(module, :component, 0)
  end

  def sited?(_term), do: false

  @doc """
  The Logger metadata an error contributes: its kind, its site and its
  cause's class. What a log line about an error carries instead of the
  error itself; the trace id rides the process metadata already.
  """
  @spec metadata(struct()) :: keyword()
  def metadata(%{kind: kind, site: site} = error) do
    [error_kind: kind, error_site: site, error_cause: Map.get(error, :cause)]
  end

  @doc "The kinds `component` declares, in declaration order."
  @spec kinds(module()) :: [atom()]
  def kinds(component) do
    for {kind, _meaning, _opts} <- declared(component), do: kind
  end

  # A malformed entry is the composer's line, in full and alongside
  # everything else wrong with the roster; here it is only skipped, so a
  # broken declaration cannot become a half-built error at a boundary.
  defp declared(component) do
    for {kind, meaning, opts} <- component.errors(),
        is_atom(kind) and is_binary(meaning) and is_list(opts),
        do: {kind, meaning, opts}
  end

  defmacro __using__(opts) do
    component = Keyword.fetch!(opts, :component)

    quote do
      @oneiroi_error_component unquote(component)

      @enforce_keys [:kind, :site]
      defstruct unquote(@fields)

      @typedoc "One of the component's declared boundary failures."
      @type t :: %__MODULE__{
              kind: atom(),
              site: atom(),
              cause: atom() | nil,
              meaning: String.t(),
              remedy: String.t(),
              runbook: String.t() | nil,
              admin: String.t() | nil,
              details: keyword()
            }

      @doc "The component whose `errors/0` this struct speaks for."
      @spec component() :: module()
      def component, do: @oneiroi_error_component

      @doc "Every kind the component declares, in declaration order."
      @spec kinds() :: [atom()]
      def kinds, do: Oneiroi.Error.kinds(@oneiroi_error_component)

      @doc """
      Builds a declared error at `site`, the atom naming this line.

      `details` is caller context — identifiers, counts, the scope the
      failure happened in — and never a value the registry already
      carries, nor a secret (`Oneiroi.Config.Secret`).
      """
      @spec new(atom(), atom(), keyword()) :: t()
      def new(kind, site, details \\ []) do
        Oneiroi.Error.build!(__MODULE__, @oneiroi_error_component, kind, site, details)
      end

      @doc """
      Wraps a failure that did not start here (an exception, an exit, a
      library's `{:error, reason}`) as a declared error at `site`.
      Only the cause's class is kept (`Oneiroi.Error.describe/1`).
      """
      @spec caught(atom(), atom(), term(), keyword()) :: t()
      def caught(kind, site, cause, details \\ []) do
        Oneiroi.Error.build!(
          __MODULE__,
          @oneiroi_error_component,
          kind,
          site,
          details,
          Oneiroi.Error.describe(cause)
        )
      end
    end
  end
end

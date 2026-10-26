defmodule Oneiroi.Platform.Policies.Tables do
  @moduledoc """
  The migration lint (conventions §6, §12): every table has one owner,
  a scope column and a row-level policy.

  Read at AST grade off the migrations under the registered scope. A
  table is created through `Oneiroi.Migration.projection/3`, which adds
  the scope column and the policy by construction, and whose first
  argument names the table; the lint checks that name against the
  roster's slugs, because a table outside a system's prefix is a table
  nobody owns. A bare `create table(...)` is reported: it has no tenancy
  unless its author wrote every statement by hand, and a hand that
  remembered them this time is the one that forgets next time. Oban's
  and the event store's tables arrive through their own migrations under
  their reserved names and never appear as a `create table` here.

  No `oneiroi:allow` escape: a table that must not carry a scope column
  (there is none yet) is an argument to make in the roster, not a comment.
  """

  @behaviour Oneiroi.Audit.Check

  alias Oneiroi.Audit.Source

  # Tables a library keeps for itself, created by their own statement in
  # a named migration and admitted here by exact name; a `CREATE TABLE`
  # in an `execute` for any other name is a table with no tenancy wearing
  # raw SQL.
  @reserved ["projection_versions"]
  @create ~r/create\s+table\s+(?:if\s+not\s+exists\s+)?"?([a-z_]+)"?/i

  @impl Oneiroi.Audit.Check
  def run(scope) do
    slugs = Enum.map(Oneiroi.Boot.components(), &Atom.to_string(&1.slug()))

    scope
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      case Source.read(path) do
        {:ok, source} -> findings(source, slugs)
        {:error, problem} -> [problem]
      end
    end)
  end

  defp findings(source, slugs) do
    source.ast
    |> Source.collect(&violation(&1, slugs))
    |> Enum.map(fn {line, message} -> "#{source.path}:#{line}: tables: #{message}" end)
  end

  # `create table(:name, ...)` outside the helper: no tenancy by construction.
  defp violation({:create, meta, [{:table, _tmeta, [name | _]} | _rest]}, _slugs) do
    [
      {Keyword.get(meta, :line, 0),
       "#{inspect(name)} is created with a bare create table (use Oneiroi.Migration.projection/3, which adds the scope column and the policy)"}
    ]
  end

  # `projection(:name, scope: ...)`: the name must sit on a system's prefix.
  defp violation({:projection, meta, [name | _rest]}, slugs) when is_atom(name) do
    table = Atom.to_string(name)

    if Enum.any?(slugs, &String.starts_with?(table, &1 <> "_")) do
      []
    else
      [
        {Keyword.get(meta, :line, 0),
         "#{inspect(name)} is on no system's prefix (expected <slug>_*; the roster's slugs are #{Enum.join(slugs, ", ")})"}
      ]
    end
  end

  # `execute("CREATE TABLE ...")`: raw SQL is not a way around the helper.
  defp violation({:execute, meta, [sql | _rest]}, _slugs) when is_binary(sql) do
    for [_all, table] <- Regex.scan(@create, sql), table not in @reserved do
      {Keyword.get(meta, :line, 0),
       "#{inspect(table)} is created by raw SQL (use Oneiroi.Migration.projection/3; only #{inspect(@reserved)} is reserved)"}
    end
  end

  defp violation(_node, _slugs), do: []
end

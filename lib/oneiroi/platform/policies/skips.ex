defmodule Oneiroi.Platform.Policies.Skips do
  @moduledoc """
  The `skips` check (conventions §9, §13): a skipped test names the
  ticket that owns it, or CI rejects it.

  A bare `@tag :skip` is how a failing test leaves the suite for good: the
  pipeline escalates two CI reds to a human, so the pressure on a red test
  is to skip it, and a skip with no owner is a test nobody will un-skip.
  The ticket key is what makes the skip a debt with an address.

  Accepted: `@tag skip: "ORC-123 ..."`, and the same on `@moduletag`,
  where the string carries a key shaped `[A-Z][A-Z0-9]+-[0-9]+`. Reported:
  `@tag :skip`, `@tag skip: true`, and a `skip:` string with no key.
  Matched at AST grade, so the words inside a string or a docstring are
  not a finding.

  No `oneiroi:allow` escape, on purpose: an escape would be a second way to
  skip without a ticket, and the check exists to leave exactly one.
  """

  @behaviour Oneiroi.Audit.Check

  alias Oneiroi.Audit.Source

  @key ~r/\b[A-Z][A-Z0-9]+-[0-9]+\b/
  @tags [:tag, :moduletag]

  @impl Oneiroi.Audit.Check
  def run(scope) do
    scope
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      case Source.read(path) do
        {:ok, source} -> findings(source)
        {:error, problem} -> [problem]
      end
    end)
  end

  defp findings(source) do
    source.ast
    |> Source.collect(&violation/1)
    |> Enum.map(fn {line, message} -> "#{source.path}:#{line}: skips: #{message}" end)
  end

  # `@tag :skip`
  defp violation({:@, meta, [{tag, _tag_meta, [:skip]}]}) when tag in @tags do
    [
      {Keyword.get(meta, :line, 0),
       "a bare @#{tag} :skip; name the ticket: @#{tag} skip: \"ORC-n reason\""}
    ]
  end

  # `@tag skip: ...`
  defp violation({:@, meta, [{tag, _tag_meta, [[{:skip, value}]]}]}) when tag in @tags do
    if keyed?(value),
      do: [],
      else: [
        {Keyword.get(meta, :line, 0),
         "a @#{tag} skip: with no ticket key (expected \"ORC-n reason\")"}
      ]
  end

  defp violation(_node), do: []

  defp keyed?(value) when is_binary(value), do: Regex.match?(@key, value)
  defp keyed?(_value), do: false
end

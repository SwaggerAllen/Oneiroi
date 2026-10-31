defmodule Oneiroi.Apsu.Policies.ProjectorScope do
  @moduledoc """
  A projector's query names the tenant whose row it means (conventions
  §12, sima-qian #21). Projectors run under the platform scope
  (`Oneiroi.Projection`), so row-level security filters nothing they
  read or write: a `where:` that keys on a number, a ref, a slug or a
  session key alone reaches every resident holding the same one.
  Resolving one resident's prediction #1 resolved every resident's
  prediction #1 until 10-31, and a rebuilt copy, which keeps the
  source's refs and keys, collided on every one of them.

  Read at AST grade off the projectors: every `from(x in Schema, ...)`
  must have a `where:` that reads `x.resident_id`, `x.account_id` or
  `x.id` (the row's own id, which is the tenant's on the resident and
  account tables). The escape is `# oneiroi:allow projector_scope` with
  the reason beside it, for a row keyed by something unique across the
  store by construction.
  """

  @behaviour Oneiroi.Audit.Check

  alias Oneiroi.Audit.Source

  @tenant [:resident_id, :account_id, :id]

  @impl Oneiroi.Audit.Check
  def run(scope) do
    Source.scan(scope, "projector_scope", fn source ->
      source.ast
      |> Source.collect(&violation/1)
      |> Enum.map(fn {line, message} -> {line, "projector_scope: " <> message} end)
    end)
  end

  defp violation({:from, meta, [{:in, _in, [{var, _vmeta, ctx}, schema]}, opts]})
       when is_atom(var) and is_atom(ctx) and is_list(opts) do
    case Keyword.fetch(opts, :where) do
      {:ok, where} ->
        if tenant?(where, var),
          do: [],
          else: [
            {Keyword.get(meta, :line, 0),
             "a query on #{Macro.to_string(schema)} keys on no tenant (name #{var}.resident_id, #{var}.account_id or #{var}.id: a projector runs under the platform scope, so nothing else limits it to one resident)"}
          ]

      :error ->
        [
          {Keyword.get(meta, :line, 0),
           "a query on #{Macro.to_string(schema)} has no where: at all, so it reaches every resident's rows"}
        ]
    end
  end

  defp violation(_node), do: []

  defp tenant?(where, var) do
    where
    |> Source.collect(fn
      {{:., _dot, [{^var, _meta, ctx}, field]}, _call, []}
      when is_atom(ctx) and field in @tenant ->
        [field]

      _other ->
        []
    end)
    |> Enum.any?()
  end
end

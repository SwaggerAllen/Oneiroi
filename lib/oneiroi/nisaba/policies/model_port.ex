defmodule Oneiroi.Nisaba.Policies.ModelPort do
  @moduledoc """
  The `model_port` check (conventions §11, §13, `non-asks.md`): every
  model call goes through `Oneiroi.Nisaba.Provider`, so outside the
  port's own implementations nothing in the tree speaks HTTP to a model
  provider. Two things are reported, at AST grade:

    * a remote call on an HTTP client: `Req`, `Finch`, `Mint`,
      `HTTPoison`, `Tesla`, `:httpc`, `:hackney` or `:gun`;
    * a string literal naming a provider host (`openrouter.ai`,
      `api.openai.com`, `api.anthropic.com`,
      `generativelanguage.googleapis.com`), reported on the line of the
      call it sits in.

  The port's implementations live under `lib/oneiroi/nisaba/provider/`
  and are the one path exempt, by prefix rather than by tag, because an
  escape on the port itself would be the port excusing itself.

  Escape elsewhere: `# oneiroi:allow model_port`, on the offending line
  or the comment line directly above it (`Oneiroi.Audit.Source`).
  """

  @behaviour Oneiroi.Audit.Check

  alias Oneiroi.Audit.Source

  @tag "model_port"
  @exempt ~r{(^|/)lib/oneiroi/nisaba/provider/}
  @clients [:Req, :Finch, :Mint, :HTTPoison, :Tesla]
  @erlang_clients [:httpc, :hackney, :gun]
  @hosts ~w(openrouter.ai api.openai.com api.anthropic.com generativelanguage.googleapis.com)

  @doc "The bare name a `oneiroi:allow` comment gives this check."
  @spec tag() :: String.t()
  def tag, do: @tag

  @impl Oneiroi.Audit.Check
  def run(scope), do: Source.scan(scope, @tag, &violations/1)

  defp violations(source) do
    if Regex.match?(@exempt, source.path), do: [], else: findings(source)
  end

  defp findings(source) do
    # A module attribute's value is documentation or configuration (a
    # moduledoc naming the hosts it bans, a list of them), never a call,
    # so a finding on an attribute's line is dropped.
    attribute_lines =
      source.ast
      |> Source.collect(fn
        {:@, _meta, [{_name, meta, _value}]} when is_list(meta) -> [Keyword.get(meta, :line, 0)]
        _node -> []
      end)
      |> MapSet.new()

    source.ast
    |> Source.collect(fn
      {{:., _dot, [module, _fun]}, _meta, args} = node when is_list(args) ->
        client(module, node) ++ hosts(node)

      {_form, meta, args} = node when is_list(meta) and is_list(args) ->
        hosts(node)

      _node ->
        []
    end)
    |> Enum.reject(fn {line, _message} -> MapSet.member?(attribute_lines, line) end)
    |> Enum.uniq()
  end

  defp client(module, node) do
    cond do
      name = Enum.find(@clients, &Source.alias?(module, &1)) ->
        [{Source.line(node), "#{name} called outside the provider port (conventions §11)"}]

      is_atom(module) and module in @erlang_clients ->
        [
          {Source.line(node),
           "#{inspect(module)} called outside the provider port (conventions §11)"}
        ]

      true ->
        []
    end
  end

  # A literal has no line of its own, so the host is reported on the
  # nearest enclosing node that has one.
  defp hosts({_form, _meta, args} = node) do
    args
    |> literals()
    |> Enum.filter(fn text -> Enum.any?(@hosts, &String.contains?(text, &1)) end)
    |> Enum.map(fn text ->
      {Source.line(node),
       "a model provider's host in a string outside the provider port: #{text}"}
    end)
  end

  defp literals(args) do
    Enum.flat_map(args, fn
      text when is_binary(text) -> [text]
      {:<<>>, _meta, parts} -> literals(parts)
      list when is_list(list) -> literals(list)
      {key, value} when is_atom(key) -> literals([value])
      _other -> []
    end)
  end
end

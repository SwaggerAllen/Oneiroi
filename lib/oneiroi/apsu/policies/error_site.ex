defmodule Oneiroi.Apsu.Policies.ErrorSite do
  @moduledoc """
  Every place an error starts carries a site, and no two places share
  one (`Oneiroi.Error`'s "Every error carries its site").

  An error starts in one of two ways, and this finds both:

    * **Built here.** A component error's `new/3` or `caught/4`, and the
      edge's `problem/5`. The site argument must be a literal atom, it
      must start with the owning component's slug (read off the error
      module's name: `Oneiroi.SimaQian.Error` builds `sima_qian_` sites,
      `problem/5` builds `web_` ones), and no other line in the project
      may name it. A bare `{:error, :atom}`, `{:error, "text"}`, a tuple
      with a literal tag or a hand-built error struct, constructed
      anywhere but a pattern, is a site nobody named, and is reported as
      one.
    * **Caught here.** Every `rescue` and `catch` clause either builds a
      sited error (`caught/4`, usually) or raises again. A clause that
      swallows a foreign failure without naming the line it was caught
      on is what made the 2026-11-01 500 unreadable.

  What it cannot see is a library's `{:error, reason}` passed straight
  through a `with`: the value is a variable here. That half is
  `Oneiroi.Component.API.returned/3`, which refuses an unsited error
  leaving any export while the suite runs.

  Patterns are not constructions: a `case` clause, a function head, the
  left of `=` or `<-`, `match?/2`'s first argument and every typespec
  name `{:error, :atom}` without building one. `quote` blocks are code
  for elsewhere and are skipped.

  Escape: `# oneiroi:allow error_site`, on the offending line or the
  comment line directly above it (`Oneiroi.Audit.Source`), for a
  callback whose contract is a bare tuple a library defines.
  """

  @behaviour Oneiroi.Audit.Check

  alias Oneiroi.Audit.Source

  @tag "error_site"
  @specs [:spec, :type, :typep, :opaque, :callback, :macrocallback]
  @raises [:raise, :reraise, :exit, :throw]

  @doc "The bare name a `oneiroi:allow` comment gives this check."
  @spec tag() :: String.t()
  def tag, do: @tag

  @impl Oneiroi.Audit.Check
  def run(scope) do
    # Uniqueness is a property of the whole scope, so every file is read
    # once up front for its sites, then each is checked knowing the rest.
    counts =
      scope
      |> Path.wildcard()
      |> Enum.flat_map(&sites_in/1)
      |> Enum.frequencies()

    Source.scan(scope, @tag, &violations(&1, counts))
  end

  # A file that does not parse is `Source.scan`'s to report; here it
  # simply names no sites.
  defp sites_in(path) do
    case Source.read(path) do
      {:ok, source} -> for {site, _line, _prefix} <- sites(source), do: site
      {:error, _problem} -> []
    end
  end

  @doc """
  Every `{site, line, expected_prefix}` a file builds, in source order.
  Public for the test that holds it to the shapes it must recognise.
  """
  @spec sites(Source.t()) :: [
          {atom() | {:not_literal, Macro.t()}, pos_integer(), String.t() | nil}
        ]
  def sites(source) do
    aliases = aliases(source.ast)

    source
    |> encoded()
    |> walk(false, [])
    |> Enum.flat_map(fn
      {:call, node} -> site_of(node, aliases)
      _other -> []
    end)
  end

  defp violations(source, counts) do
    aliases = aliases(source.ast)
    found = source |> encoded() |> walk(false, [])

    built =
      for {:call, node} <- found, {site, line, prefix} <- site_of(node, aliases) do
        problem_with(site, line, prefix, counts)
      end

    bare =
      for {:bare, line} <- found do
        {line,
         "an error built with no site: use a component error's new/3 (or caught/4 for a failure " <>
           "that started elsewhere) so the line can be found from the error"}
      end

    caught =
      for {:clause, kind, line, body} <- found, not handled?(body, aliases) do
        {line,
         "a #{kind} clause that names no site: wrap what it caught with caught/4, " <>
           "or raise it again"}
      end

    Enum.reject(built ++ bare ++ caught, &is_nil/1)
  end

  defp problem_with({:not_literal, _node}, line, _prefix, _counts),
    do: {line, "a site must be a literal atom, written at this line and nowhere else"}

  defp problem_with(site, line, prefix, counts) do
    name = Atom.to_string(site)

    cond do
      is_binary(prefix) and not String.starts_with?(name, prefix) ->
        {line, "site #{inspect(site)} does not start with #{prefix}, the owning component's slug"}

      Map.get(counts, site, 0) > 1 ->
        {line,
         "site #{inspect(site)} is named at #{counts[site]} lines; a site names exactly one"}

      true ->
        nil
    end
  end

  ## The walk: collects constructor calls, bare error tuples outside
  ## patterns, and rescue/catch clauses.

  defp walk({:@, _meta, [{name, _m2, _args}]}, _pattern?, acc) when name in @specs, do: acc
  defp walk({:quote, _meta, _args}, _pattern?, acc), do: acc

  defp walk({def, _meta, [head, body]}, _pattern?, acc)
       when def in [:def, :defp, :defmacro, :defmacrop] do
    acc = walk(head, true, acc)
    walk_body(body, acc)
  end

  defp walk({:->, _meta, [head, body]}, _pattern?, acc) do
    acc = walk(head, true, acc)
    walk(body, false, acc)
  end

  defp walk({op, _meta, [left, right]}, pattern?, acc) when op in [:=, :<-] do
    acc = walk(left, true, acc)
    walk(right, pattern?, acc)
  end

  defp walk({:match?, _meta, [pattern, value]}, pattern?, acc) do
    acc = walk(pattern, true, acc)
    walk(value, pattern?, acc)
  end

  defp walk({:try, _meta, [blocks]}, _pattern?, acc) when is_list(blocks),
    do: walk_body(blocks, acc)

  defp walk({:__error_tuple__, meta, [value]}, pattern?, acc) do
    acc =
      if not pattern? and bare?(value),
        do: [{:bare, Keyword.get(meta, :line, 0)} | acc],
        else: acc

    walk(value, pattern?, acc)
  end

  defp walk({form, _meta, args} = node, pattern?, acc) when is_list(args) do
    acc = if pattern?, do: acc, else: [{:call, node} | acc]
    acc = walk(form, pattern?, acc)
    Enum.reduce(args, acc, &walk(&1, pattern?, &2))
  end

  defp walk({left, right}, pattern?, acc), do: walk(right, pattern?, walk(left, pattern?, acc))

  defp walk(list, pattern?, acc) when is_list(list),
    do: Enum.reduce(list, acc, &walk(&1, pattern?, &2))

  defp walk(_leaf, _pattern?, acc), do: acc

  # A `do`/`rescue`/`catch` keyword block: `rescue` and `catch` clauses
  # are collected for the caught rule as well as walked.
  defp walk_body(blocks, acc) when is_list(blocks) do
    if Keyword.keyword?(blocks) do
      Enum.reduce(blocks, acc, fn
        {kind, clauses}, acc when kind in [:rescue, :catch] and is_list(clauses) ->
          walk(clauses, false, clauses(kind, clauses, acc))

        {_key, block}, acc ->
          walk(block, false, acc)
      end)
    else
      walk(blocks, false, acc)
    end
  end

  defp walk_body(body, acc), do: walk(body, false, acc)

  defp clauses(kind, clauses, acc) do
    for {:->, meta, [_head, body]} <- clauses, reduce: acc do
      acc -> [{:clause, kind, Keyword.get(meta, :line, 0), body} | acc]
    end
  end

  # What an error tuple holds when somebody wrote the error in place.
  defp bare?(atom) when is_atom(atom), do: true
  defp bare?(binary) when is_binary(binary), do: true
  defp bare?({:<<>>, _meta, _parts}), do: true
  defp bare?({sigil, _meta, _args}) when sigil in [:sigil_s, :sigil_S], do: true
  defp bare?({:{}, _meta, [tag | _rest]}) when is_atom(tag), do: true
  defp bare?({tag, _value}) when is_atom(tag), do: true

  defp bare?({:%, _meta, [{:__aliases__, _m2, parts}, _fields]}),
    do: List.last(parts) == :Error

  defp bare?(_value), do: false

  # The file again, with every `{:error, value}` written as a tuple
  # marked and carrying its line. A literal tuple has no metadata in the
  # ordinary AST, so a bare error could not be placed, and a keyword pair
  # (`error: x`) or a map entry has the same shape as the tuple there.
  # The literal encoder sees the braces, measured: it fires on
  # `{:error, :x}` and not on `[error: x]` or `%{error: x}`.
  # The path is one the audit's own scope glob produced, never a request
  # value; Sobelow reads any File call on a variable as a traversal.
  # sobelow_skip ["Traversal.FileModule"]
  defp encoded(%Source{path: path}) do
    encoder = fn
      {:error, value}, meta -> {:ok, {:__error_tuple__, meta, [value]}}
      literal, _meta -> {:ok, literal}
    end

    {ast, _comments} =
      path
      |> File.read!()
      |> Code.string_to_quoted_with_comments!(file: path, literal_encoder: encoder)

    ast
  end

  ## Constructor calls and their sites

  defp site_of({{:., _dot, [module, fun]}, meta, args} = _node, aliases)
       when fun in [:new, :caught] and is_list(args) do
    with {:ok, owner} <- error_module(module, aliases),
         [_kind, site | _rest]
         when (fun == :new and length(args) in 2..3) or
                (fun == :caught and length(args) in 3..4) <- args do
      [{literal(site), Keyword.get(meta, :line, 0), prefix(owner)}]
    else
      [_kind] when fun == :new ->
        [{{:not_literal, nil}, Keyword.get(meta, :line, 0), nil}]

      _other ->
        []
    end
  end

  defp site_of({:problem, meta, [_conn, _status, _kind, site, _meaning]}, _aliases),
    do: [{literal(site), Keyword.get(meta, :line, 0), "web_"}]

  defp site_of(_node, _aliases), do: []

  defp literal(site) when is_atom(site) and site not in [nil, true, false], do: site
  defp literal(other), do: {:not_literal, other}

  # `Oneiroi.<System>.Error` however this file spells it.
  defp error_module({:__aliases__, _meta, [first | rest]}, aliases) do
    full = Module.concat([Map.get(aliases, first, first) | rest])

    case Module.split(full) do
      ["Oneiroi" | middle] when middle != [] ->
        if List.last(middle) == "Error" and length(middle) >= 2, do: {:ok, full}, else: :error

      _other ->
        :error
    end
  end

  defp error_module(_module, _aliases), do: :error

  defp prefix(module) do
    module |> Module.split() |> Enum.at(1) |> Macro.underscore() |> Kernel.<>("_")
  end

  # `alias A.B.Error`, `alias A.B.Error, as: X` and `alias A.B.{Error, C}`.
  defp aliases(ast) do
    ast
    |> Source.collect(fn
      {:alias, _meta, [{:__aliases__, _m2, parts}]} ->
        [{List.last(parts), Module.concat(parts)}]

      {:alias, _meta, [{:__aliases__, _m2, parts}, [as: {:__aliases__, _m3, [short]}]]} ->
        [{short, Module.concat(parts)}]

      {:alias, _meta, [{{:., _m2, [{:__aliases__, _m3, base}, :{}]}, _m4, children}]} ->
        for {:__aliases__, _m5, child} <- children,
            do: {List.last(child), Module.concat(base ++ child)}

      _node ->
        []
    end)
    |> Map.new()
  end

  ## The caught rule

  defp handled?(body, aliases) do
    body
    |> Source.collect(fn
      {name, _meta, args} = node when is_list(args) ->
        [name in @raises or site_of(node, aliases) != []] ++ reraised?(node)

      _node ->
        []
    end)
    |> Enum.any?()
  end

  defp reraised?({{:., _dot, [:erlang, :raise]}, _meta, _args}), do: [true]
  defp reraised?(_node), do: []
end

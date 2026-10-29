defmodule Oneiroi.Nisaba.Policies.Prompts do
  @moduledoc """
  The `prompts` check (conventions §11, §13): a system prompt is a file
  under `priv/prompts/`, reviewed as a diff, and reaches a request
  through `Oneiroi.Nisaba.Prompt.message/2`. A system message built from
  a literal in the tree, as a map (`%{role: :system, content: "…"}`) or
  a keyword list (`role: :system, content: "…"`), is reported on the
  line of the map or the call it sits in.

  User and assistant messages are runtime content and are not this
  check's; the one thing it holds is that what the resident is told it
  is comes from a file somebody can read whole.

  Escape: `# oneiroi:allow prompt`, on the offending line or the comment
  line directly above it (`Oneiroi.Audit.Source`).
  """

  @behaviour Oneiroi.Audit.Check

  alias Oneiroi.Audit.Source

  @tag "prompt"

  @doc "The bare name a `oneiroi:allow` comment gives this check."
  @spec tag() :: String.t()
  def tag, do: @tag

  @impl Oneiroi.Audit.Check
  def run(scope), do: Source.scan(scope, @tag, &violations/1)

  defp violations(source) do
    source.ast
    |> Source.collect(fn
      {:%{}, _meta, pairs} = node when is_list(pairs) ->
        if literal_system?(pairs), do: [finding(node)], else: []

      {_form, meta, args} = node when is_list(meta) and is_list(args) ->
        if Enum.any?(lists_in(args), &literal_system?/1), do: [finding(node)], else: []

      _node ->
        []
    end)
    |> Enum.uniq()
  end

  defp finding(node),
    do:
      {Source.line(node),
       "a system prompt as a literal (use Oneiroi.Nisaba.Prompt.message/2 on a file under priv/prompts; conventions §11)"}

  # A call's list arguments and the lists inside them: `[role: :system, …]`
  # as the argument, or one element of a `messages` list.
  defp lists_in(args) do
    Enum.flat_map(args, fn
      list when is_list(list) -> [list | Enum.filter(list, &is_list/1)]
      _other -> []
    end)
  end

  defp literal_system?(pairs) do
    Enum.any?(pairs, &match?({:role, :system}, &1)) and
      Enum.any?(pairs, fn
        {:content, text} when is_binary(text) -> true
        {:content, {:<<>>, _meta, _parts}} -> true
        _other -> false
      end)
  end
end

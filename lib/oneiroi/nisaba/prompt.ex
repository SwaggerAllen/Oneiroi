defmodule Oneiroi.Nisaba.Prompt do
  @moduledoc """
  Prompts are files (conventions §11): every system prompt lives under
  `priv/prompts/<name>.md`, reviewed as a diff, and reaches a request
  through `message/1` and nothing else. The `prompts` check reports a
  system message built from a literal anywhere in the tree.

  `{{key}}` placeholders are filled from `assigns`; a placeholder left
  unfilled is an error rather than a blank, because a prompt with a hole
  in it is a prompt that says something nobody reviewed.
  """

  # A prompt name is a slug, so the path it joins to cannot leave the
  # directory; the read below is of a file this repository ships, named
  # by code and never by a request, which is why the traversal finding
  # on it is skipped rather than guarded twice.
  @name ~r/\A[a-z0-9][a-z0-9_-]*\z/

  @doc "The prompt file's text, with `assigns` filled in."
  @spec render!(String.t(), map()) :: String.t()
  # sobelow_skip ["Traversal.FileModule"]
  def render!(name, assigns \\ %{}) when is_binary(name) and is_map(assigns) do
    unless Regex.match?(@name, name),
      do: raise(ArgumentError, "prompt names are slugs, got #{inspect(name)}")

    text = File.read!(path(name))
    # Keyed by string rather than atomising the placeholder: a prompt
    # file is not a place to mint atoms from.
    values = Map.new(assigns, fn {key, value} -> {Atom.to_string(key), value} end)

    rendered =
      Regex.replace(~r/\{\{(\w+)\}\}/, text, fn whole, key ->
        case Map.fetch(values, key) do
          {:ok, value} -> to_string(value)
          :error -> whole
        end
      end)

    case Regex.run(~r/\{\{(\w+)\}\}/, rendered) do
      nil -> rendered
      [_, key] -> raise ArgumentError, "prompt #{name} has no value for {{#{key}}}"
    end
  end

  @doc "The system message for a prompt file: what a request's `messages` opens with."
  @spec message(String.t(), map()) :: %{role: :system, content: String.t()}
  def message(name, assigns \\ %{}), do: %{role: :system, content: render!(name, assigns)}

  @doc "Where a named prompt lives."
  @spec path(String.t()) :: String.t()
  def path(name), do: Path.join(:code.priv_dir(:oneiroi), "prompts/#{name}.md")
end

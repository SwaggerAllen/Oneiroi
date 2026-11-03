defmodule Oneiroi.Brain.Uses do
  @moduledoc """
  What retrieval did with each target in a turn, read off what the turn
  already holds (the resident's work order, 2026-11-02; spec §6.3's
  F11 is weighted from it): the sections it was given, the tools it
  called and what it cited. Pure: the turn records the list once
  (`Oneiroi.Kumbukumbu.record_retrieval/5`).

  A use is `%{target, stage, via}`. The target is in citation form
  without the slug (`bookmark/42`, `writing/the-bake-off`, `keepsake/
  pocket-andrew`, `transcript/<key>`, `habit/3`, `commitment/1`), so
  every kind of edge is counted the same way and a later weighting can
  tune any of them. The stages:

  - `considered`: the memory agent ranked it (the index's every ranked
    bookmark, near-misses included; each search hit).
  - `returned`: it was put in front of the brain (injected, or handed
    back by a search or a list).
  - `used`: the brain acted on it (opened or read it, or cited it in a
    reply or a document it wrote).

  Measurement only. Nothing here weighs anything, and the counts are the
  resident's to read before any weighting is tuned from them.
  """

  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Citations

  @type use :: %{target: String.t(), stage: String.t(), via: String.t()}

  # A section's refs, by its label, as the kind they number; the index's
  # are counted with its near-misses below. `movement`'s refs are turn
  # refs, which have no citation form of their own yet.
  @section_kinds %{"madeleine" => "bookmark", "character" => "habit", "promised" => "commitment"}

  @doc "The uses a turn's sections record: what the index ranked and listed, and what each other section carried."
  @spec from_injections([map()]) :: [use()]
  def from_injections(injections) when is_list(injections) do
    Enum.flat_map(injections, fn inj ->
      label = field(inj, :label)
      refs = inj |> field(:refs) |> List.wrap()

      case label do
        # The ranked index (kumbukumbu #46): the ranked are considered and
        # returned; the explored were drawn, not ranked, so returned
        # through `explored` alone; the seed is recorded as `seed`, what
        # the learned edges are read from and written from.
        "index" ->
          explored = inj |> field(:explored) |> List.wrap()
          seeds = inj |> field(:seeds) |> List.wrap()

          Enum.flat_map(refs -- explored, &both("bookmark/#{&1}", "index")) ++
            Enum.map(explored, &use("bookmark/#{&1}", "returned", "explored")) ++
            Enum.map(seeds, &use("bookmark/#{&1}", "seed", "index"))

        "near-miss" ->
          inj
          |> field(:considered)
          |> List.wrap()
          |> Enum.map(&use("bookmark/#{&1}", "considered", "index"))

        label when is_map_key(@section_kinds, label) ->
          kind = @section_kinds[label]
          Enum.flat_map(refs, &both("#{kind}/#{&1}", label))

        _other ->
          []
      end
    end)
  end

  @doc """
  The uses a tool call records, from its name, its arguments and what it
  answered. A call that did not do it ("Not done: ...") records nothing.
  """
  @spec from_call(String.t(), map(), String.t(), String.t() | nil) :: [use()]
  def from_call(_name, _args, "Not done" <> _, _slug), do: []

  def from_call("bookmark_open", args, _output, _slug) do
    case integer(args["number"]) do
      nil -> []
      n -> [use("bookmark/#{n}", "used", "bookmark_open")]
    end
  end

  def from_call("library_read", args, _output, slug),
    do:
      args["path"]
      |> document_target(slug)
      |> List.wrap()
      |> Enum.map(&use(&1, "used", "library_read"))

  def from_call("writing_get", args, _output, _slug) do
    case to_string(args["slug"] || "") do
      "" -> []
      s -> [use("writing/#{Path.rootname(s, ".md")}", "used", "writing_get")]
    end
  end

  def from_call("library_cited_by", args, _output, slug),
    do:
      args["target"]
      |> cited_target(slug)
      |> List.wrap()
      |> Enum.map(&use(&1, "used", "library_cited_by"))

  # Each line of the list is an index line, `#<number> ...`.
  def from_call("bookmark_list", _args, output, _slug) do
    ~r/^#(\d+) /m
    |> Regex.scan(output, capture: :all_but_first)
    |> Enum.map(fn [n] -> use("bookmark/#{n}", "returned", "bookmark_list") end)
  end

  # Each hit names its document as `[<path>] passage ...`; a document
  # with several passages among the hits is one target, counted once.
  def from_call("library_search", _args, output, slug) do
    ~r/^\[([^\]]+)\] passage /m
    |> Regex.scan(output, capture: :all_but_first)
    |> Enum.map(fn [path] -> document_target(path, slug) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.flat_map(&both(&1, "library_search"))
  end

  # Each hit is `[<session>/<turn>] role: ...`; a session is the target.
  def from_call("transcript_search", _args, output, _slug) do
    ~r/^\[([^\/\]]+)\/[^\]]+\] /m
    |> Regex.scan(output, capture: :all_but_first)
    |> Enum.map(fn [key] -> "transcript/#{key}" end)
    |> Enum.uniq()
    |> Enum.flat_map(&both(&1, "transcript_search"))
  end

  # What a document written through the flow cites is used by writing it.
  def from_call("document_write", args, _output, slug),
    do: cited(to_string(args["content"] || ""), slug, "document_write")

  def from_call(_name, _args, _output, _slug), do: []

  @doc "What a reply cites of the resident's own records: each one used, through the reply."
  @spec from_reply(String.t(), String.t() | nil) :: [use()]
  def from_reply(text, slug) when is_binary(text), do: cited(text, slug, "reply")
  def from_reply(_text, _slug), do: []

  defp cited(_text, nil, _via), do: []

  defp cited(text, slug, via) do
    text
    |> Citations.extract()
    |> Enum.filter(&(&1.slug == slug))
    |> Enum.map(&use(target(&1.kind, &1.ref), "used", via))
    |> Enum.uniq()
  end

  # A document named the way library_read takes it: a path (with or
  # without a `#passage`), or a citation of the resident's own slug.
  defp document_target(name, slug) do
    name = to_string(name || "") |> String.trim()

    case cited_target(name, slug) do
      nil -> path_target(name |> String.split("#", parts: 2) |> hd())
      target -> target
    end
  end

  defp cited_target(name, slug) do
    case Citations.extract(to_string(name || "")) do
      [%{slug: ^slug, kind: kind, ref: ref}] -> target(kind, ref)
      _other -> nil
    end
  end

  defp path_target(path) do
    case Seshat.Kinds.kind_of(path) do
      %{kind: "keepsake"} ->
        "keepsake/" <> Path.rootname(path)

      %{kind: kind, folder: folder} ->
        "#{kind}/" <> (path |> String.replace_prefix(folder <> "/", "") |> strip_text())

      nil ->
        nil
    end
  end

  defp target(kind, ref),
    do: "#{kind}/" <> (ref |> String.split("#", parts: 2) |> hd() |> strip_text())

  defp strip_text(ref) do
    if Seshat.Kinds.text?(ref), do: Path.rootname(ref), else: ref
  end

  defp both(target, via), do: [use(target, "considered", via), use(target, "returned", via)]
  defp use(target, stage, via), do: %{target: target, stage: stage, via: via}

  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp integer(_other), do: nil
end

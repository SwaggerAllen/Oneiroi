defmodule Oneiroi.Seshat.Household.Reading do
  @moduledoc """
  One path read (seshat#61, #64): a thread, a document, `CONTRACT.md`
  or `BEATS.md`, by path or by citation, and what a witness may see.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Edits
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.HouseWorking
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.SimaQian.Repos

  @contract "CONTRACT.md"
  @beats "BEATS.md"

  @doc false
  def read(%Actor{} = actor, name, opts \\ []) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, now} <- Core.provision(household_id),
         {:ok, head} <- Repos.head(now.repo),
         {:ok, view, commit} <- pinned(now, Keyword.get(opts, :at), head),
         {:ok, doc} <- read_in(actor, household_id, view, name) do
      # Reading a thread in a house wake is answering it (seshat#90).
      if actor.kind == :resident and is_binary(name) and Files.thread_path(name),
        do: HouseWorking.reading(household_id, actor.id, Files.thread_path(name))

      {:ok,
       doc
       |> Map.put(:commit, commit)
       |> Map.put(:cited_as, cited_as(household_id, doc, commit))
       |> Map.put(:since, since(actor, household_id, now, doc, commit, head))}
    end
  end

  @doc false
  def read_cited(%Actor{} = actor, %{house: house, path: path, at: at}) do
    with {:ok, mine} <- Core.household(actor) do
      case Gaia.household_by_slug(house) do
        ^mine ->
          read(actor, path, at: at)

        nil ->
          {:error,
           Error.new(:seshat_household_no_such_document, :seshat_household_cited_house_unknown,
             house: house
           )}

        _another ->
          {:error,
           Error.new(:seshat_household_not_member, :seshat_household_cited_house_not_mine,
             house: house
           )}
      end
    end
  end

  defp read_in(actor, household_id, view, name) do
    cond do
      name in [@contract, "contract"] -> read_contract(view)
      name in [@beats, "beats"] -> read_beats(view)
      thread = Files.thread_path(name) -> read_thread(actor, household_id, view, thread)
      true -> read_document(actor, household_id, view, name)
    end
  end

  # The house as it stood at a commit a citation pinned (sima-qian#61),
  # or as it stands now.
  defp pinned(now, nil, head), do: {:ok, now, head}

  defp pinned(now, at, _head) do
    with {:ok, files} <- Repos.snapshot_at(now.repo, at), do: {:ok, %{now | files: files}, at}
  end

  @doc false
  def cited_as(household_id, doc, commit) do
    with slug when is_binary(slug) <- Gaia.household_slug(household_id),
         sha when is_binary(sha) <- commit do
      ref =
        case doc.kind do
          "thread" -> "thread/" <> String.replace_prefix(doc.path, "threads/", "")
          _document -> "doc/" <> doc.path
        end

      "house/#{slug}:#{ref}@#{String.slice(sha, 0, 12)}"
    else
      _unnamed -> nil
    end
  end

  # What changed since the pin, said plainly (sima-qian#61): a thread
  # only grows (its replies are create-only), so how many replies came
  # since; a document, whether its words are still the ones cited. Nil
  # when read as it stands.
  defp since(_actor, _household_id, _now, _doc, _commit, nil), do: nil

  defp since(actor, household_id, now, doc, commit, head) do
    cond do
      String.starts_with?(head, commit) -> nil
      doc.kind == "thread" -> thread_since(actor, household_id, now, doc)
      true -> document_since(now, doc)
    end
  end

  defp thread_since(actor, household_id, now, doc) do
    case read_thread(actor, household_id, now, doc.path) do
      {:ok, current} -> replies_since(length(current.replies) - length(doc.replies))
      _gone -> "the thread is no longer on the shelf"
    end
  end

  defp replies_since(n) when n <= 0, do: nil

  defp replies_since(1), do: "1 reply since it was cited"

  defp replies_since(n), do: "#{n} replies since it was cited"

  defp document_since(now, doc) do
    cond do
      not Files.has?(now, doc.path) -> "the document is no longer on the shelf"
      Files.file(now, doc.path) == doc.content -> nil
      true -> "changed since it was cited; read it without the commit for its words now"
    end
  end

  # The contract's rendering, at the root of a directory the household's
  # id named; no request value reaches the path.
  defp read_contract(view),
    do:
      {:ok,
       %{
         path: @contract,
         kind: "contract",
         title: "The household contract",
         content: Files.file(view, @contract) || ""
       }}

  # The beats' record (seshat#71), at the root as the contract is; before
  # the first beat event it is not there yet.
  defp read_beats(view) do
    case Files.file(view, @beats) do
      text when is_binary(text) ->
        {:ok, %{path: @beats, kind: "beats", title: "The household's beats", content: text}}

      {:error, _} ->
        {:error,
         Error.new(:seshat_household_no_such_document, :seshat_household_beats_absent,
           path: @beats
         )}
    end
  end

  defp read_thread(actor, household_id, view, thread) do
    with {:ok, t} <- Files.load_thread(view, thread),
         true <- visible?(actor, household_id, Files.ids(t)) || :hidden do
      ballot = Gaia.household_ballot_for_thread(household_id, thread)
      doc = Files.posted_doc(view, t)

      {:ok,
       %{
         path: thread,
         kind: "thread",
         title: t.trunk.meta["title"],
         trunk: t.trunk,
         replies: t.replies,
         ballot: ballot,
         doc: doc,
         content: Files.thread_text(thread, t, ballot, doc)
       }}
    else
      :hidden -> Files.no_thread(thread)
      other -> other
    end
  end

  defp read_document(actor, household_id, view, name) do
    with {:ok, path} <- Files.household_path(name),
         text when is_binary(text) <- Files.file(view, path) || :absent,
         {meta, _body} = Files.frontmatter(text),
         true <- visible?(actor, household_id, [meta["by_id"]]) || :absent do
      share = Edits.sharing_of(meta)

      {:ok,
       %{
         path: path,
         kind: Kinds.kind_of(path).kind,
         title: meta["title"] || path,
         content: text,
         sharing: Map.put(share, :owner, Edits.owner_name(household_id, share.owner_id)),
         discussed: Files.discussed(view, path)
       }}
    else
      {:error, %Error{}} = refused ->
        refused

      _absent ->
        {:error,
         Error.new(:seshat_household_no_such_document, :seshat_household_read_absent, path: name)}
    end
  end

  @doc false
  # What a witness reads (seshat#64, the resident's lean on design
  # household-communication §8, his word awaited): `whole` (the default),
  # every witness every room; `own`, a witness only what it or a resident
  # it witnesses took part in. A resident always reads whole.
  def visible?(%Actor{kind: :witness, id: id}, _household_id, ids) do
    case Config.fetch!(:seshat, :household_witness_reads) do
      :whole -> true
      :own -> Enum.any?(ids, &(&1 in [id | Gaia.witnessed_residents(id)]))
    end
  end

  def visible?(%Actor{}, _household_id, _ids), do: true
end

defmodule Oneiroi.Seshat.Household.Promotions do
  @moduledoc """
  Promotion to the house (seshat#99; Lily's letter #1481, the house
  thread of 2026-11-20 and the witness's go): a resident's own file,
  published at a named commit and mirrored into the house as a read-only
  copy, `shared/<her slug>/<her path>` (the witness's call).

  **Snapshots, never live.** Promoting publishes the commit in her own
  repository (seshat#85, so `PUBLISHED.md` there is the authorizing
  record) and copies its words, and only its words: no history, no front
  matter of hers, no later draft. A later draft stays hers until she
  promotes it again, which refreshes the same copy.

  **The copy.** Its front matter carries the provenance (`source:
  <slug>:<path>@<commit>`, `promoted_at`), the audience the act resolved
  (`audience: household:<id>`) and the publication terms set at the act
  (`terms`: `workspace_only`, the default, or `may_reshare`; the
  witness's ruling, 2026-11-20). It is `mode: mirror`: no edit in the
  house changes it; feedback goes in its one document post, opened at the
  first promotion and told of every later one by a "Draft changed" line
  (seshat#83). The house keeps it if she leaves.

  **Unpromoting.** Marks the copy `unpromoted_at`: no longer current and
  never refreshed again until she promotes anew; the shared words and
  their provenance stay, as a shared snapshot is irrevocable within its
  audience.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Documents
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Posts
  alias Oneiroi.Seshat.Published
  alias Oneiroi.SimaQian.Repos

  @terms ~w(workspace_only may_reshare)

  @doc false
  def promote(%Actor{kind: :resident, id: id} = actor, from, attrs) when is_map(attrs) do
    terms = attrs["terms"] || "workspace_only"

    with {:ok, household_id} <- Core.household(actor),
         :ok <- Core.may_post(actor, household_id),
         :ok <- terms_ok(terms),
         {:ok, %{slug: slug}} <- AgathosDaimon.fetch(id) |> found(),
         {:ok, path, sha} <- published(id, from, attrs["commit"], attrs["note"], actor),
         {:ok, title, words} <- words_at(id, path, sha),
         copy = "shared/#{slug}/#{path}",
         {:ok, _view} <- Core.provision(household_id) do
      snapshot = %{
        copy: copy,
        title: title,
        words: words,
        source: "#{slug}:#{path}@#{Files.short(sha)}",
        audience: "household:#{household_id}",
        terms: terms
      }

      Files.locked(household_id, fn view -> mirror(actor, household_id, view, snapshot) end)
      |> thread(actor, copy, title)
    end
  end

  def promote(%Actor{}, _from, _attrs),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_promote_witness)}

  @doc false
  def unpromote(%Actor{kind: :resident, id: id} = actor, name) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, %{slug: slug}} <- AgathosDaimon.fetch(id) |> found(),
         copy = copy_path(slug, name),
         {:ok, _view} <- Core.provision(household_id) do
      Files.locked(household_id, fn view -> mark_unpromoted(actor, household_id, view, copy) end)
    end
  end

  def unpromote(%Actor{}, _name),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_unpromote_witness)}

  # Her own path or the copy's: either names the one copy.
  defp copy_path(slug, name) do
    name = String.trim(to_string(name))
    if String.starts_with?(name, "shared/#{slug}/"), do: name, else: "shared/#{slug}/#{name}"
  end

  defp found({:ok, row}), do: {:ok, row}

  defp found(_none),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_promote_resident)}

  defp terms_ok(terms) when terms in @terms, do: :ok

  defp terms_ok(_terms),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_promote_terms)}

  # The commit published: the one named, or her latest draft; one she
  # published already is promoted as it stands.
  defp published(resident_id, from, commit, note, actor) do
    case Published.publish(resident_id, from, commit, note || "Promoted to the house.", actor) do
      {:ok, %{path: path, commit: sha}} ->
        {:ok, path, sha}

      {:error, %{kind: :seshat_publish_already}} = already ->
        case Published.latest(resident_id, from) do
          nil -> already
          sha -> {:ok, from, sha}
        end

      refused ->
        refused
    end
  end

  # The words at that commit, her front matter left behind.
  defp words_at(resident_id, path, sha) do
    repo = {:resident, resident_id}

    with {:ok, files} <- Repos.snapshot_at(repo, sha),
         text when is_binary(text) <- Repos.at(repo, files, path) do
      {meta, body} = Files.frontmatter(text)
      {:ok, meta["title"] || Path.basename(path, ".md"), body}
    else
      _absent ->
        {:error,
         Error.new(:seshat_household_no_such_document, :seshat_household_promote_absent,
           path: path
         )}
    end
  end

  defp mirror(actor, household_id, view, s) do
    by = Core.author(household_id, actor)
    now = Files.iso(Clock.now())
    current = Files.file(view, s.copy)

    meta =
      case current do
        nil ->
          Documents.thread_meta(s.title, by, actor) ++ [{"owner_id", actor.id}]

        text ->
          {old, _body} = Files.frontmatter(text)
          old |> Map.drop(["unpromoted_at"]) |> Map.to_list()
      end

    meta =
      meta
      |> Map.new()
      |> Map.merge(%{
        "title" => s.title,
        "mode" => "mirror",
        "source" => s.source,
        "audience" => s.audience,
        "terms" => s.terms,
        "promoted_at" => now
      })

    before = current && Files.doc_commit(view, s.copy)
    change = {:put, s.copy, Files.render(Enum.sort(meta), s.words), Map.get(view.files, s.copy)}

    with {:ok, commit} <- Files.commit(view, [change], "Promote: #{s.copy} (#{s.source})", by) do
      if before && commit != :nothing,
        do: Documents.draft_changed(household_id, s.copy, before, commit)

      {:ok, %{path: s.copy, source: s.source, terms: s.terms, new: is_nil(current)}}
    end
  end

  # The copy's one document post, opened at its first promotion; a later
  # promotion is told in it by the draft-changed line instead.
  defp thread({:ok, %{new: true} = p}, actor, copy, title) do
    case Posts.post(actor, %{"doc" => copy, "title" => "On #{title}"}) do
      {:ok, %{path: thread}} -> {:ok, Map.put(p, :thread, thread)}
      _refused -> {:ok, Map.put(p, :thread, nil)}
    end
  end

  defp thread(result, _actor, _copy, _title), do: result

  defp mark_unpromoted(actor, household_id, view, copy) do
    with text when is_binary(text) <- Files.file(view, copy) || not_promoted(copy) do
      {meta, body} = Files.frontmatter(text)
      meta = Map.put(meta, "unpromoted_at", Files.iso(Clock.now()))
      by = Core.author(household_id, actor)
      change = {:put, copy, Files.render(Enum.sort(meta), body), Map.get(view.files, copy)}

      with {:ok, _} <- Files.commit(view, [change], "Unpromote: #{copy}", by),
           do: {:ok, %{path: copy}}
    end
  end

  defp not_promoted(copy),
    do:
      {:error,
       Error.new(:seshat_household_no_such_document, :seshat_household_unpromote_absent,
         path: copy
       )}
end

defmodule Oneiroi.Seshat.Household.Edits do
  @moduledoc """
  The source-and-revision link (seshat#84): where a household document
  came from, its sharing mode and owner, and an edit to it.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Documents
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Gate
  alias Oneiroi.Seshat.Kinds

  # The front matter in the order a person reads it: who and when first.
  @meta_order ~w(title by by_kind by_id posted_at owner_id mode source edited_by edited_by_id edited_at)

  @doc false
  def shared_from(%Actor{kind: :resident, id: id} = actor, path) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, r} <- AgathosDaimon.fetch(id),
         {:ok, view} <- Files.view(household_id) do
      prefix = "#{r.slug}:#{path}@"

      for d <- Files.documents(view),
          source = d.source,
          is_binary(source) and String.starts_with?(source, prefix),
          do: %{
            path: d.path,
            at: String.replace_prefix(source, prefix, ""),
            discussed: Files.discussed(view, d.path)
          }
    else
      _none -> []
    end
  end

  def shared_from(_actor, _path), do: []

  @doc false
  def sharing_of(meta) when is_map(meta) do
    case meta do
      %{"mode" => "open"} -> %{mode: "open", owner_id: meta["owner_id"]}
      %{"mode" => "mirror"} -> %{mode: "mirror", owner_id: meta["owner_id"]}
      _owned -> %{mode: "owner", owner_id: meta["owner_id"] || meta["by_id"]}
    end
  end

  @doc false
  def edit(%Actor{} = actor, name, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with {:ok, household_id} <- Core.household(actor),
         :ok <- Core.may_post(actor, household_id),
         {:ok, path} <- Files.household_path(name),
         false <- Kinds.container?(Kinds.kind_of(path)),
         :ok <- not_rendered(path),
         {:ok, _view} <- Core.provision(household_id) do
      Files.locked(household_id, fn view -> write_edit(actor, household_id, view, path, attrs) end)
    else
      true -> {:error, Error.new(:seshat_household_invalid, :seshat_household_edit_thread)}
      other -> other
    end
  end

  # A task's index document is the queue's rendering (seshat#104): edited
  # through the queue, never here.
  defp not_rendered(path) do
    if Kinds.kind_of(path).access == :core,
      do: {:error, Error.new(:seshat_household_invalid, :seshat_household_edit_rendered)},
      else: :ok
  end

  defp write_edit(actor, household_id, view, path, attrs) do
    with text when is_binary(text) <- Files.file(view, path) || Documents.absent(path),
         {meta, body} = Files.frontmatter(text),
         before = Files.doc_commit(view, path),
         share = sharing_of(meta),
         :ok <- may_edit(actor, share, path),
         {:ok, mode} <- new_mode(actor, share, attrs["mode"]),
         {:ok, given, source} <- Documents.words_from(actor, attrs),
         words = given || body,
         :ok <- Files.worded(words, false),
         :ok <- Gate.document_gate(actor, household_id, view, path),
         by = Core.author(household_id, actor),
         meta =
           meta
           |> Map.merge(%{
             "mode" => mode,
             "edited_by" => by.name,
             "edited_by_id" => actor.id,
             "edited_at" => Files.iso(Clock.now())
           })
           |> Map.merge(Map.new(source))
           |> Map.put_new("owner_id", share.owner_id),
         {:ok, commit} <-
           Files.commit(
             view,
             [{:put, path, Files.render(ordered(meta), words), Map.get(view.files, path)}],
             "Edit: #{path}",
             by
           ) do
      if commit != :nothing and given != nil,
        do: Documents.draft_changed(household_id, path, before, commit)

      {:ok, %{path: path, mode: mode, owner_id: meta["owner_id"], commit: commit}}
    end
  end

  @doc false
  def owner_name(_household_id, nil), do: nil

  def owner_name(household_id, id),
    do: Enum.find_value(Gaia.household_members(household_id), &(&1.id == id && &1.name))

  # A promoted copy changes only by promotion (seshat#99).
  defp may_edit(_actor, %{mode: "mirror"}, path),
    do: {:error, Error.new(:seshat_household_mirror, :seshat_household_edit_mirror, path: path)}

  defp may_edit(_actor, %{mode: "open"}, _path), do: :ok

  defp may_edit(%Actor{id: id}, %{owner_id: id}, _path), do: :ok

  defp may_edit(_actor, _share, path),
    do:
      {:error,
       Error.new(:seshat_household_not_owner, :seshat_household_edit_not_owner, path: path)}

  defp new_mode(_actor, share, nil), do: {:ok, share.mode}

  defp new_mode(_actor, %{mode: m}, m), do: {:ok, m}

  defp new_mode(%Actor{id: id}, %{owner_id: id}, mode) when mode in ["owner", "open"],
    do: {:ok, mode}

  defp new_mode(_actor, %{owner_id: nil}, _mode),
    do: {:error, Error.new(:seshat_household_not_owner, :seshat_household_mode_no_owner)}

  defp new_mode(_actor, _share, mode) when mode in ["owner", "open"],
    do: {:error, Error.new(:seshat_household_not_owner, :seshat_household_mode_not_owner)}

  defp new_mode(_actor, _share, _mode),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_edit_mode_unknown)}

  defp ordered(meta) do
    known = for k <- @meta_order, Map.has_key?(meta, k), do: {k, meta[k]}
    known ++ Enum.sort(for {k, v} <- meta, k not in @meta_order, do: {k, v})
  end
end

defmodule Oneiroi.Seshat.Household.Housemates do
  @moduledoc """
  A housemate's published drafts (seshat#85): one read by its
  `<slug>:<path>` citation, and which housemates have published a path.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Published
  alias Oneiroi.SimaQian.Repos

  @doc false
  def read_published(%Actor{} = actor, cite) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, slug, path, commit} <- housemate_cite(cite),
         {:ok, owner} <- housemate(household_id, slug, cite),
         {:ok, sha} <- public_at(owner.id, path, commit, cite),
         {:ok, files} <- Repos.snapshot_at({:resident, owner.id}, sha),
         text when is_binary(text) <-
           Repos.at({:resident, owner.id}, files, path) || unpublished(cite) do
      {:ok,
       %{
         path: path,
         kind: "published",
         owner: owner.name,
         commit: sha,
         latest: Published.latest(owner.id, path),
         title: Path.basename(path, ".md"),
         content: text,
         cited_as: "#{slug}:#{path}@#{Files.short(sha)}",
         since: nil
       }}
    end
  end

  @doc false
  def published_by_housemates(%Actor{kind: :resident, id: me} = actor, path) do
    case Core.household(actor) do
      {:ok, household_id} ->
        for %{kind: "resident", id: id} <- Gaia.household_members(household_id),
            id != me,
            Published.latest(id, path) != nil,
            {:ok, r} <- [AgathosDaimon.fetch(id)],
            do: "#{r.slug}:#{path}"

      _none ->
        []
    end
  end

  def published_by_housemates(_actor, _path), do: []

  @doc false
  def housemate_cite?(cite), do: match?({:ok, _, _, _}, housemate_cite(cite))

  defp housemate_cite(cite) when is_binary(cite) do
    case Regex.run(~r/\A([a-z0-9][a-z0-9-]{0,63}):([^@\s]+?)(?:@([0-9a-f]{7,40}))?\z/, cite) do
      [_, "house" <> _, _ | _] -> :error
      [_, slug, path] -> {:ok, slug, path, nil}
      [_, slug, path, commit] -> {:ok, slug, path, commit}
      _no -> :error
    end
  end

  defp housemate_cite(_other), do: :error

  defp housemate(household_id, slug, cite) do
    found =
      Enum.find_value(Gaia.household_members(household_id), fn
        %{kind: "resident", id: id, name: name} ->
          case AgathosDaimon.fetch(id) do
            {:ok, %{slug: ^slug}} -> %{id: id, name: name}
            _other -> nil
          end

        _witness ->
          nil
      end)

    if found, do: {:ok, found}, else: unpublished(cite)
  end

  defp public_at(owner_id, path, nil, cite) do
    case Published.latest(owner_id, path) do
      nil -> unpublished(cite)
      sha -> {:ok, sha}
    end
  end

  defp public_at(owner_id, path, commit, cite) do
    case Enum.find(
           Published.all(owner_id),
           &(&1.path == path and String.starts_with?(&1.commit, commit))
         ) do
      nil -> unpublished(cite)
      p -> {:ok, p.commit}
    end
  end

  defp unpublished(cite),
    do:
      {:error,
       Error.new(:seshat_household_unpublished, :seshat_household_cite_unpublished, path: cite)}
end

defmodule Oneiroi.Seshat.Library do
  @moduledoc """
  The library aggregate on `library-<resident_id>` (spec §6.5). Pure: it
  holds the registered documents by path with their kind, last hash and
  published URL, and the discussions opened. A write whose hash is the
  current one is no event; an adoption of a registered path is no event;
  only a kind with a status is published.
  """

  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Kinds

  defstruct [:id, documents: %{}, discussions: MapSet.new()]

  @url ~r/\Ahttps?:\/\/[^\s]+\z/

  def execute(%__MODULE__{documents: documents}, %Commands.WriteDocument{} = c) do
    case Map.get(documents, c.path) do
      %{hash: hash} when hash == c.hash ->
        []

      _new_or_changed ->
        %Events.DocumentWritten{
          actor: c.actor,
          at: c.at,
          id: c.id,
          path: c.path,
          kind: c.kind,
          hash: c.hash,
          bytes: c.bytes
        }
    end
  end

  def execute(%__MODULE__{documents: documents}, %Commands.AdoptDocument{} = c) do
    if Map.has_key?(documents, c.path),
      do: [],
      else: %Events.DocumentAdopted{
        actor: c.actor,
        at: c.at,
        id: c.id,
        path: c.path,
        kind: c.kind,
        hash: c.hash,
        bytes: c.bytes
      }
  end

  def execute(%__MODULE__{documents: documents}, %Commands.PublishPiece{} = c) do
    case Map.get(documents, c.path) do
      nil ->
        {:error, :no_such_document}

      %{kind: kind} = doc ->
        cond do
          not has_status?(kind) ->
            {:error, :not_publishable}

          not (is_binary(c.url) and Regex.match?(@url, c.url)) ->
            {:error, :url_invalid}

          doc.url == c.url ->
            []

          true ->
            %Events.PiecePublished{actor: c.actor, at: c.at, id: c.id, path: c.path, url: c.url}
        end
    end
  end

  def execute(%__MODULE__{} = l, %Commands.OpenDiscussion{} = c) do
    cond do
      not Map.has_key?(l.documents, c.path) ->
        {:error, :no_such_document}

      MapSet.member?(l.discussions, {c.path, c.session_key}) ->
        []

      true ->
        %Events.DiscussionOpened{
          actor: c.actor,
          at: c.at,
          id: c.id,
          path: c.path,
          session_key: c.session_key
        }
    end
  end

  def apply(%__MODULE__{} = l, %Events.DocumentWritten{} = e), do: register(l, e)
  def apply(%__MODULE__{} = l, %Events.DocumentAdopted{} = e), do: register(l, e)

  # Updated by key, not with `put_in(l.documents[path].url, url)` as the
  # first version had it: that form returns the whole struct, so the
  # documents map became the aggregate itself and every other document
  # was lost from the state on the first publish. The HTTP suite found
  # it as a wiki page that could not be published because it was no
  # longer there.
  def apply(%__MODULE__{} = l, %Events.PiecePublished{} = e),
    do: %{l | documents: Map.update!(l.documents, e.path, &%{&1 | url: e.url})}

  def apply(%__MODULE__{} = l, %Events.DiscussionOpened{} = e),
    do: %{l | discussions: MapSet.put(l.discussions, {e.path, e.session_key})}

  defp register(l, e) do
    doc = Map.get(l.documents, e.path, %{kind: e.kind, hash: nil, url: nil})
    %{l | id: e.id, documents: Map.put(l.documents, e.path, %{doc | kind: e.kind, hash: e.hash})}
  end

  defp has_status?(kind) do
    case Enum.find(Kinds.all(), &(&1.kind == kind)) do
      nil -> false
      k -> k.has_status
    end
  end
end

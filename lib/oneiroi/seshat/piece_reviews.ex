defmodule Oneiroi.Seshat.PieceReviews do
  @moduledoc """
  The writing gate's service (seshat#42): what waits for the witness's
  review, his decision, what waits for the reader, and the reader's two
  reports, the Substack draft it made and the URL once the witness
  published it.

  A piece waits for review while its frontmatter says `status: review`
  and the witness has not decided this version (its hash): a declined
  piece she rewrites and marks for review again comes back.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.PiecesRouter
  alias Oneiroi.Seshat.Store

  @doc "The pieces waiting on the witness, and those on their way out: for review, approved (the reader drafts), drafted (he publishes)."
  def pieces(resident_id) do
    docs = Documents.list(resident_id)
    reviews = reviews(resident_id)

    for_review =
      for d <- docs,
          d.kind == "writing" and d.status == "review",
          not decided?(reviews[d.path], d.hash),
          do: %{
            path: d.path,
            title: d.title,
            written_at: d.written_at,
            last: last(reviews[d.path])
          }

    %{
      for_review: for_review,
      approved: out_in(reviews, docs, "approved"),
      drafted: out_in(reviews, docs, "drafted")
    }
  end

  @doc "The witness approves or declines the version of the piece he read, with a note."
  def review(resident_id, path, decision, note, %Actor{} = actor) do
    with %{} = doc <- Enum.find(Documents.list(resident_id), &(&1.path == path)) || none(path) do
      dispatch(%Commands.ReviewPiece{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        path: path,
        decision: decision,
        note: note,
        hash: doc.hash
      })
    end
  end

  @doc "What waits for the reader: approved pieces to draft, with their title and copy, and drafted ones to watch for publication."
  def for_reader(resident_id) do
    %{approved: approved, drafted: drafted} = pieces(resident_id)

    to_draft =
      for p <- approved,
          {:ok, body} <- [Citations.publish_copy(resident_id, p.path)],
          do: %{path: p.path, title: p.title, body: body}

    %{
      to_draft: to_draft,
      to_watch: for(p <- drafted, do: %{path: p.path, title: p.title, draft_url: p.draft_url})
    }
  end

  @doc "The reader made the Substack draft."
  def drafted(resident_id, path, draft_url, %Actor{} = actor),
    do:
      dispatch(%Commands.DraftPiece{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        path: path,
        draft_url: draft_url
      })

  @doc "The reader found the drafted piece published at a URL: recorded as published, the frontmatter given the URL."
  def published(resident_id, path, url, %Actor{} = actor) do
    case reviews(resident_id)[path] do
      %{state: "drafted"} -> Documents.record_published(resident_id, path, url, actor)
      _other -> {:error, Error.new(:seshat_not_approved, :seshat_pieces_published_not_drafted)}
    end
  end

  defp reviews(resident_id) do
    Scope.resident(resident_id, fn -> Repo.all(from(p in Store.PieceReview, select: p)) end)
    |> Map.new(&{&1.path, &1})
  end

  defp decided?(nil, _hash), do: false
  defp decided?(review, hash), do: review.hash == hash

  defp last(nil), do: nil
  defp last(r), do: %{state: r.state, note: r.note, decided_at: r.decided_at}

  defp unpublished?(docs, r) do
    case Enum.find(docs, &(&1.path == r.path)) do
      %{published_at: %DateTime{} = at} -> DateTime.compare(at, r.decided_at) == :lt
      %{} -> true
      nil -> false
    end
  end

  defp out_in(reviews, docs, state),
    do: for(r <- Map.values(reviews), r.state == state, unpublished?(docs, r), do: out(r, docs))

  defp out(r, docs) do
    doc = Enum.find(docs, &(&1.path == r.path))

    %{
      path: r.path,
      title: doc && doc.title,
      state: r.state,
      note: r.note,
      draft_url: r.draft_url,
      decided_at: r.decided_at
    }
  end

  defp none(path),
    do: {:error, Error.new(:seshat_no_such_document, :seshat_pieces_no_such_document, path: path)}

  defp dispatch(command) do
    case PiecesRouter.dispatch(command) do
      {:ok, _events} ->
        :ok

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:seshat_dispatch_failed, :seshat_pieces_dispatch_failed, reason)}
    end
  end
end

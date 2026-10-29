defmodule Oneiroi.Kumbukumbu.Memory do
  @moduledoc """
  The memory aggregate on `memory-<resident_id>` (spec §3.1, §6.3). Pure
  (conventions §6): the bookmark's number, the instant and every ref
  arrive on the command.

  What it holds is what its rules need and nothing the projections do:
  the numbers of the bookmarks and each one's span and pin, the tag set
  with each tag's state, the taggings as a set, and the open bookmark
  proposals. A command whose effect is already in the state produces no
  event, so a tool call the model repeats or a request a client retries
  is harmless.
  """

  alias Oneiroi.Kumbukumbu.Events.Memory, as: Events
  alias Oneiroi.Kumbukumbu.MemoryCommands, as: Commands

  defstruct [:id, bookmarks: %{}, tags: %{}, taggings: MapSet.new(), proposals: %{}]

  # A tag is a slug (spec §3.2): the bounds are this codebase's guess,
  # long enough for "small-practical-suggestions" and short enough to
  # fit an index line.
  @slug ~r/\A[a-z0-9][a-z0-9-]{0,39}\z/
  @line_limit 120
  @target_kinds ~w(bookmark conversation turn)

  @doc "The slug a tag must match."
  @spec slug_pattern() :: Regex.t()
  def slug_pattern, do: @slug

  @doc "A bookmark's line is at most this many characters (spec §3.2's 120-char line)."
  @spec line_limit() :: pos_integer()
  def line_limit, do: @line_limit

  @doc "What a tagging may target in this slice."
  @spec target_kinds() :: [String.t()]
  def target_kinds, do: @target_kinds

  # ---- bookmarks ----

  def execute(%__MODULE__{} = m, %Commands.AddBookmark{} = c) do
    cond do
      Map.has_key?(m.bookmarks, c.number) -> []
      not line_ok?(c.line) -> {:error, :line_invalid}
      not span_ok?(c.turns_back) -> {:error, :span_invalid}
      true -> with_proposal(m, c)
    end
  end

  def execute(%__MODULE__{bookmarks: bookmarks}, %Commands.ExtendBookmark{} = c) do
    case Map.fetch(bookmarks, c.number) do
      :error ->
        {:error, :no_such_bookmark}

      {:ok, %{turns_back: current}}
      when not is_integer(c.turns_back) or c.turns_back <= current ->
        {:error, :span_not_grown}

      {:ok, _} ->
        %Events.BookmarkExtended{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          turns_back: c.turns_back
        }
    end
  end

  def execute(%__MODULE__{bookmarks: bookmarks}, %Commands.PinBookmark{} = c) do
    case Map.fetch(bookmarks, c.number) do
      :error -> {:error, :no_such_bookmark}
      {:ok, %{pinned: true}} -> []
      {:ok, _} -> %Events.BookmarkPinned{actor: c.actor, at: c.at, id: c.id, number: c.number}
    end
  end

  def execute(%__MODULE__{bookmarks: bookmarks}, %Commands.UnpinBookmark{} = c) do
    case Map.fetch(bookmarks, c.number) do
      :error -> {:error, :no_such_bookmark}
      {:ok, %{pinned: false}} -> []
      {:ok, _} -> %Events.BookmarkUnpinned{actor: c.actor, at: c.at, id: c.id, number: c.number}
    end
  end

  def execute(%__MODULE__{proposals: proposals}, %Commands.ProposeBookmark{} = c) do
    cond do
      Map.has_key?(proposals, c.ref) ->
        []

      not line_ok?(c.line) ->
        {:error, :line_invalid}

      true ->
        %Events.BookmarkProposed{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          ref: c.ref,
          session_key: c.session_key,
          anchor_ref: c.anchor_ref,
          line: c.line
        }
    end
  end

  def execute(%__MODULE__{proposals: proposals}, %Commands.DeclineBookmarkProposal{} = c) do
    case Map.get(proposals, c.ref) do
      %{state: :open} ->
        %Events.BookmarkProposalDeclined{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          ref: c.ref
        }

      _other ->
        {:error, :no_such_proposal}
    end
  end

  # ---- tags ----

  def execute(%__MODULE__{tags: tags}, %Commands.ProposeTag{} = c) do
    cond do
      not slug_ok?(c.slug) -> {:error, :slug_invalid}
      Map.get(tags, c.slug) == :proposed -> []
      Map.get(tags, c.slug) == :active -> {:error, :tag_exists}
      true -> %Events.TagProposed{actor: c.actor, at: c.at, note: c.note, id: c.id, slug: c.slug}
    end
  end

  def execute(%__MODULE__{tags: tags}, %Commands.ApproveTag{} = c) do
    if Map.get(tags, c.slug) == :proposed,
      do: %Events.TagApproved{actor: c.actor, at: c.at, note: c.note, id: c.id, slug: c.slug},
      else: {:error, :no_such_proposal}
  end

  def execute(%__MODULE__{tags: tags}, %Commands.RejectTag{} = c) do
    if Map.get(tags, c.slug) == :proposed,
      do: %Events.TagRejected{actor: c.actor, at: c.at, note: c.note, id: c.id, slug: c.slug},
      else: {:error, :no_such_proposal}
  end

  def execute(%__MODULE__{tags: tags}, %Commands.CreateTag{} = c) do
    cond do
      not slug_ok?(c.slug) -> {:error, :slug_invalid}
      Map.get(tags, c.slug) == :active -> []
      Map.get(tags, c.slug) == :proposed -> {:error, :tag_proposed}
      true -> %Events.TagCreated{actor: c.actor, at: c.at, id: c.id, slug: c.slug}
    end
  end

  def execute(%__MODULE__{tags: tags}, %Commands.RetireTag{} = c) do
    if Map.get(tags, c.slug) == :active,
      do: %Events.TagRetired{actor: c.actor, at: c.at, id: c.id, slug: c.slug},
      else: {:error, :no_such_tag}
  end

  def execute(%__MODULE__{} = m, %Commands.ApplyTag{} = c) do
    cond do
      Map.get(m.tags, c.slug) != :active ->
        {:error, :tag_not_active}

      c.target_kind not in @target_kinds ->
        {:error, :target_invalid}

      c.target_kind == "bookmark" and not Map.has_key?(m.bookmarks, number(c.target_id)) ->
        {:error, :target_invalid}

      MapSet.member?(m.taggings, tagging_key(c)) ->
        []

      true ->
        %Events.TagApplied{
          actor: c.actor,
          at: c.at,
          id: c.id,
          slug: c.slug,
          target_kind: c.target_kind,
          target_id: c.target_id
        }
    end
  end

  def execute(%__MODULE__{taggings: taggings}, %Commands.RemoveTagging{} = c) do
    if MapSet.member?(taggings, tagging_key(c)),
      do: %Events.TaggingRemoved{
        actor: c.actor,
        at: c.at,
        id: c.id,
        slug: c.slug,
        target_kind: c.target_kind,
        target_id: c.target_id
      },
      else: []
  end

  # ---- apply ----

  def apply(%__MODULE__{} = m, %Events.BookmarkAdded{} = e) do
    %{
      m
      | id: e.id,
        bookmarks: Map.put(m.bookmarks, e.number, %{turns_back: e.turns_back, pinned: false}),
        proposals: accept(m.proposals, e.proposal_ref)
    }
  end

  def apply(%__MODULE__{} = m, %Events.BookmarkExtended{} = e),
    do: put_in(m.bookmarks[e.number].turns_back, e.turns_back)

  def apply(%__MODULE__{} = m, %Events.BookmarkPinned{} = e),
    do: put_in(m.bookmarks[e.number].pinned, true)

  def apply(%__MODULE__{} = m, %Events.BookmarkUnpinned{} = e),
    do: put_in(m.bookmarks[e.number].pinned, false)

  def apply(%__MODULE__{} = m, %Events.BookmarkProposed{} = e) do
    proposal = %{state: :open, by: actor_map(e.actor)}
    %{m | id: e.id, proposals: Map.put(m.proposals, e.ref, proposal)}
  end

  def apply(%__MODULE__{} = m, %Events.BookmarkProposalDeclined{} = e),
    do: put_in(m.proposals[e.ref].state, :declined)

  def apply(%__MODULE__{} = m, %Events.TagProposed{} = e),
    do: %{m | id: e.id, tags: Map.put(m.tags, e.slug, :proposed)}

  def apply(%__MODULE__{} = m, %Events.TagApproved{} = e),
    do: %{m | tags: Map.put(m.tags, e.slug, :active)}

  def apply(%__MODULE__{} = m, %Events.TagRejected{} = e),
    do: %{m | tags: Map.delete(m.tags, e.slug)}

  def apply(%__MODULE__{} = m, %Events.TagCreated{} = e),
    do: %{m | id: e.id, tags: Map.put(m.tags, e.slug, :active)}

  def apply(%__MODULE__{} = m, %Events.TagRetired{} = e),
    do: %{m | tags: Map.put(m.tags, e.slug, :retired)}

  def apply(%__MODULE__{} = m, %Events.TagApplied{} = e),
    do: %{m | taggings: MapSet.put(m.taggings, tagging_key(e))}

  def apply(%__MODULE__{} = m, %Events.TaggingRemoved{} = e),
    do: %{m | taggings: MapSet.delete(m.taggings, tagging_key(e))}

  # ---- helpers ----

  defp bookmark_added(c, proposal) do
    %Events.BookmarkAdded{
      actor: c.actor,
      at: c.at,
      id: c.id,
      number: c.number,
      session_key: c.session_key,
      anchor_ref: c.anchor_ref,
      anchor_at: c.anchor_at,
      turns_back: c.turns_back,
      line: c.line,
      summary: c.summary,
      proposal_ref: c.proposal_ref,
      proposed_by: proposal && proposal.by
    }
  end

  # A bookmark naming a proposal accepts it, and only an open one.
  defp with_proposal(_m, %{proposal_ref: nil} = c), do: bookmark_added(c, nil)

  defp with_proposal(m, c) do
    case Map.get(m.proposals, c.proposal_ref) do
      %{state: :open} = proposal -> bookmark_added(c, proposal)
      _other -> {:error, :no_such_proposal}
    end
  end

  defp accept(proposals, nil), do: proposals
  defp accept(proposals, ref), do: put_in(proposals[ref].state, :accepted)

  defp line_ok?(line),
    do: is_binary(line) and String.trim(line) != "" and String.length(line) <= @line_limit

  defp span_ok?(turns_back), do: is_integer(turns_back) and turns_back >= 1

  defp slug_ok?(slug), do: is_binary(slug) and Regex.match?(@slug, slug)

  defp tagging_key(%{slug: slug, target_kind: kind, target_id: id}),
    do: {slug, kind, to_string(id)}

  # A bookmark target arrives as the number or its string: the wire
  # carries strings and the aggregate keys on integers.
  defp number(n) when is_integer(n), do: n

  defp number(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp number(_other), do: nil

  # An actor replayed from the log has string keys; one on a fresh
  # command is the struct. Both are one actor.
  defp actor_map(%{} = actor) do
    read = fn key -> Map.get(actor, key) || Map.get(actor, Atom.to_string(key)) end

    case read.(:kind) do
      nil -> nil
      kind -> %{kind: to_string(kind), id: read.(:id), model: read.(:model)}
    end
  end

  defp actor_map(_other), do: nil
end

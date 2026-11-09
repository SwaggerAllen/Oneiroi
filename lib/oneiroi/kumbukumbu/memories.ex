defmodule Oneiroi.Kumbukumbu.Memories do
  @moduledoc """
  Memory's service functions for bookmarks, tags and taggings (spec
  §6.3): the command edge, where numbers are minted, refs made and the
  parties' roles held, and the reads the Memory screen and the brain
  take.

  Who may do what is held here, not in a client. A bookmark's words are
  the resident's: only the resident's actor adds or extends one, or
  declines a proposal. The tag set is the witness's: only the witness's
  actor creates, approves, rejects or retires a tag. Either party pins,
  proposes a tag and applies an active one.

  Reads run under the resident's scope: a bookmark is the resident's row
  and the witness reads it as the resident's witness, which the route
  checks at the edge (`witnessed`), not a party to a conversation.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Conversation
  alias Oneiroi.Kumbukumbu.Conversations
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Events.Memory, as: Events
  alias Oneiroi.Kumbukumbu.Index
  alias Oneiroi.Kumbukumbu.Madeleine
  alias Oneiroi.Kumbukumbu.MemoryCommands, as: Commands
  alias Oneiroi.Kumbukumbu.MemoryRouter, as: Router
  alias Oneiroi.Kumbukumbu.Ranking
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  # ---- bookmarks ----

  @doc """
  The resident bookmarks a moment: `attrs` carry `session_key`,
  `anchor_ref` (the turn it was in), `line`, `summary`, `turns_back`
  (default 1) and, for a witness's proposal accepted, `proposal_ref`.
  `anchor_at` may be given for a turn still in flight; otherwise it is
  the captured turn's first instant. Returns the bookmark's number.
  """
  @spec add_bookmark(String.t(), map(), Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  def add_bookmark(resident_id, attrs, %Actor{} = actor) when is_map(attrs) do
    with :ok <- resident_only(actor),
         {:ok, anchor_at} <- anchor_at(resident_id, attrs),
         {:ok, number} <- Oneiroi.AgathosDaimon.mint_id(resident_id, "bookmark", actor) do
      command = %Commands.AddBookmark{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        session_key: attrs[:session_key],
        anchor_ref: attrs[:anchor_ref],
        anchor_at: anchor_at,
        turns_back: attrs[:turns_back] || 1,
        line: attrs[:line],
        summary: attrs[:summary],
        proposal_ref: attrs[:proposal_ref],
        register: attrs[:register]
      }

      with {:ok, _} <- dispatch(command), do: {:ok, number}
    end
  end

  def extend_bookmark(resident_id, number, turns_back, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.ExtendBookmark{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        turns_back: turns_back
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  def pin_bookmark(resident_id, number, attrs, %Actor{} = actor) when is_map(attrs) do
    command = %Commands.PinBookmark{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      evidences: Map.get(attrs, :evidences)
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def weigh_bookmark(resident_id, number, importance, status, %Actor{} = actor) do
    command = %Commands.WeighBookmark{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      importance: importance,
      status: status
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def record_citations(resident_id, sources, %Actor{} = actor) when is_map(sources) do
    command = %Commands.RecordCitations{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      sources: sources
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def shown(resident_id, label), do: Scope.resident(resident_id, fn -> Store.shown(label) end)

  def timeline_bookmarks(resident_id),
    do: Scope.resident(resident_id, fn -> Store.timeline_bookmarks() end)

  def unpin_bookmark(resident_id, number, %Actor{} = actor) do
    command = %Commands.UnpinBookmark{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "The witness proposes a bookmark with a suggested line and a note; returns the proposal's ref."
  def propose_bookmark(resident_id, session_key, anchor_ref, line, note, %Actor{} = actor) do
    with :ok <- witness_only(actor),
         {:ok, _at} <- anchor_at(resident_id, %{session_key: session_key, anchor_ref: anchor_ref}) do
      ref = 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

      command = %Commands.ProposeBookmark{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        ref: ref,
        session_key: session_key,
        anchor_ref: anchor_ref,
        line: line
      }

      with {:ok, _} <- dispatch(command), do: {:ok, ref}
    end
  end

  def decline_proposal(resident_id, ref, note, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.DeclineBookmarkProposal{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        ref: ref
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  # ---- revisions (F13) ----

  @doc "Revises a memory: a fact by either party applies, a stance by the resident applies, a stance by the witness is proposed; returns the number and whether it holds."
  def revise(resident_id, attrs, %Actor{} = actor) when is_map(attrs) do
    command = %Commands.Revise{
      actor: actor,
      at: Clock.now(),
      note: attrs[:note],
      id: resident_id,
      target_kind: attrs[:target_kind],
      target_id: attrs[:target_id],
      kind: attrs[:kind],
      text: attrs[:text]
    }

    case dispatch(command) do
      {:ok, [%Events.RevisionApplied{number: n}]} -> {:ok, %{number: n, state: "applied"}}
      {:ok, [%Events.RevisionProposed{number: n}]} -> {:ok, %{number: n, state: "proposed"}}
      other -> other
    end
  end

  @doc "The resident accepts a proposed revision, with a note; it holds."
  def accept_revision(resident_id, number, note, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.AcceptRevision{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        number: number
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "The resident declines a proposed revision, with a note."
  def decline_revision(resident_id, number, note, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.DeclineRevision{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        number: number
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "Every revision, newest first."
  def revisions(resident_id), do: Scope.resident(resident_id, fn -> Store.revisions() end)

  @doc "The revisions on one target, applied and proposed, in order."
  def revisions_of(resident_id, kind, target_id),
    do: Scope.resident(resident_id, fn -> Store.revisions_of(kind, to_string(target_id)) end)

  # ---- tags ----

  def propose_tag(resident_id, slug, note, %Actor{} = actor) do
    command = %Commands.ProposeTag{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      slug: slug
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def approve_tag(resident_id, slug, note, %Actor{} = actor),
    do: decide_tag(Commands.ApproveTag, [note: note], resident_id, slug, actor)

  def reject_tag(resident_id, slug, note, %Actor{} = actor),
    do: decide_tag(Commands.RejectTag, [note: note], resident_id, slug, actor)

  def create_tag(resident_id, slug, %Actor{} = actor),
    do: decide_tag(Commands.CreateTag, [], resident_id, slug, actor)

  def retire_tag(resident_id, slug, %Actor{} = actor),
    do: decide_tag(Commands.RetireTag, [], resident_id, slug, actor)

  @doc "Applies an active tag to a target: a bookmark's number, a session key or a turn ref."
  def apply_tag(resident_id, slug, kind, target_id, %Actor{} = actor) do
    with :ok <- target_ok(resident_id, kind, target_id) do
      command = %Commands.ApplyTag{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        slug: slug,
        target_kind: kind,
        target_id: to_string(target_id)
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  def remove_tagging(resident_id, slug, kind, target_id, %Actor{} = actor) do
    command = %Commands.RemoveTagging{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      slug: slug,
      target_kind: kind,
      target_id: to_string(target_id)
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- reads ----

  @doc "The resident's bookmarks, newest first, each with its closed-set tags and then the tree's (spec §6.17, P39), through the tree port."
  def bookmarks(resident_id),
    do: tree_tags(resident_id, Scope.resident(resident_id, fn -> Store.bookmarks() end))

  @doc "One bookmark with the messages of its span: the anchor turn and the `turns_back - 1` before it."
  @spec bookmark(String.t(), pos_integer()) :: {:ok, map(), [map()]} | {:error, Error.t()}
  def bookmark(resident_id, number) do
    read =
      Scope.resident(resident_id, fn ->
        case Store.bookmark(number) do
          nil ->
            {:error,
             Error.new(:kumbukumbu_no_such_bookmark, :kumbukumbu_memories_bookmark_absent,
               number: number
             )}

          b ->
            {:ok, b, span(b)}
        end
      end)

    with {:ok, b, span} <- read, do: {:ok, hd(tree_tags(resident_id, [b])), span}
  end

  # The tree's tags (`soul/3`, `habit/2`, `seed/1`) after the closed
  # set's, through the port, so the resident's own tree is a vocabulary
  # beside the witness's labels (spec §6.17, P39). Outside the store's
  # scope: the port's implementation takes its own.
  defp tree_tags(_resident_id, []), do: []

  defp tree_tags(resident_id, rows) do
    ids = Enum.map(rows, &Integer.to_string(&1.number))
    tree = Config.fetch!(:kumbukumbu, :tree).tags_of(resident_id, "bookmark", ids)
    Enum.map(rows, &%{&1 | tags: &1.tags ++ Map.get(tree, Integer.to_string(&1.number), [])})
  end

  def proposals(resident_id), do: Scope.resident(resident_id, fn -> Store.open_proposals() end)

  def tags(resident_id), do: Scope.resident(resident_id, fn -> Store.tags() end)

  def taggings(resident_id, kind, target_id),
    do: Scope.resident(resident_id, fn -> Store.taggings(kind, to_string(target_id)) end)

  def tagged(resident_id, slug), do: Scope.resident(resident_id, fn -> Store.tagged(slug) end)

  @doc """
  The madeleine for a turn's words: the vectors refreshed (embedding what
  changed), then one adjacent, unheard bookmark or nil; within the room of
  `session_key` when given (spec §6.3, P23). `refresh: false` reads the
  vectors as they stand and `purpose:` bills the query elsewhere than
  `embeddings`: a regression trial's turn passes both (eunomia#10).
  """
  def madeleine(resident_id, text, %Actor{} = actor, session_key \\ nil, opts \\ []) do
    if Keyword.get(opts, :refresh, true), do: _ = Madeleine.refresh(resident_id, actor)
    keys = session_key && Conversations.room(resident_id, session_key).keys
    Madeleine.recall(resident_id, text, actor, keys, Keyword.get(opts, :purpose, :embeddings))
  end

  @doc "The turn's words embedded once, after refreshing the bookmarks' vectors (kumbukumbu#46)."
  def memory_query(resident_id, text, %Actor{} = actor, opts \\ []) do
    if Keyword.get(opts, :refresh, true), do: _ = Madeleine.refresh(resident_id, actor)
    Madeleine.query(resident_id, text, actor, Keyword.get(opts, :purpose, :embeddings))
  end

  @doc "The madeleine for a vector already embedded, within the room of `session_key`, past what the index returned."
  def madeleine_near(resident_id, vector, session_key, exclude \\ []) do
    keys = session_key && Conversations.room(resident_id, session_key).keys
    Madeleine.recall_near(resident_id, vector, keys, exclude)
  end

  @doc "The index the brain is shown this turn, under `KUMBUKUMBU_INDEX_TOKENS`, over every bookmark."
  @spec index(String.t()) :: Index.built()
  def index(resident_id) do
    budget = Config.fetch!(:kumbukumbu, :index_tokens)
    resident_id |> bookmarks() |> Index.build(budget, Local.zone(resident_id))
  end

  @doc """
  The index within the room of `session_key` (spec §6.3, P23): built
  over the bookmarks of the room's sessions alone, and a bookmark of
  another domain that would have ranked in is named among the
  near-misses as held behind the domain line, so the audit shows the
  line approached and not crossed. A `session_key` no session has, nil
  included, is the common room (`Conversations.room/2`).
  """
  @spec index(String.t(), String.t() | nil) :: Index.built()
  def index(resident_id, session_key) do
    budget = Config.fetch!(:kumbukumbu, :index_tokens)
    %{keys: keys} = Conversations.room(resident_id, session_key)
    # The pins are in the stable prefix (`pins/2`, kumbukumbu#45): they
    # are decisions, not measurements, and are never ranked here.
    all = resident_id |> bookmarks() |> Enum.reject(& &1.pinned_at)
    {in_room, held} = Enum.split_with(all, &(&1.session_key in keys))
    zone = Local.zone(resident_id)
    built = Index.build(in_room, budget, zone)
    would = all |> Index.build(budget, zone) |> Map.fetch!(:included)
    sessions = Scope.resident(resident_id, fn -> Map.new(Store.sessions(), &{&1.key, &1}) end)

    approached =
      held
      |> Enum.filter(&(&1.number in would))
      |> Enum.map(fn b ->
        %{
          number: b.number,
          line: b.line,
          reason:
            "held behind the domain line: a bookmark of #{domain_name(sessions[b.session_key])} ranked in and was not crossed"
        }
      end)

    %{built | near_misses: built.near_misses ++ approached}
  end

  @doc """
  The ranked index (kumbukumbu#46): the bookmarks nearest `vector` in
  the room, ranked with the learned edges out of the seed, a fifth of
  the lines drawn at random from outside the ranked set, fresh each
  call; or, with no vector (blank words, nothing embedded, the provider
  down, a preview), the index by recency as before. The built index
  carries `seeds` and `explored` beside the usual fields, so the turn
  records what it considered, returned and drew.
  """
  @spec ranked_index(String.t(), String.t() | nil, [float()] | nil) :: map()
  def ranked_index(resident_id, session_key, nil),
    do:
      resident_id
      |> index(session_key)
      |> Map.merge(%{seeds: [], explored: [], considered: nil, exploration: ""})

  def ranked_index(resident_id, session_key, vector) do
    %{keys: keys} = Conversations.room(resident_id, session_key)

    unpinned = resident_id |> bookmarks() |> Enum.reject(& &1.pinned_at)
    {in_room, held} = Enum.split_with(unpinned, &(&1.session_key in keys))
    by_number = Map.new(in_room, &{&1.number, &1})
    held_by_number = Map.new(held, &{&1.number, &1})
    considered = Config.fetch!(:kumbukumbu, :index_considered)
    lines = Config.fetch!(:kumbukumbu, :index_lines)
    explore = Config.fetch!(:kumbukumbu, :explore_lines)

    {candidates, approached, {edges, citations}} =
      Scope.resident(resident_id, fn ->
        nearest = Store.nearest_vectors(vector, "bookmark", considered * 3)

        near =
          nearest
          |> Enum.filter(&Map.has_key?(by_number, &1.number))
          |> Enum.take(considered)
          |> Enum.map(&%{bookmark: by_number[&1.number], distance: &1.distance})

        # Another domain's bookmark that would have ranked in, had the
        # room not held it, is named and never crossed (spec §6.3, P23):
        # the line approached.
        approached =
          nearest
          |> Enum.take(lines)
          |> Enum.filter(&Map.has_key?(held_by_number, &1.number))
          |> Enum.map(&held_by_number[&1.number])

        seeds =
          near
          |> Enum.take(Config.fetch!(:kumbukumbu, :index_seeds))
          |> Enum.map(& &1.bookmark.number)

        {near, approached, {Store.edges_from(seeds), Store.citation_edges_from(seeds)}}
      end)

    # The exploration's draw, at the command edge and fresh each call;
    # what it returned is recorded on the turn, so nothing replays it.
    draw = Enum.shuffle(in_room)

    ranking =
      Ranking.rank(candidates, edges,
        citations: citations,
        lambda: Config.fetch!(:kumbukumbu, :edge_lambda_percent) / 100,
        half_life: Config.fetch!(:kumbukumbu, :edge_half_life_opportunities),
        lines: lines,
        explore: explore,
        seeds: Config.fetch!(:kumbukumbu, :index_seeds),
        min_score: Config.fetch!(:kumbukumbu, :index_min_similarity_percent) / 100,
        budget: Config.fetch!(:kumbukumbu, :index_tokens),
        explore_budget: Config.fetch!(:kumbukumbu, :explore_tokens),
        draw: draw
      )

    sessions = Scope.resident(resident_id, fn -> Map.new(Store.sessions(), &{&1.key, &1}) end)

    held_misses =
      Enum.map(approached, fn b ->
        %{
          number: b.number,
          line: b.line,
          reason:
            "held behind the domain line: a bookmark of #{domain_name(sessions[b.session_key])} ranked in and was not crossed"
        }
      end)

    built = ranked_index_built(ranking, length(in_room), Local.zone(resident_id))
    %{built | near_misses: built.near_misses ++ held_misses}
  end

  defp ranked_index_built(ranking, in_room, zone) do
    ranked_lines = Enum.map(ranking.ranked, &Index.line(&1.bookmark, zone))
    explored_lines = Enum.map(ranking.explored, &Index.line(&1.bookmark, zone))
    shown = length(ranked_lines) + length(explored_lines)

    # The exploration's draws are a slot of their own (brain#68), listed
    # under their own line apart from the index.
    exploration =
      if explored_lines == [],
        do: "",
        else:
          Enum.join(
            ["Drawn at random, for what you might not think to look for:" | explored_lines],
            "\n"
          )

    footer =
      "#{max(in_room - shown, 0)} more not shown; bookmark_open(number) reads any, bookmark_list pages back through the rest, and transcript_search reaches past the index. " <>
        "When you reply, memory_feedback(used: [numbers]) says which of these helped."

    text = Enum.join(ranked_lines ++ ["", footer], "\n")

    near_misses =
      Enum.map(ranking.rejected, fn r ->
        %{
          number: r.bookmark.number,
          line: Index.line(r.bookmark, zone),
          reason:
            "ranked #{round3(r.score)} (similarity #{round3(r.similarity)}, edges #{round3(r.edge)}), #{r.why}"
        }
      end)

    %{
      text: text,
      included: Enum.map(ranking.ranked ++ ranking.explored, & &1.bookmark.number),
      left_out: max(in_room - shown, 0),
      near_misses: near_misses,
      tokens: Index.tokens(text),
      seeds: ranking.seeds,
      explored: Enum.map(ranking.explored, & &1.bookmark.number),
      exploration: exploration,
      considered: length(ranking.ranked) + length(ranking.rejected)
    }
  end

  defp round3(x) when is_float(x), do: Float.round(x, 3)
  defp round3(x), do: x

  @doc """
  The pins within the room of `session_key`, oldest first (kumbukumbu
  #46): the resident's decisions, kept in the stable prefix rather than
  the ranked index, so they are cached with the identity files and never
  crowd the index or are measured against it.
  """
  @spec pins(String.t(), String.t() | nil) :: [map()]
  def pins(resident_id, session_key) do
    %{keys: keys} = Conversations.room(resident_id, session_key)

    resident_id
    |> bookmarks()
    |> Enum.filter(&(&1.pinned_at && &1.session_key in keys))
    |> Enum.sort_by(& &1.number)
  end

  defp domain_name(%{domain: domain}) when is_binary(domain), do: "the #{domain} domain"
  defp domain_name(_session), do: "the common room"

  @doc """
  What the index holds now in the common room, for the witness's Memory
  screen (kumbukumbu#38): the same `index/2` the next turn of the main
  session is built from (the main session is the common room), never
  inferred from `last_indexed_at`, which only says when a turn last
  listed a bookmark. The numbers listed in the index's order, how many
  of the room's it left out, how many sit in a named room and are
  listed only in that room's sessions, the budget, and a sentence that
  says all of it, so a client renders the rule and never restates it.
  """
  @spec index_now(String.t()) :: %{
          listed: [pos_integer()],
          left_out: non_neg_integer(),
          elsewhere: non_neg_integer(),
          budget: pos_integer(),
          description: String.t()
        }
  def index_now(resident_id) do
    budget = Config.fetch!(:kumbukumbu, :index_tokens)
    pins = pins(resident_id, nil)
    %{keys: keys} = Conversations.room(resident_id, nil)
    all = bookmarks(resident_id)
    ranked = Enum.count(all, &(is_nil(&1.pinned_at) and &1.session_key in keys))
    elsewhere = length(all) - length(pins) - ranked
    lines = Config.fetch!(:kumbukumbu, :index_lines)

    # Ranked against each turn's words (kumbukumbu#46), the index has no
    # "now" to show: what is in front of her every turn is the pins.
    %{
      listed: Enum.map(pins, & &1.number),
      left_out: ranked,
      elsewhere: elsewhere,
      budget: budget,
      description:
        "#{count(length(pins), "pin")} in front of every turn, in the stable prefix. " <>
          "The other #{ranked} are ranked against each turn's words: up to #{lines} a turn under a budget of #{budget} tokens (a bound), a fifth of them drawn at random." <>
          if(elsewhere > 0,
            do:
              " #{count(elsewhere, "bookmark")} made in a named room #{if elsewhere == 1, do: "is", else: "are"} ranked only in that room's conversations.",
            else: ""
          )
    }
  end

  defp count(1, word), do: "1 #{word}"
  defp count(n, word), do: "#{n} #{word}s"

  @doc """
  One page of the bookmarks within the room of `session_key`, newest
  first, for the brain's `bookmark_list` (kumbukumbu#39): the index
  lists what fits its budget, and this pages back through the rest.
  `before:` a number to page back from, `pinned: true` the pins alone
  (every one, the ones the index's half could not fit included), `tag:`
  a tag the bookmark carries, `text:` a phrase in its line, `from:` and
  `to:` days its anchor falls between, all combined; at most `KUMBUKUMBU_PAGE_BOOKMARKS` rows, and
  `further`, how many more match beyond the page. The room is
  `index/2`'s: a bookmark of another domain is never listed.
  """
  @spec page(String.t(), String.t() | nil, keyword()) :: %{
          rows: [map()],
          further: non_neg_integer()
        }
  def page(resident_id, session_key, opts \\ []) do
    size = Config.fetch!(:kumbukumbu, :page_bookmarks)
    %{keys: keys} = Conversations.room(resident_id, session_key)

    matching =
      resident_id
      |> bookmarks()
      |> Enum.filter(&(&1.session_key in keys and page_match?(&1, opts)))
      |> Enum.sort_by(& &1.number, :desc)

    {rows, rest} = Enum.split(matching, size)
    %{rows: rows, further: length(rest)}
  end

  defp page_match?(b, opts) do
    Enum.all?(opts, fn
      {:before, n} when is_integer(n) -> b.number < n
      {:pinned, true} -> b.pinned_at != nil
      {:tag, tag} when is_binary(tag) and tag != "" -> tag in b.tags
      {:text, text} when is_binary(text) and text != "" -> contains?(b.line, text)
      {:from, %Date{} = day} -> Date.compare(DateTime.to_date(b.anchor_at), day) != :lt
      {:to, %Date{} = day} -> Date.compare(DateTime.to_date(b.anchor_at), day) != :gt
      {_unset, _value} -> true
    end)
  end

  defp contains?(line, text),
    do: String.contains?(String.downcase(line), String.downcase(String.trim(text)))

  # ---- helpers ----

  # The span is turns, not instants: the anchor turn's messages and
  # those of the `turns_back - 1` turns captured before it in the
  # session, in transcript order.
  defp span(b) do
    messages = Store.messages(b.session_key)

    turns =
      messages
      |> Enum.chunk_by(& &1.turn_ref)
      |> Enum.take_while(fn [first | _] -> first.turn_ref != b.anchor_ref end)

    anchor = Enum.filter(messages, &(&1.turn_ref == b.anchor_ref))
    before = turns |> Enum.take(-(b.turns_back - 1)) |> List.flatten()
    if b.turns_back > 1, do: before ++ anchor, else: anchor
  end

  defp anchor_at(_resident_id, %{anchor_at: %DateTime{} = at}), do: {:ok, at}

  defp anchor_at(resident_id, %{session_key: key, anchor_ref: ref})
       when is_binary(key) and is_binary(ref) do
    Scope.resident(resident_id, fn ->
      with %{} <- Store.session(key) || :no_such_session,
           [first | _] <- Store.turn_messages(ref) do
        {:ok, first.sent_at}
      else
        [] ->
          {:error,
           Error.new(:kumbukumbu_no_such_turn, :kumbukumbu_memories_anchor_turn_absent,
             turn_ref: ref
           )}

        :no_such_session ->
          {:error,
           Error.new(:kumbukumbu_no_such_session, :kumbukumbu_memories_anchor_session_absent,
             key: key
           )}
      end
    end)
  end

  defp anchor_at(_resident_id, _attrs),
    do: {:error, Error.new(:kumbukumbu_target_invalid, :kumbukumbu_memories_anchor_unnamed)}

  defp target_ok(_resident_id, "bookmark", _id), do: :ok

  defp target_ok(resident_id, "conversation", key) do
    Scope.resident(resident_id, fn ->
      if Store.session(to_string(key)),
        do: :ok,
        else:
          {:error,
           Error.new(:kumbukumbu_target_invalid, :kumbukumbu_memories_target_session_absent,
             kind: "conversation",
             id: key
           )}
    end)
  end

  defp target_ok(resident_id, "turn", ref) do
    Scope.resident(resident_id, fn ->
      if Store.turn_messages(to_string(ref)) != [],
        do: :ok,
        else:
          {:error,
           Error.new(:kumbukumbu_target_invalid, :kumbukumbu_memories_target_turn_absent,
             kind: "turn",
             id: ref
           )}
    end)
  end

  defp target_ok(_resident_id, kind, id),
    do:
      {:error,
       Error.new(:kumbukumbu_target_invalid, :kumbukumbu_memories_target_kind_unknown,
         kind: kind,
         id: id
       )}

  defp decide_tag(module, extra, resident_id, slug, actor) do
    with :ok <- witness_only(actor) do
      fields = [actor: actor, at: Clock.now(), id: resident_id, slug: slug] ++ extra
      with {:ok, _} <- dispatch(struct!(module, fields)), do: :ok
    end
  end

  # ---- house letters (kumbukumbu#44) ----

  @doc """
  Sends a house letter from the conversation `session_key` names (its
  title is the sender, the server's name for it) or, with `session_key`
  nil, from the witness; to a conversation's name or `house`. `attrs`
  carry `to`, `text`, and optionally `in_reply_to` and `keepsake`.
  """
  def send_letter(resident_id, session_key, attrs, %Actor{} = actor) when is_map(attrs) do
    with {:ok, from} <- sender(resident_id, session_key, actor),
         :ok <- addressed(resident_id, attrs[:to]) do
      command = %Commands.SendHouseLetter{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        from: from,
        from_session: session_key,
        to: attrs[:to],
        to_session: attrs[:to_session],
        in_reply_to: attrs[:in_reply_to],
        text: attrs[:text],
        keepsake: attrs[:keepsake]
      }

      case dispatch(command) do
        {:ok, [%Events.HouseLetterSent{number: n, from: from}]} -> {:ok, %{number: n, from: from}}
        other -> other
      end
    end
  end

  @doc "A house letter from the oracle to the conversation `session_key` (brain#49); nothing when that conversation has no name."
  def letter_to_session(resident_id, session_key, text, %Actor{kind: :platform} = actor) do
    case name_of(resident_id, session_key) do
      nil ->
        {:ok, :no_conversation}

      # The session itself rides with its name (sunna#44): every free-time
      # conversation is named Free time, and the answer belongs to one.
      name ->
        send_letter(resident_id, nil, %{to: name, to_session: session_key, text: text}, actor)
    end
  end

  @doc """
  The names a house letter can be addressed to (kumbukumbu#44): `house`,
  `Free time` and the Oneiroi chat, which are always there to be written
  to, and the name of every conversation this resident has had. A letter
  to any other name would wait for a reader that never comes.
  """
  def addresses(resident_id) do
    titles =
      Scope.resident(resident_id, fn -> Store.sessions() end)
      |> Enum.map(&Conversation.title/1)

    Enum.uniq(["house", "Free time", "Oneiroi chat" | titles])
  end

  @doc "Every house letter, oldest first, each with the conversations that read it."
  def letters(resident_id), do: Scope.resident(resident_id, fn -> Store.house_letters() end)

  @doc "The letters for the conversation `session_key` names, to it or to the house, that it did not send and has not read."
  def inbox(resident_id, session_key) do
    case name_of(resident_id, session_key) do
      nil -> []
      name -> resident_id |> letters() |> Enum.filter(&unread_by?(&1, name))
    end
  end

  @doc "The conversation `session_key` names reads these letters: each one for it is marked read by its name."
  def read_letters(resident_id, session_key, numbers, %Actor{} = actor) do
    case name_of(resident_id, session_key) do
      nil ->
        :ok

      name ->
        command = %Commands.ReadHouseLetters{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          numbers: numbers,
          by: name
        }

        with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "A conversation's name, by its key; nil for a key the resident has no session under."
  def name_of(_resident_id, nil), do: nil

  def name_of(resident_id, session_key) do
    case Scope.resident(resident_id, fn -> Store.session(session_key) end) do
      nil -> nil
      session -> Conversation.title(session)
    end
  end

  defp unread_by?(letter, name),
    do:
      (letter.to_name == name or letter.to_name == "house") and letter.from_name != name and
        name not in letter.read_by

  # A name no conversation answers to is refused before the letter is
  # sent: on 2026-11-02 a Claude Code conversation that opened before the
  # hook named its folder was called `Claude Code`, a letter to `Claude
  # Code · Oneiroi` was accepted, and nothing would ever have read it.
  # A malformed `to` is the aggregate's to refuse, as it always was.
  defp addressed(resident_id, to) when is_binary(to) and to != "" do
    names = addresses(resident_id)

    if to in names,
      do: :ok,
      else:
        {:error,
         Error.new(:kumbukumbu_letter_unaddressed, :kumbukumbu_memories_letter_unaddressed,
           to: to,
           names: names
         )}
  end

  defp addressed(_resident_id, _to), do: :ok

  defp sender(_resident_id, nil, %Actor{kind: :witness}), do: {:ok, "witness"}
  # The oracle's landing notice (brain#49): the platform, writing for no
  # conversation of its own.
  defp sender(_resident_id, nil, %Actor{kind: :platform}), do: {:ok, "the oracle"}
  # A platform report for the triage resident (gaia#20).
  defp sender(_resident_id, nil, %Actor{kind: :job, id: "platform_reports"}),
    do: {:ok, "a platform report"}

  defp sender(resident_id, session_key, %Actor{}) do
    case name_of(resident_id, session_key) do
      nil ->
        {:error,
         Error.new(:kumbukumbu_no_such_session, :kumbukumbu_memories_letter_session_absent,
           key: session_key
         )}

      name ->
        {:ok, name}
    end
  end

  defp resident_only(%Actor{kind: :resident}), do: :ok

  defp resident_only(%Actor{}),
    do: {:error, Error.new(:kumbukumbu_not_the_resident, :kumbukumbu_memories_resident_only)}

  defp witness_only(%Actor{kind: :witness}), do: :ok

  defp witness_only(%Actor{}),
    do: {:error, Error.new(:kumbukumbu_not_the_witness, :kumbukumbu_memories_witness_only)}

  # The aggregate's refusals arrive sited (`Memory`); what else a
  # dispatch answers, the actor middleware's refusal or the store's own
  # failure, is wrapped here, once, where it is first matched.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, {:refused, problems} = refusal} ->
        {:error,
         Error.caught(
           :kumbukumbu_command_refused,
           :kumbukumbu_memories_command_refused,
           refusal,
           problems: problems
         )}

      {:error, reason} ->
        {:error,
         Error.caught(
           :kumbukumbu_dispatch_failed,
           :kumbukumbu_memories_dispatch_failed,
           reason,
           command: command.__struct__
         )}
    end
  end

  @doc "The messages of one turn, by ref, under the resident's scope: what a habit's citation reads back (ethos)."
  def turn_messages(resident_id, turn_ref),
    do: Scope.resident(resident_id, fn -> Store.turn_messages(turn_ref) end)
end

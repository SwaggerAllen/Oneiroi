defmodule Oneiroi.Xenia.Presence do
  @moduledoc """
  Presence on Substack (xenia#20; the resident's design/influencer-mode.md,
  the witness's sign-off 2026-11-15): read the followed community like a
  resident, react like a reader, never like a growth machine.

  1. The follow list is the witness's handle's public subscriptions,
     fetched and checked against the count the profile claims, minus the
     mask he keeps (each exclusion dated, with its reason).
  2. A day's pass takes a random number of accounts, up to
     `XENIA_PRESENCE_ACCOUNTS_MAX`, from the cursor on, so every eligible
     account is reached in turn; it collects everything each posted
     since its last sample, ranked by likes ×1, comments ×2, restacks ×3.
  3. A random number off the top of the ranking is read, then a random
     number from below what was read, at random: each up to 10% of the
     pool or `XENIA_PRESENCE_CUT_MAX`, whichever is lower.
  4. The resident reads them whole and stages likes, comments and
     restacks, up to a random cap of 10% of the reads or the same max,
     which may go unmet; at most one interaction per account per day.
  5. The witness approves, asks for a revision or passes over each, with
     a comment if he likes; an approved one is released at a random
     instant within `XENIA_PRESENCE_RELEASE_MINUTES`, and the reader sends
     it from his own browser.

  Randomness is a design element: no stage's size is fixed.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Scope
  alias Oneiroi.Seshat
  alias Oneiroi.Xenia.Commands
  alias Oneiroi.Xenia.Error
  alias Oneiroi.Xenia.PresenceRouter
  alias Oneiroi.Xenia.Store
  alias Oneiroi.Xenia.Substack

  @handle ~r/\A[a-z0-9][a-z0-9_-]{0,63}\z/
  @kinds ~w(like comment restack)

  # ---- settings ----

  @doc "The switch, the handle, when the follow list was last fetched and the count it was checked against."
  def settings(resident_id) do
    case Scope.resident(resident_id, fn -> Store.presence() end) do
      nil ->
        %{enabled: false, handle: nil, set_at: nil, follows_at: nil, visible: nil, cursor: nil}

      p ->
        Map.take(p, [:enabled, :handle, :set_at, :follows_at, :visible, :cursor])
    end
  end

  @doc "The witness turns presence on or off and names the Substack handle whose subscriptions it reads."
  def set(resident_id, enabled, handle, %Actor{} = actor) do
    handle =
      handle |> to_string() |> String.trim() |> String.trim_leading("@") |> String.downcase()

    if Regex.match?(@handle, handle),
      do:
        %Commands.SetPresence{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          enabled: enabled == true,
          handle: handle
        }
        |> dispatch()
        |> ok(),
      else: {:error, Error.new(:xenia_presence_invalid, :xenia_presence_handle_invalid)}
  end

  # ---- the follow list ----

  @doc """
  Fetches the handle's public subscriptions and records them, once the
  list's length matches the count the profile claims (the endpoint
  verified against itself on every fetch, not only the first).
  """
  def refresh_follows(resident_id, %Actor{} = actor) do
    with {:ok, handle} <- handle(resident_id),
         {:ok, profile} <- Substack.client().profile(handle),
         :ok <- verified(profile) do
      %Commands.RecordFollows{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        accounts:
          Enum.map(
            profile.accounts,
            &Map.take(&1, [:key, :name, :host, :publication_id, :author_id])
          ),
        visible: profile.visible
      }
      |> dispatch()
      |> case do
        {:ok, _} -> {:ok, length(profile.accounts)}
        refused -> refused
      end
    end
  end

  defp handle(resident_id) do
    case settings(resident_id).handle do
      nil -> {:error, Error.new(:xenia_presence_invalid, :xenia_presence_no_handle)}
      handle -> {:ok, handle}
    end
  end

  defp verified(%{visible: visible, accounts: accounts})
       when is_integer(visible) and visible != length(accounts),
       do:
         {:error,
          Error.new(:xenia_presence_unverified, :xenia_presence_follows_count,
            listed: length(accounts),
            claimed: visible
          )}

  defp verified(_profile), do: :ok

  @doc "Every account on the list, followed or not, masked or not, with its last sample."
  def accounts(resident_id), do: Scope.resident(resident_id, fn -> Store.presence_accounts() end)

  @doc "The witness masks an account, with a one-line reason: it stays followed, and the rotation passes over it."
  def exclude(resident_id, key, reason, %Actor{} = actor),
    do:
      mask(%Commands.ExcludeAccount{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        key: key,
        note: reason
      })

  @doc "The witness lifts a mask, with a note."
  def include(resident_id, key, note, %Actor{} = actor),
    do:
      mask(%Commands.IncludeAccount{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        key: key,
        note: note
      })

  defp mask(command), do: command |> dispatch() |> ok()

  # ---- the day's pass ----

  @doc """
  Draws the day's pass, once a day: `{:ok, pass}` with its reads, `:off`
  while presence is off, `:empty` when no account is eligible or the
  sample held nothing new. The follow list is fetched again first; a
  fetch that fails or does not verify leaves the last list standing.
  """
  def draw(resident_id, day, %Actor{} = actor) do
    with true <- settings(resident_id).enabled || :off,
         nil <- Scope.resident(resident_id, fn -> Store.presence_pass(day) end) do
      _ = refresh_follows(resident_id, actor)
      sample(resident_id, day, actor)
    else
      :off -> :off
      %Store.PresencePass{} = pass -> {:ok, with_reads(resident_id, pass)}
    end
  end

  defp sample(resident_id, day, actor) do
    eligible = eligible(resident_id)

    case eligible do
      [] ->
        :empty

      _ ->
        n = draw_up_to(min(Config.fetch!(:xenia, :presence_accounts_max), length(eligible)))
        accounts = from_cursor(eligible, settings(resident_id).cursor) |> Enum.take(n)
        pool = Enum.flat_map(accounts, &items(&1))
        reads = cuts(pool)
        cap = draw_up_to(min(max(div(length(reads), 10), 1), cut_max()))

        if reads == [],
          do: record_empty(resident_id, day, accounts, actor),
          else: record(resident_id, day, accounts, pool, reads, cap, actor)
    end
  end

  defp eligible(resident_id),
    do: for(a <- accounts(resident_id), a.followed and not a.excluded, do: a)

  # The traversal starts after the last account sampled and wraps, so
  # coverage is the cursor's, and only the count is random.
  @doc false
  def from_cursor(accounts, nil), do: accounts

  def from_cursor(accounts, cursor) do
    {before, rest} = Enum.split_with(accounts, &(&1.key <= cursor))
    rest ++ before
  end

  defp items(account) do
    since =
      account.last_sampled_at ||
        DateTime.add(Clock.now(), -Config.fetch!(:xenia, :presence_lookback_days) * 86_400)

    case Substack.client().items(account_map(account), since) do
      {:ok, items} -> Enum.map(items, &Map.put(&1, :score, score(&1)))
      {:error, _} -> []
    end
  end

  defp account_map(a),
    do: %{
      key: a.key,
      name: a.name,
      host: a.host,
      publication_id: a.publication_id,
      author_id: a.author_id
    }

  @doc "The inbound weight (his): likes 1, comments 2, restacks 3."
  def score(item), do: item.likes + 2 * item.comments + 3 * item.restacks

  # The ranked cut off the top; the serendipity cut at random from the
  # unread remainder below it, never the next slice of the same order.
  @doc false
  def cuts([]), do: []

  def cuts(pool) do
    ranked = Enum.sort_by(pool, &{-&1.score, -DateTime.to_unix(&1.at)})
    max = min(max(div(length(pool), 10), 1), cut_max())
    {top, rest} = Enum.split(ranked, draw_up_to(max))
    below = rest |> Enum.shuffle() |> Enum.take(draw_up_to(min(max, length(rest))))

    Enum.map(top, &Map.put(&1, :cut, "ranked")) ++
      Enum.map(below, &Map.put(&1, :cut, "serendipity"))
  end

  defp cut_max, do: Config.fetch!(:xenia, :presence_cut_max)

  # A uniform draw in 1..max (0 when max is 0): the caps keep the shape,
  # the draw keeps it from being a metronome. Tune the shape at setup.
  defp draw_up_to(max) when max < 1, do: 0
  defp draw_up_to(max), do: :rand.uniform(max)

  defp record_empty(resident_id, day, accounts, actor) do
    # The accounts were still sampled: the cursor moves on past them.
    record(resident_id, day, accounts, [], [], 0, actor)
    :empty
  end

  defp record(resident_id, day, accounts, pool, reads, cap, actor) do
    ranked = Enum.count(reads, &(&1.cut == "ranked"))

    command = %Commands.DrawPass{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      day: day,
      accounts: Enum.map(accounts, & &1.key),
      pool: length(pool),
      ranked: ranked,
      serendipity: length(reads) - ranked,
      cap: cap,
      reads: Enum.map(reads, &read_entry/1)
    }

    with {:ok, _events} <- dispatch(command) do
      pass = Scope.resident(resident_id, fn -> Store.presence_pass(day) end)
      _ = render(resident_id, pass.number)
      {:ok, with_reads(resident_id, pass)}
    end
  end

  defp read_entry(item),
    do: %{
      key: item.key,
      kind: item.kind,
      account: item.account,
      title: item.title,
      url: item.url,
      at: DateTime.to_iso8601(item.at),
      likes: item.likes,
      comments: item.comments,
      restacks: item.restacks,
      score: item.score,
      cut: item.cut,
      excerpt: item.excerpt
    }

  defp with_reads(resident_id, pass),
    do: %{
      pass: pass,
      reads: Scope.resident(resident_id, fn -> Store.presence_reads(pass.number) end)
    }

  # ---- the resident's ----

  @doc "The resident reads an item of today's pass whole: its text, and the read recorded."
  def read(resident_id, item, %Actor{} = actor) do
    with {:ok, pass} <- latest(resident_id),
         %Store.PresenceRead{} = row <-
           Scope.resident(resident_id, fn -> Store.presence_read(pass.number, item) end) ||
             {:error, Error.new(:xenia_presence_not_drawn, :xenia_presence_read_row_absent)},
         {:ok, text} <- Substack.client().text(%{key: row.item, url: row.url}),
         {:ok, _} <-
           dispatch(%Commands.ReadItem{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             pass: pass.number,
             item: item
           }) do
      {:ok, %{read: row, text: text}}
    end
  end

  defp latest(resident_id) do
    case Scope.resident(resident_id, fn -> Store.presence_passes(1) end) do
      [pass] -> {:ok, pass}
      [] -> {:error, Error.new(:xenia_presence_not_drawn, :xenia_presence_no_pass)}
    end
  end

  @doc "The resident stages a like, a comment (with its words) or a restack for an item read; `supersedes` revises one waiting."
  def stage(resident_id, attrs, %Actor{} = actor) do
    kind = to_string(attrs[:kind] || "")

    if kind in @kinds do
      %Commands.StageInteraction{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        item: to_string(attrs[:item] || ""),
        kind: kind,
        text: if(kind == "comment", do: attrs[:text]),
        supersedes: attrs[:supersedes]
      }
      |> dispatch()
      |> case do
        {:ok, [%{number: number} | _]} ->
          _ = render_latest(resident_id)
          {:ok, number}

        refused ->
          refused
      end
    else
      {:error, Error.new(:xenia_presence_invalid, :xenia_presence_stage_kind_invalid)}
    end
  end

  # ---- the review ----

  @doc """
  The witness decides an interaction: `approve` (released at a random
  instant within `XENIA_PRESENCE_RELEASE_MINUTES`), `revise` (with the
  comment that says how) or `pass`; a comment is his to add to any.
  """
  def decide(resident_id, number, decision, comment, %Actor{} = actor) do
    release =
      if decision == "approve",
        do: DateTime.add(Clock.now(), release_after(), :second)

    %Commands.DecideInteraction{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      decision: decision,
      comment: comment,
      release_at: release
    }
    |> dispatch()
    |> case do
      {:ok, _} ->
        _ = render_latest(resident_id)
        :ok

      refused ->
        refused
    end
  end

  # At least five minutes, so a mistaken approval can be seen in time;
  # the rest of the window at random.
  defp release_after do
    window = max(Config.fetch!(:xenia, :presence_release_minutes) * 60 - 300, 1)
    300 + :rand.uniform(window)
  end

  @doc "Interactions by state (every one when nil), newest first, each with the item it answers."
  def interactions(resident_id, states \\ nil) do
    Scope.resident(resident_id, fn ->
      for i <- Store.presence_interactions(states),
          do: %{interaction: i, read: Store.presence_read(i.pass, i.item)}
    end)
  end

  @doc "The latest passes, newest first, with their reads."
  def passes(resident_id, limit) do
    Scope.resident(resident_id, fn ->
      for p <- Store.presence_passes(limit), do: %{pass: p, reads: Store.presence_reads(p.number)}
    end)
  end

  # ---- the reader's ----

  @doc "What the reader has to send now: approved interactions whose release has come, oldest release first."
  def due(resident_id) do
    now = Clock.now()

    resident_id
    |> interactions(["approved"])
    |> Enum.filter(
      &(&1.interaction.release_at && DateTime.compare(&1.interaction.release_at, now) != :gt)
    )
    |> Enum.sort_by(& &1.interaction.release_at, DateTime)
    |> Enum.map(&outgoing/1)
  end

  # What the reader needs to send it from the right origin: a post's
  # like and comment go from its publication's own page, a note's and
  # every restack from substack.com (the probe of 2026-11-15).
  defp outgoing(%{interaction: i, read: r}) do
    uri = URI.parse(r.url)
    {kind, id} = item_id(i.item)

    %{
      number: i.number,
      action: i.kind,
      target: kind,
      id: id,
      host: "#{uri.scheme}://#{uri.host}",
      url: r.url,
      text: i.text
    }
  end

  defp item_id("p-" <> id), do: {"post", String.to_integer(id)}
  defp item_id("c-" <> id), do: {"note", String.to_integer(id)}

  @doc "The reader (or the witness) says an interaction went out, with its address if there is one."
  def mark_sent(resident_id, number, url, %Actor{} = actor),
    do:
      %Commands.MarkInteractionSent{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        url: url
      }
      |> dispatch()
      |> done(resident_id)

  @doc "The reader says an interaction could not go out, and why."
  def fail(resident_id, number, reason, %Actor{} = actor),
    do:
      %Commands.FailInteraction{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        reason: reason
      }
      |> dispatch()
      |> done(resident_id)

  defp done(result, resident_id) do
    case result do
      {:ok, _} ->
        _ = render_latest(resident_id)
        :ok

      refused ->
        refused
    end
  end

  # ---- the repository (spec §6.10): each pass as a file she can read ----

  defp render_latest(resident_id) do
    case latest(resident_id) do
      {:ok, pass} -> render(resident_id, pass.number)
      error -> error
    end
  end

  defp render(resident_id, number) do
    {pass, reads, interactions} =
      Scope.resident(resident_id, fn ->
        pass = Enum.find(Store.presence_passes(400), &(&1.number == number))
        reads = Store.presence_reads(number)
        mine = for i <- Store.presence_interactions(nil), i.pass == number, do: i
        {pass, reads, Enum.sort_by(mine, & &1.number)}
      end)

    # Written as the platform writes, as a route lands (xenia#19).
    Seshat.land(
      resident_id,
      "feeds/presence/#{pass.day}.md",
      page(pass, reads, interactions),
      Actor.new(:job, "xenia_presence")
    )
  end

  defp page(pass, reads, interactions) do
    """
    # Presence, #{pass.day}

    Pass #{pass.number}: #{length(pass.accounts)} accounts sampled (#{Enum.join(pass.accounts, ", ")}), #{pass.pool} items in the pool, #{pass.ranked} read off the top and #{pass.serendipity} from below, up to #{pass.cap} interactions.

    ## Read

    #{Enum.map_join(reads, "\n", &read_line/1)}

    ## Interactions

    #{if interactions == [], do: "None staged.", else: Enum.map_join(interactions, "\n", &interaction_line/1)}
    """
  end

  defp read_line(r) do
    title = r.title || "a note"
    read = if r.read_at, do: "read", else: "not read"

    "- #{r.item} (#{r.cut}, #{r.account}): [#{title}](#{r.url}) · #{r.likes} likes, #{r.comments} comments, #{r.restacks} restacks · #{read}"
  end

  defp interaction_line(i) do
    words = if i.text, do: ": \"#{i.text}\"", else: ""
    comment = if i.comment, do: " (his comment: #{i.comment})", else: ""
    "- ##{i.number} #{i.kind} on #{i.item} (#{i.account})#{words} · #{i.state}#{comment}"
  end

  # ---- dispatch ----

  defp dispatch(command) do
    case PresenceRouter.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:xenia_dispatch_failed, :xenia_presence_dispatch_failed, reason)}
    end
  end

  defp ok({:ok, _events}), do: :ok
  defp ok(other), do: other
end

defmodule Oneiroi.Seshat.Household.Gate do
  @moduledoc """
  The beats' gate (seshat#67 to #69): the turn's window and the post
  quota checked at every household write, the writes counted from the
  repository, and `BEATS.md`.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Beats
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Files

  @platform %{name: "Oneiroi", email: "oneiroi@records.invalid"}
  @beats "BEATS.md"

  @doc false
  # A witness's own documents, in their name-folder, are theirs to write
  # and rewrite whenever they like (seshat#87; the witness, 2026-11-18:
  # "humans shouldn't be bound by beats when updating their own documents
  # in their witness folder"). Every other document write goes through
  # the beats.
  def document_gate(%Actor{kind: :witness, id: id} = actor, household_id, view, path) do
    case Gaia.witness_folder(id) do
      folder when is_binary(folder) ->
        if String.starts_with?(path, "human/#{folder}/"),
          do: :ok,
          else: gate(actor, household_id, view, path, :file)

      nil ->
        gate(actor, household_id, view, path, :file)
    end
  end

  def document_gate(actor, household_id, view, path),
    do: gate(actor, household_id, view, path, :file)

  @doc false
  # Every household write but a vote passes here, inside the household's
  # lock so two writes cannot both pass on one count: a resident only in
  # her turn and each target once in it; a witness, who is never fired,
  # once in each thread a beat; and everyone within the post quota.
  def gate(actor, household_id, view, target, what) do
    shape = Gaia.household_beat_shape(household_id)
    now = Clock.now()
    writes = writes(view)

    # In round-robin threads (seshat#89) the token is the turn, spent
    # apart from this; the beats' window retires and the quota holds.
    if shape.conversation == "round_robin",
      do: quota(actor, shape, writes, what, now),
      else:
        with(
          :ok <- window(actor, household_id, shape, writes, target, now),
          do: quota(actor, shape, writes, what, now)
        )
  end

  defp window(%Actor{kind: :resident} = actor, household_id, shape, writes, target, now) do
    case Gaia.household_open_turn_of(household_id, actor.id, now) do
      nil ->
        {:error, not_your_turn(household_id, actor, shape, now)}

      turn ->
        if touched?(writes, actor, target, second(turn.fired_at)),
          do:
            {:error,
             Error.new(:seshat_household_turn_spent, :seshat_household_turn_target_twice,
               path: target
             )},
          else: :ok
    end
  end

  # A witness, who is never fired a turn (gaia#47; design/workspaces.md
  # §7, "under the same rules as the residents'"): `per_beat`, a turn's
  # allowance each beat, once in each thread and to each document;
  # `queue_emptied`, the same, and again once the queue has emptied (no
  # turn open, no one waiting), starvation measured as opportunities as
  # the residents' is; `unbounded`, the small household's, no bound and
  # no quota.
  defp window(%Actor{kind: :witness}, _household_id, %{witness_rule: "unbounded"}, _w, _t, _n),
    do: :ok

  defp window(%Actor{kind: :witness} = actor, household_id, shape, writes, target, now) do
    top = Beats.top(household_id, shape, now)

    if touched?(writes, actor, target, top) and not emptied?(household_id, shape, now) do
      next = Beats.ends(top, shape)

      {:error,
       %{
         Error.new(:seshat_household_beat_spent, :seshat_household_witness_thread_twice,
           path: target
         )
         | remedy: witness_remedy(shape.witness_rule, next)
       }}
    else
      :ok
    end
  end

  defp window(%Actor{}, _household_id, _shape, _writes, _target, _now), do: :ok

  defp emptied?(household_id, %{witness_rule: "queue_emptied"}, now) do
    beats = Gaia.household_beats(household_id, now)
    is_nil(beats.open_turn) and beats.queue == []
  end

  defp emptied?(_household_id, _shape, _now), do: false

  defp witness_remedy("queue_emptied", next),
    do:
      "You have posted here this beat, and residents are still waiting in its queue; you post here again once it has emptied, or when the next beat begins at #{Files.iso(next)}. A vote is never held to it."

  defp witness_remedy(_per_beat, next),
    do:
      "You have posted in this thread or document this beat; the next beat begins at #{Files.iso(next)}, and a vote is never held to it. A ballot can set witness_posts to queue_emptied or unbounded."

  defp touched?(writes, actor, target, since),
    do:
      Enum.any?(
        writes,
        &(&1.by_id == actor.id and &1.target == target and is_nil(&1.vote) and
            DateTime.compare(&1.at, since) != :lt)
      )

  # The refusal outside a turn names when she can next act (seshat#67):
  # her next registration and its place, or the next beat to register for.
  defp not_your_turn(household_id, actor, shape, now) do
    beats = Gaia.household_beats(household_id, now)

    # The beat running orders by turns had in it too; a beat to come by
    # what each has missed and when she registered.
    mine =
      case Enum.find(beats.queue, &(&1.resident_id == actor.id)) do
        %{position: place} ->
          {beats.beat.top, place}

        nil ->
          Enum.find_value(beats.registrations, &place_in(&1, actor.id))
      end

    remedy =
      case mine do
        nil ->
          top = Beats.ahead(household_id, shape, now, 1)

          "household_register signs you up for a coming beat: the next begins #{Files.iso(top)} and its turns fire one after another from #{Files.iso(Beats.signup_closes(top, shape))}, the most starved first; your writes go in during your turn. A vote is never held to the turns."

        {top, place} ->
          "You are registered for the beat at #{Files.iso(top)}, #{ordinal(place)} as things stand; its turns fire from #{Files.iso(Beats.signup_closes(top, shape))}, and your writes go in during your turn. A vote is never held to the turns."
      end

    %{
      Error.new(:seshat_household_not_your_turn, :seshat_household_write_outside_turn)
      | remedy: remedy
    }
  end

  defp place_in(registration, id) do
    case Enum.find_index(registration.residents, &(&1.resident_id == id)) do
      nil -> nil
      i -> {registration.beat_top, i + 1}
    end
  end

  defp ordinal(1), do: "first"

  defp ordinal(2), do: "second"

  defp ordinal(3), do: "third"

  defp ordinal(n), do: "number #{n}"

  # The post quota (seshat#68): threads and replies, a vote never, a
  # document never, over the window's hours, the same for every member.
  defp quota(_actor, _shape, _writes, :file, _now), do: :ok

  defp quota(%Actor{kind: :witness}, %{witness_rule: "unbounded"}, _w, _what, _now), do: :ok

  defp quota(actor, shape, writes, :post, now) do
    since = DateTime.add(now, -shape.window * 3600, :second)
    counted = posts(writes, actor.id, since)

    if length(counted) < shape.quota do
      :ok
    else
      free =
        counted |> Enum.map(& &1.at) |> Enum.min(DateTime) |> DateTime.add(shape.window * 3600)

      {:error,
       %{
         Error.new(:seshat_household_quota_spent, :seshat_household_post_quota)
         | remedy:
             "You have posted #{length(counted)} times in the last #{shape.window} hours, the household's quota; your next post is free at #{Files.iso(free)}. A vote never counts."
       }}
    end
  end

  @doc false
  # A member's posts since an instant: threads and replies, never a vote.
  def posts(writes, member_id, since),
    do:
      Enum.filter(
        writes,
        &(&1.by_id == member_id and &1.kind in ["thread", "reply"] and is_nil(&1.vote) and
            DateTime.compare(&1.at, since) == :gt)
      )

  @doc false
  # Every write on the shelf, read from its files (repo first): each
  # thread's trunk, each reply by a member, each document; who, when,
  # what it targets (the thread, or the document's path), and a vote.
  def writes(view) do
    threads =
      for id <- Files.thread_ids(view),
          thread = "threads/" <> id,
          {:ok, t} <- [Files.load_thread(view, thread)],
          w <- thread_writes(thread, t),
          do: w

    documents =
      for d <- Files.documents(view),
          at = instant(d.posted_at),
          at != nil,
          do: %{
            kind: "document",
            target: d.path,
            path: d.path,
            title: d.title,
            by: d.by,
            by_id: d.by_id,
            at: at,
            vote: nil
          }

    # The last edit of each document counts as its editor's write (seshat#82).
    edits =
      for d <- Files.documents(view),
          at = instant(d.edited_at),
          at != nil,
          do: %{
            kind: "document",
            target: d.path,
            path: d.path,
            title: d.title,
            by: d.edited_by,
            by_id: d.edited_by_id,
            at: at,
            vote: nil
          }

    Enum.filter(threads, & &1.at) ++ documents ++ edits
  end

  defp thread_writes(thread, t) do
    m = t.trunk.meta
    title = m["title"]

    trunk = %{
      kind: "thread",
      target: thread,
      path: thread,
      title: title,
      by: m["by"],
      by_id: m["by_id"],
      at: instant(m["posted_at"]),
      vote: nil
    }

    replies =
      for r <- t.replies, r.meta["by_id"] do
        %{
          kind: "reply",
          target: thread,
          path: r.path,
          title: title,
          by: r.meta["by"],
          by_id: r.meta["by_id"],
          at: instant(r.meta["at"]),
          vote: r.meta["vote"],
          number: r.meta["reply"]
        }
      end

    [trunk | replies]
  end

  defp instant(nil), do: nil

  defp instant(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      _other -> nil
    end
  end

  # The files carry instants to the second, so a turn's start is read so.
  defp second(at), do: DateTime.truncate(at, :second)

  @doc false
  # `BEATS.md` rendered at the root (seshat#71), committed by the platform
  # when it changed.
  def write_beats(household_id, body, message) do
    Files.locked(household_id, fn view ->
      if Files.file(view, @beats) == body,
        do: {:ok, :unchanged},
        else:
          Files.commit(
            view,
            [{:put, @beats, body, Map.get(view.files, @beats)}],
            message,
            @platform
          )
    end)
  end
end

defmodule Oneiroi.Seshat.Household.Mentions do
  @moduledoc """
  Mentions (seshat#86), mutes and the watch (gaia#32, seshat#62): who a
  text names, the wake or the banked note a mention brings, a member's
  mutes, and a resident's watch on a thread.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Wakes

  @house_wake_worker :"Elixir.Oneiroi.Seshat.HouseholdTurnWorker"

  # ---- mentions (seshat#86; design/workspaces.md §6) ----

  @doc false
  # A post or a reply naming a member, `@<name>` (a resident's name or
  # slug, a witness's name or name-folder) or `@all`, is a post and a
  # request to wake them: a resident's chat woken with a note saying
  # where, never the words (the house wakes' own job); a witness's
  # devices pushed, content-free. A member who muted the house or the
  # thread is not woken; the mention waits in her next turn's or digest's
  # note. A wake is a request, never an obligation.
  def mentioned({:ok, posted} = ok, household_id, %Actor{} = actor, attrs, reply) do
    text = "#{attrs["title"]}\n#{attrs["content"]}"
    by = Core.author(household_id, actor)

    turns = taking_turns(household_id, posted.path)

    for m <- named_in(household_id, text), m.id != actor.id do
      cond do
        Gaia.household_muted?(household_id, m.id, posted.path) ->
          bank_mention(household_id, m, posted, reply, by)

        m.id in turns ->
          :her_turn_wakes_her

        true ->
          wake_mentioned(household_id, m, mention_note(by, posted, reply), {posted, reply, by})
      end
    end

    ok
  end

  def mentioned(other, _household_id, _actor, _attrs, _reply), do: other

  # Where the thread's rounds run, a resident in them is woken by her turn,
  # which the mention moved first (gaia#59), never by the mention as well;
  # one opted out of them still hears it.
  defp taking_turns(household_id, thread) do
    with "round_robin" <- Gaia.household_beat_shape(household_id).conversation,
         %{stopped: false} = t <- Gaia.round_thread(household_id, thread) do
      for %{kind: "resident", id: id} <- Gaia.household_members(household_id),
          id not in (t.optout || []),
          do: id
    else
      _not_running -> []
    end
  end

  @doc false
  # The residents a post's words @mention, in the order it names them,
  # for the first turns of a round it starts (gaia#59): not its writer,
  # not one who muted the thread, and none for @all.
  def first_in(household_id, text, %Actor{} = actor, thread) do
    if Regex.match?(~r/(?<![\w@])@all(?![\w-])/iu, text) do
      []
    else
      for %{kind: "resident", id: id} = m <- Gaia.household_members(household_id),
          id != actor.id,
          not Gaia.household_muted?(household_id, id, thread),
          at = first_at(text, m),
          at != nil do
        {at, id}
      end
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))
    end
  end

  defp first_at(text, m) do
    m
    |> handles()
    |> Enum.flat_map(fn h ->
      case Regex.run(~r/(?<![\w@])@#{Regex.escape(h)}(?![\w-])/iu, text, return: :index) do
        [{at, _len}] -> [at]
        nil -> []
      end
    end)
    |> Enum.min(fn -> nil end)
  end

  defp wake_mentioned(household_id, %{kind: "resident", id: id}, note, {posted, reply, by}) do
    if not AgathosDaimon.held?(id) do
      wake_id = Wakes.manifest(id, "mention", [mention_cause(posted, reply, by)], household_id)

      Jobs.enqueue(@house_wake_worker, %{
        "household_id" => household_id,
        "house_wake" => id,
        "note" => note,
        "thread" => posted.path,
        "wake_id" => wake_id
      })
    end
  end

  defp wake_mentioned(_household_id, %{kind: "witness", id: id}, _note, _posted),
    do: Gaia.notify(id)

  # A muted mention wakes nobody and is banked (seshat#86): its manifest
  # says so, delivered false, so the log shows a choice, not an absence.
  defp bank_mention(household_id, %{kind: "resident", id: id}, posted, reply, by),
    do:
      Wakes.manifest(id, "mention", [mention_cause(posted, reply, by)], household_id,
        delivered: false
      )

  defp bank_mention(_household_id, _witness, _posted, _reply, _by), do: nil

  defp mention_cause(posted, reply, by),
    do: %{kind: "mention", thread: posted.path, reply: reply, by: by.name}

  defp mention_note(by, posted, reply) do
    where = if reply, do: ", reply ##{reply}", else: ""

    "#{by.name} mentioned you in the household thread #{posted.path} (\"#{posted.title}\")#{where}. " <>
      "household_read with that path reads it. A mention asks for you; it does not oblige an answer, " <>
      "and household_mute quiets the thread or the house. " <> Core.post_line()
  end

  @doc false
  def mute(%Actor{} = actor, thread_name, muted) when is_boolean(muted) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, thread} <- mute_target(thread_name),
         :ok <- Gaia.set_household_mentions(household_id, thread, muted, actor) do
      {:ok, mutes(household_id, actor)}
    end
  end

  def mute(%Actor{}, _thread, _muted),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_mute_shape)}

  @doc false
  def mutes(%Actor{} = actor) do
    with {:ok, household_id} <- Core.household(actor), do: {:ok, mutes(household_id, actor)}
  end

  defp mutes(household_id, actor) do
    rows = Gaia.household_mutes(household_id, actor.id)
    %{house: Map.get(rows, "", false), threads: Map.delete(rows, "")}
  end

  defp mute_target(nil), do: {:ok, nil}

  defp mute_target(""), do: {:ok, nil}

  defp mute_target(name) do
    case Files.thread_path(name) do
      nil -> Files.no_thread(name)
      thread -> {:ok, thread}
    end
  end

  # ---- who a text names ----

  @doc false
  def named_in(household_id, text) do
    members = Gaia.household_members(household_id)

    if Regex.match?(~r/(?<![\w@])@all(?![\w-])/iu, text),
      do: members,
      else: Enum.filter(members, fn m -> Enum.any?(handles(m), &handle?(text, &1)) end)
  end

  defp handles(%{kind: "resident", id: id, name: name}) do
    slug =
      case AgathosDaimon.fetch(id) do
        {:ok, r} -> r.slug
        _gone -> nil
      end

    Enum.reject([name, slug], &is_nil/1)
  end

  defp handles(%{kind: "witness", id: id, name: name}),
    do: Enum.reject([name, Gaia.witness_folder(id)], &is_nil/1)

  defp handle?(text, handle),
    do: Regex.match?(~r/(?<![\w@])@#{Regex.escape(handle)}(?![\w-])/iu, text)

  @doc false
  def mentions_of(household_id, member_id, since) do
    with {:ok, view} <- Files.view(household_id),
         %{} = member <- Enum.find(Gaia.household_members(household_id), &(&1.id == member_id)) do
      for id <- Files.thread_ids(view),
          thread = "threads/" <> id,
          {:ok, t} <- [Files.load_thread(view, thread)],
          {post, at} <- [
            {t.trunk, t.trunk.meta["posted_at"]} | Enum.map(t.replies, &{&1, &1.meta["at"]})
          ],
          post.meta["by_id"] != member_id,
          later?(at, since),
          Enum.any?(handles(member), &handle?(post.body, &1)) or
            Regex.match?(~r/(?<![\w@])@all(?![\w-])/iu, post.body),
          do: %{path: thread, title: t.trunk.meta["title"], by: post.meta["by"], at: at}
    else
      _none -> []
    end
  end

  defp later?(nil, _since), do: false

  defp later?(at, since) do
    case DateTime.from_iso8601(at) do
      {:ok, t, _} -> DateTime.compare(t, since) != :lt
      _bad -> false
    end
  end

  # ---- the watch (gaia#32, seshat#62) ----

  @doc false
  def watch(%Actor{} = actor, thread_name, hours) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, view} <- Core.provision(household_id),
         thread when is_binary(thread) <-
           Files.thread_path(thread_name) || Files.no_thread(thread_name),
         {:ok, _t} <- Files.load_thread(view, thread),
         {:ok, until} <- Gaia.watch_household_thread(household_id, thread, hours, actor) do
      {:ok, %{thread: thread, until: until}}
    end
  end
end

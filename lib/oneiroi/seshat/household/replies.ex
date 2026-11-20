defmodule Oneiroi.Seshat.Household.Replies do
  @moduledoc """
  Replies (seshat#59, #60, #62, #63): a reply in words or a vote, its
  stamp, the watch's poke, a ballot's waived term, and a refused
  round-robin answer.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Contract
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Gate
  alias Oneiroi.Seshat.Household.Mentions
  alias Oneiroi.Seshat.Household.Wakes
  alias Oneiroi.Seshat.HouseholdRounds

  @watch_actor Actor.new(:job, "household_watch")
  @rounds_actor Actor.new(:job, "household_rounds")
  @ballot_actor Actor.new(:job, "household_ballots")

  @doc false
  def reply(%Actor{} = actor, thread_name, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    text = to_string(attrs["content"] || "")
    vote = attrs["vote"] |> Files.blank() |> downcase()

    with {:ok, household_id} <- Core.household(actor),
         :ok <- may_reply(actor, vote, household_id),
         :ok <- Files.worded(text, vote != nil),
         {:ok, view} <- Core.provision(household_id),
         thread when is_binary(thread) <-
           Files.thread_path(thread_name) || Files.no_thread(thread_name),
         {:ok, t} <- Files.load_thread(view, thread),
         :ok <- cast(household_id, thread, vote, actor),
         by = Core.author(household_id, actor),
         reply = {text, vote, Files.integer(attrs["in_reply_to"])},
         {:ok, written} <-
           Files.locked(household_id, fn view ->
             write_reply(actor, household_id, view, {thread, t}, by, reply)
           end) do
      {rounds, written} = Map.pop(written, :rounds, :none)

      with {:write, spent} <- rounds,
           true <- HouseholdRounds.on?(household_id),
           do:
             HouseholdRounds.after_write(
               household_id,
               thread,
               actor,
               spent,
               Mentions.first_in(household_id, text, actor, thread)
             )

      _ = waive_term(household_id, thread, vote)
      poke(household_id, thread, t, written, by, actor)
      _ = Wakes.wake_house_on_witness(household_id, thread, t, written, actor)

      _ =
        Mentions.mentioned(
          {:ok, %{path: thread, title: t.trunk.meta["title"]}},
          household_id,
          actor,
          attrs,
          written.number
        )

      {:ok, Map.merge(written, %{thread: thread, vote: vote})}
    end
  end

  defp write_reply(actor, household_id, view, {thread, t}, by, {text, vote, in_reply_to}) do
    # A vote is governance, never a post (seshat#67, #68): it waits on no
    # turn and spends no quota. A resident's answer to a house check-in is
    # the check-in's, not the beats' (seshat#75): her first reply there
    # waits on no turn either. Anything else goes through the beats.
    exempt? = vote != nil or Wakes.checkin_answer?(actor, t)

    with :ok <- if(exempt?, do: :ok, else: Gate.gate(actor, household_id, view, thread, :post)),
         {:ok, spent} <- reply_token(exempt?, actor, household_id, thread),
         {:ok, written} <-
           append_reply(actor, household_id, view, {thread, t}, by, {text, vote, in_reply_to}) do
      {:ok, Map.put(written, :rounds, if(vote == nil, do: {:write, spent}, else: :none))}
    end
  end

  # In round-robin threads (seshat#89) a resident's reply where the
  # rounds run spends her live token, before the write it allows.
  defp reply_token(false, actor, household_id, thread) do
    if HouseholdRounds.on?(household_id),
      do: HouseholdRounds.spend_for_reply(actor, household_id, thread),
      else: {:ok, []}
  end

  defp reply_token(true, _actor, _household_id, _thread), do: {:ok, []}

  @doc false
  # After a write, the thread's rounds start (or again, stopped) and every
  # turn issued is woken (seshat#89); nothing under the beats.
  def rounds_after({:ok, %{path: thread}} = ok, household_id, actor, attrs) do
    if HouseholdRounds.on?(household_id) do
      text = "#{attrs["title"]}\n#{attrs["content"]}"
      first = Mentions.first_in(household_id, text, actor, thread)
      HouseholdRounds.after_write(household_id, thread, actor, [], first)
    end

    ok
  end

  def rounds_after(other, _household_id, _actor, _attrs), do: other

  defp append_reply(actor, _household_id, view, {thread, t}, by, {text, vote, in_reply_to}) do
    number = Files.next_reply(view, thread)

    meta =
      [
        {"by", by.name},
        {"by_kind", Atom.to_string(actor.kind)},
        {"by_id", actor.id},
        {"at", Files.iso(Clock.now())},
        {"reply", Integer.to_string(number)}
      ] ++
        Files.optional("in_reply_to", in_reply_to && Integer.to_string(in_reply_to)) ++
        Files.optional("vote", vote) ++
        stamp(view, t)

    body = if text == "", do: "Votes #{vote}.", else: text
    path = Files.reply_path(thread, number, by.name)

    with {:ok, _} <-
           Files.commit(
             view,
             [{:create, path, Files.render(meta, body)}],
             "Reply ##{number} to #{t.trunk.meta["title"]}",
             by
           ),
         do: {:ok, %{path: path, number: number}}
  end

  # A reply on a document post is stamped with the draft it answers
  # (seshat#83): an out-of-date reply says so, whether or not a
  # draft-changed line was ever written.
  defp stamp(view, %{trunk: %{meta: %{"doc" => path}}}),
    do: Files.optional("doc_commit", Files.doc_commit(view, path))

  defp stamp(_view, _t), do: []

  defp downcase(nil), do: nil

  defp downcase(v), do: String.downcase(v)

  defp may_reply(%Actor{kind: :resident}, _vote, _household_id), do: :ok

  defp may_reply(%Actor{kind: :witness}, vote, _household_id) when is_binary(vote), do: :ok

  defp may_reply(%Actor{kind: :witness}, _vote, household_id) do
    if Gaia.household_beat_shape(household_id).witnesses_post,
      do: :ok,
      else:
        {:error, Error.new(:seshat_household_residents_write, :seshat_household_witness_replies)}
  end

  defp may_reply(%Actor{}, _vote, _household_id),
    do: {:error, Error.new(:seshat_household_residents_write, :seshat_household_actor_replies)}

  defp cast(_household_id, _thread, nil, _actor), do: :ok

  defp cast(household_id, thread, vote, actor) do
    case Gaia.household_ballot_for_thread(household_id, thread) do
      nil ->
        {:error, Error.new(:seshat_household_not_a_ballot, :seshat_household_vote_no_ballot)}

      ballot ->
        Gaia.vote_household_ballot(household_id, ballot.number, vote, actor)
    end
  end

  # A yes that makes a ballot unanimous closes it at once, the rest of its
  # term waived (gaia#54, seshat#91); short of every member, nothing.
  defp waive_term(household_id, thread, "yes") do
    case Gaia.household_ballot_for_thread(household_id, thread) do
      %{number: n, closed_at: nil} -> Contract.close_ballot(household_id, n, @ballot_actor)
      _closed_or_none -> :ok
    end
  end

  defp waive_term(_household_id, _thread, _vote), do: :ok

  # The watch's poke (seshat#62): every resident watching the thread now,
  # the author aside, gets a letter to its chat naming the thread and the
  # reply, never the words.
  defp poke(household_id, thread, t, written, by, actor) do
    now = Clock.now()

    for watcher <- Gaia.household_watchers(household_id, thread, now),
        watcher != actor.id do
      text =
        "#{by.name} replied in the household thread #{thread} (\"#{t.trunk.meta["title"]}\"), reply ##{written.number}. " <>
          "household_read with that path reads it. You asked to be told of new replies here for a while; the watch ends on its own."

      Kumbukumbu.send_letter(watcher, nil, %{to: "Oneiroi chat", text: text}, @watch_actor)
    end

    :ok
  end

  @doc false
  def answer_refused(turn, text, error) do
    why = Map.get(error, :remedy) || Map.get(error, :meaning) || "it was refused"

    letter =
      "Your answer in your round-robin turn #{turn.turn_id} in #{turn.thread} could not be posted there for you: #{why} " <>
        "The turn is still yours until #{Files.iso(turn.expires_at)}: household_reply posts it yourself, household_skip passes it. " <>
        "What you said, kept here so it is not lost:\n\n" <> text

    _ =
      Kumbukumbu.send_letter(
        turn.resident_id,
        nil,
        %{to: "Oneiroi chat", text: letter},
        @rounds_actor
      )

    :ok
  end
end

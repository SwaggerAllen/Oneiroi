defmodule Oneiroi.Ethos.Habits do
  @moduledoc """
  Habits (spec §6.17, P38; the behaviours of §6.3 moved here): how the
  resident tends to act, kept as rows that cite the moments in memory
  that evidenced them, so that character survives a change of model and
  never votes as evidence. The command edge, the two scores, and the
  trigger lane the brain's context assembly runs every turn.

  The list is the resident's: it defines, revises and cites; the witness
  affirms, and gives the first ones before first contact as it gives
  every seed. Two scores, never one. Habit strength is a measurement:
  citations under a half-life. Connection strength is a decision trace:
  pins on cited bookmarks, which do not decay, and affirmations and cited
  bookmarks, which do. Both are computed on read and shown to the brain
  as figures beside the words (the author's call), never written into
  the habit's own sentence.

  Retrieval is this system's and choice is the brain's: `how_i_act/2`
  matches the situation against triggers with no model call and returns
  the matching habits with their scores and one or two cited turns, in
  a lane of its own that memory's scoring never pools with.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Ethos.Edge
  alias Oneiroi.Ethos.Error
  alias Oneiroi.Ethos.Lane
  alias Oneiroi.Ethos.Seeds
  alias Oneiroi.Ethos.Store
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope

  @exemplar_chars 400

  @doc "Defines a habit: the resident's, or the witness's before first contact; with `seed_number`, the seed graduates to it in the same call. Returns its number."
  @spec define(String.t(), map(), Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  def define(resident_id, attrs, %Actor{} = actor) when is_map(attrs) do
    with :ok <- may_define(resident_id, actor),
         {:ok, number} <- Oneiroi.AgathosDaimon.mint_id(resident_id, "habit", actor),
         :ok <- graduate_seed(resident_id, attrs[:seed_number], number, attrs[:note], actor) do
      command = %Commands.DefineHabit{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        name: attrs[:name],
        trigger: normalise(attrs[:trigger]),
        stance: attrs[:stance] || "keep",
        seed_number: attrs[:seed_number]
      }

      with {:ok, _} <- Edge.dispatch(command), do: {:ok, number}
    end
  end

  # The ladder is explicit (the author's call): a seed becomes a habit by
  # a receipted graduation, refused until its citations confirm it.
  defp graduate_seed(_resident_id, nil, _number, _note, _actor), do: :ok

  defp graduate_seed(resident_id, seed_number, number, note, actor),
    do: Seeds.graduate(resident_id, seed_number, "habit", number, note || "", actor)

  @doc "The resident revises a habit: new words, trigger or stance; the old stay in the log."
  def change(resident_id, number, attrs, %Actor{} = actor) when is_map(attrs) do
    with :ok <- resident_only(actor) do
      command = %Commands.ChangeHabit{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        name: attrs[:name],
        trigger: normalise(attrs[:trigger]),
        stance: attrs[:stance] || "keep"
      }

      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  @doc "The witness affirms a habit, with a note."
  def affirm(resident_id, number, note, %Actor{} = actor) do
    with :ok <- witness_only(actor) do
      command = %Commands.AffirmHabit{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        number: number
      }

      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  @doc "The habit cites a moment that was one: a turn (by ref) or a bookmark (by number, which must exist), with what the moment changed (P34) or nil."
  def cite(resident_id, number, kind, target_id, %Actor{} = actor, movement \\ nil) do
    with :ok <- resident_only(actor),
         :ok <- Edge.target_exists(resident_id, kind, target_id),
         {:ok, movement} <- Edge.movement(movement) do
      command = %Commands.CiteHabit{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        target_kind: kind,
        target_id: to_string(target_id),
        movement: movement
      }

      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  # ---- reads ----

  @doc "The habits with their scores, ranked by the product of the two, then habit, then number."
  @spec habits(String.t()) :: [Store.Habit.t()]
  def habits(resident_id) do
    pinned =
      resident_id
      |> Kumbukumbu.bookmarks()
      |> Enum.filter(& &1.pinned_at)
      |> Enum.map(&Integer.to_string(&1.number))
      |> MapSet.new()

    Scope.resident(resident_id, fn ->
      now = Clock.now()
      half_life = Config.fetch!(:ethos, :half_life_days)
      citations = Enum.group_by(Store.citations("habit"), & &1.number)
      affirmations = Enum.group_by(Store.affirmations(), & &1.number)

      Store.habits()
      |> Enum.map(fn h ->
        mine = Map.get(citations, h.number, [])
        affirmed = Map.get(affirmations, h.number, [])

        %{
          h
          | habit: habit(mine, now, half_life),
            connection: connection(mine, affirmed, pinned, now, half_life),
            citations: length(mine),
            days: mine |> Enum.map(&DateTime.to_date(&1.at)) |> Enum.uniq() |> length(),
            affirmations: length(affirmed)
        }
      end)
      |> Enum.sort_by(&{-&1.habit * &1.connection, -&1.habit, &1.number})
    end)
  end

  @doc "The citations of one habit, newest first."
  def citations(resident_id, number),
    do:
      Scope.resident(resident_id, fn ->
        Enum.filter(Store.citations("habit"), &(&1.number == number))
      end)

  @doc """
  What the brain is shown this turn (spec §6.17, the trigger lane): the
  habits whose trigger the situation matches, and with an `actor` in the
  situation the habits and open seeds the vector lane finds near its
  words (`Oneiroi.Ethos.Lane`). `situation` carries `text` (the
  witness's words), `tags` (on the conversation), `at` (the instant, for
  the time of day) and `actor` (who the query is billed to; absent, the
  match is deterministic alone). Each match comes with its scores, who
  affirmed it, and up to `ETHOS_EXEMPLARS` cited turns with the
  resident's own words; the open seeds are counted, and the nearest
  few named, never loaded whole.
  """
  @spec how_i_act(String.t(), map()) :: %{
          text: String.t(),
          numbers: [pos_integer()],
          count: non_neg_integer(),
          seeds: non_neg_integer(),
          near: [pos_integer()],
          near_seeds: [pos_integer()]
        }
  def how_i_act(resident_id, situation) do
    all = habits(resident_id)
    matched = Enum.filter(all, &matches?(&1.trigger, situation))
    lane = lane(resident_id, situation)
    near = Enum.reject(lane.habits, fn n -> Enum.any?(matched, &(&1.number == n)) end)
    matches = matched ++ Enum.filter(all, &(&1.number in near))
    limit = Config.fetch!(:ethos, :exemplars)

    {sections, open} =
      Scope.resident(resident_id, fn ->
        affirmations = Enum.group_by(Store.affirmations(), & &1.number)
        citations = Enum.group_by(Store.citations("habit"), & &1.number)

        {Enum.map(
           matches,
           &section(
             &1,
             Map.get(affirmations, &1.number, []),
             Map.get(citations, &1.number, []),
             limit
           )
         ), Enum.count(Store.seeds(), &(&1.state == "open"))}
      end)

    room = room_keys(resident_id, situation)
    sections = sections |> Enum.map(&exemplars(&1, resident_id, room)) |> mark_near(matches, near)

    text =
      case {sections, open} do
        {[], 0} ->
          ""

        _ ->
          Enum.join(
            [
              "# How I act\n\nWhat this situation has drawn out of me before. Whether to act on it is mine to decide."
              | sections
            ] ++ seeds_line(open, lane.seeds),
            "\n\n"
          )
      end

    %{
      text: text,
      numbers: Enum.map(matches, & &1.number),
      count: length(matches),
      seeds: open,
      near: near,
      near_seeds: Enum.map(lane.seeds, &elem(&1, 0))
    }
  end

  # The vector lane runs only for a query somebody is billed for; the
  # refresh before it embeds what changed and nothing when nothing did.
  defp lane(resident_id, %{actor: %Actor{} = actor} = situation) do
    _ = Lane.refresh(resident_id, actor)
    Lane.nearest(resident_id, Map.get(situation, :text) || "", actor)
  end

  defp lane(_resident_id, _situation), do: %{habits: [], seeds: []}

  # A habit the lane found and the trigger did not says so, so the brain
  # reads the match as nearness and not as its own rule firing.
  defp mark_near(sections, matches, near) do
    Enum.zip_with(sections, matches, fn section, h ->
      if h.number in near,
        do: String.replace(section, "\n", " (near this, by the lane)\n", global: false),
        else: section
    end)
  end

  @doc "Whether a trigger matches a situation: any word in the text, any tag present, or the time of day."
  @spec matches?(map(), map()) :: boolean()
  def matches?(trigger, situation) when is_map(trigger) do
    text = String.downcase(Map.get(situation, :text) || "")
    tags = Map.get(situation, :tags) || []
    time = time_of_day(Map.get(situation, :at))

    Enum.any?(
      Map.get(trigger, "words", []),
      &(&1 != "" and String.contains?(text, String.downcase(&1)))
    ) or
      Enum.any?(Map.get(trigger, "tags", []), &(&1 in tags)) or
      time in Map.get(trigger, "times", [])
  end

  @doc "The time of day a trigger names: morning (05-11), afternoon (12-16), evening (17-21), night, in UTC until the resident has a timezone (spec §6.7)."
  @spec time_of_day(DateTime.t() | nil) :: String.t() | nil
  def time_of_day(%DateTime{hour: h}) when h in 5..11, do: "morning"
  def time_of_day(%DateTime{hour: h}) when h in 12..16, do: "afternoon"
  def time_of_day(%DateTime{hour: h}) when h in 17..21, do: "evening"
  def time_of_day(%DateTime{}), do: "night"
  def time_of_day(_none), do: nil

  # ---- scores ----

  defp decay(at, now, half_life) do
    age_days = max(DateTime.diff(now, at, :second), 0) / 86_400
    :math.pow(0.5, age_days / half_life)
  end

  defp habit(citations, now, half_life),
    do: citations |> Enum.map(&decay(&1.at, now, half_life)) |> Enum.sum() |> round3()

  defp connection(citations, affirmations, pinned, now, half_life) do
    on_bookmarks = Enum.filter(citations, &(&1.target_kind == "bookmark"))
    {pinned_ones, rest} = Enum.split_with(on_bookmarks, &MapSet.member?(pinned, &1.target_id))

    (length(pinned_ones) +
       Enum.sum(Enum.map(rest, &decay(&1.at, now, half_life))) +
       Enum.sum(Enum.map(affirmations, &decay(&1.at, now, half_life))))
    |> round3()
  end

  # A sum over nothing is the integer zero; the score is always a float.
  defp round3(n), do: Float.round(n / 1, 3)

  # ---- the section the brain reads ----

  # The header with the counts as figures (the author's call: without
  # them every habit weighs the same), and the cited turns to read in
  # the next step, outside the scope's transaction.
  defp section(h, affirmations, citations, limit) do
    affirmed =
      case affirmations do
        [] ->
          "not yet affirmed"

        [a | _] ->
          "affirmed #{length(affirmations)}x by my #{a.by_kind || "witness"}, last: \"#{a.note}\""
      end

    header =
      "## ##{h.number} #{h.name} (#{h.stance})\n" <>
        "Trigger: #{trigger_words(h.trigger)}. Habit #{h.habit}, connection #{h.connection}, cited #{h.citations}x over #{h.days} #{plural(h.days, "day")}; #{affirmed}."

    turns = citations |> Enum.filter(&(&1.target_kind == "turn")) |> Enum.take(limit)
    {header, turns}
  end

  # The room (spec §6.3, P23): a situation with a session names it, and
  # a cited turn from a session outside it is not shown, however strong
  # the habit; without one, every cited turn may be.
  defp room_keys(resident_id, %{session_key: key}) when is_binary(key),
    do: Kumbukumbu.room(resident_id, key).keys

  defp room_keys(_resident_id, _situation), do: nil

  defp exemplars({header, turns}, resident_id, room) do
    lines =
      turns
      |> Enum.map(&exemplar(resident_id, &1, room))
      |> Enum.reject(&is_nil/1)

    Enum.join([header | lines], "\n")
  end

  defp exemplar(resident_id, %{target_id: turn_ref} = citation, room) do
    case resident_id
         |> Kumbukumbu.turn_messages(turn_ref)
         |> Enum.find(&(&1.role == "assistant" and (is_nil(room) or &1.session_key in room))) do
      nil ->
        nil

      m ->
        "- turn #{turn_ref}: \"#{String.slice(m.content, 0, @exemplar_chars)}\"" <>
          movement_line(citation.movement)
    end
  end

  # What the cited moment changed (P34), on the line under the words,
  # so the brain reads the movement beside the moment and never in its
  # place.
  defp movement_line(nil), do: ""

  defp movement_line(%{} = movement) do
    parts =
      [{"Stance: ", "stance"}, {"Intention: ", "intention"}, {"Resumes at: ", "resume"}]
      |> Enum.reject(fn {_label, k} -> movement[k] in [nil, ""] end)
      |> Enum.map(fn {label, k} -> label <> movement[k] end)

    if parts == [], do: "", else: "\n  Moved: " <> Enum.join(parts, ". ") <> "."
  end

  defp seeds_line(0, _near), do: []

  defp seeds_line(open, near) do
    count =
      "#{open} open #{plural(open, "seed")} of who I might be becoming; seed_list reads them."

    case near do
      [] ->
        [count]

      near ->
        [
          count <>
            " Near this: " <> Enum.map_join(near, "; ", fn {n, text} -> "##{n} #{text}" end)
        ]
    end
  end

  defp trigger_words(trigger) do
    trigger
    |> Enum.reject(fn {_k, v} -> v == [] end)
    |> Enum.map_join("; ", fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)
  end

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  # ---- helpers ----

  # The resident's list (spec §6.3): a witness defines only before first
  # contact, as it gives every seed.
  defp may_define(_resident_id, %Actor{kind: :resident}), do: :ok

  defp may_define(resident_id, %Actor{kind: :witness}) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, %{first_contact_at: nil}} ->
        :ok

      _other ->
        {:error,
         Error.new(:ethos_not_the_resident, :ethos_habits_witness_after_first_contact,
           since: "first contact"
         )}
    end
  end

  defp may_define(_resident_id, %Actor{}),
    do: {:error, Error.new(:ethos_not_the_resident, :ethos_habits_define_not_a_party)}

  defp resident_only(%Actor{kind: :resident}), do: :ok

  defp resident_only(%Actor{}),
    do: {:error, Error.new(:ethos_not_the_resident, :ethos_habits_resident_only)}

  defp witness_only(%Actor{kind: :witness}), do: :ok

  defp witness_only(%Actor{}),
    do: {:error, Error.new(:ethos_not_the_witness, :ethos_habits_witness_only)}

  # String keys and lists, whatever the caller sent: the aggregate and the
  # JSON column hold one shape.
  defp normalise(%{} = trigger) do
    Map.new(trigger, fn {k, v} -> {to_string(k), v |> List.wrap() |> Enum.map(&to_string/1)} end)
  end

  defp normalise(_other), do: nil
end

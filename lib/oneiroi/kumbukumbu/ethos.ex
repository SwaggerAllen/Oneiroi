defmodule Oneiroi.Kumbukumbu.Ethos do
  @moduledoc """
  Behaviours (spec §6.3, F55; `systems/kumbukumbu.md` #13): how the
  resident tends to act, kept as rows so that character survives a change
  of model. The command edge, the two scores, and the retrieval the
  brain's context assembly runs every turn.

  The list is the resident's: it defines, revises and enacts; the witness
  affirms, and gives the first ones before first contact as it gives
  every seed. Two scores, never one. Habit strength is a measurement:
  enactments under a half-life. Connection strength is a decision trace:
  pins on enacting bookmarks, which do not decay, and affirmations and
  enacting bookmarks, which do. Both are computed on read here; the
  nightly recomputation is the judgement phase's.

  Retrieval is memory's and choice is the brain's: `how_i_act/2` matches
  the situation against triggers with no model call and returns the
  matching behaviours with their scores and one or two enacting turns.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Memory
  alias Oneiroi.Kumbukumbu.MemoryCommands, as: Commands
  alias Oneiroi.Kumbukumbu.MemoryRouter, as: Router
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  @exemplar_chars 400

  @doc "Defines a behaviour: the resident's, or the witness's before first contact. Returns its number."
  @spec define(String.t(), map(), Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  def define(resident_id, attrs, %Actor{} = actor) when is_map(attrs) do
    with :ok <- may_define(resident_id, actor),
         {:ok, number} <- Oneiroi.AgathosDaimon.mint_id(resident_id, "behaviour", actor) do
      command = %Commands.DefineBehaviour{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        name: attrs[:name],
        trigger: normalise(attrs[:trigger]),
        stance: attrs[:stance] || "keep"
      }

      with {:ok, _} <- dispatch(command), do: {:ok, number}
    end
  end

  @doc "The resident revises a behaviour: new words, trigger or stance; the old stay in the log."
  def change(resident_id, number, attrs, %Actor{} = actor) when is_map(attrs) do
    with :ok <- resident_only(actor) do
      command = %Commands.ChangeBehaviour{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        name: attrs[:name],
        trigger: normalise(attrs[:trigger]),
        stance: attrs[:stance] || "keep"
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "The witness affirms a behaviour, with a note."
  def affirm(resident_id, number, note, %Actor{} = actor) do
    with :ok <- witness_only(actor) do
      command = %Commands.AffirmBehaviour{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        number: number
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "The resident records an enactment on a turn (by ref) or a bookmark (by number)."
  def enact(resident_id, number, kind, target_id, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.EnactBehaviour{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        target_kind: kind,
        target_id: to_string(target_id)
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  # ---- reads ----

  @doc "The behaviours with their scores, ranked by the product of the two, then habit, then number."
  @spec behaviours(String.t()) :: [Store.Behaviour.t()]
  def behaviours(resident_id) do
    Scope.resident(resident_id, fn ->
      now = Clock.now()
      half_life = Config.fetch!(:kumbukumbu, :half_life_days)
      enactments = Enum.group_by(Store.enactments(), & &1.number)
      affirmations = Enum.group_by(Store.affirmations(), & &1.number)
      pinned = Store.pinned_numbers() |> Enum.map(&Integer.to_string/1) |> MapSet.new()

      Store.behaviours()
      |> Enum.map(fn b ->
        mine = Map.get(enactments, b.number, [])
        affirmed = Map.get(affirmations, b.number, [])

        %{
          b
          | habit: habit(mine, now, half_life),
            connection: connection(mine, affirmed, pinned, now, half_life),
            enactments: length(mine),
            affirmations: length(affirmed)
        }
      end)
      |> Enum.sort_by(&{-&1.habit * &1.connection, -&1.habit, &1.number})
    end)
  end

  @doc "The enactments of one behaviour, newest first."
  def enactments(resident_id, number),
    do:
      Scope.resident(resident_id, fn ->
        Enum.filter(Store.enactments(), &(&1.number == number))
      end)

  @doc """
  What the brain is shown this turn (spec §6.3): the behaviours whose
  trigger the situation matches. `situation` carries `text` (the witness's
  words), `tags` (on the conversation) and `at` (the instant, for the time
  of day). Each match comes with its scores, who affirmed it, and up to
  `KUMBUKUMBU_EXEMPLARS` enacting turns with the resident's own words.
  """
  @spec how_i_act(String.t(), map()) :: %{
          text: String.t(),
          numbers: [pos_integer()],
          count: non_neg_integer()
        }
  def how_i_act(resident_id, situation) do
    matches = resident_id |> behaviours() |> Enum.filter(&matches?(&1.trigger, situation))

    sections =
      Scope.resident(resident_id, fn ->
        affirmations = Enum.group_by(Store.affirmations(), & &1.number)
        limit = Config.fetch!(:kumbukumbu, :exemplars)
        Enum.map(matches, &section(&1, Map.get(affirmations, &1.number, []), limit))
      end)

    text =
      case sections do
        [] ->
          ""

        _ ->
          Enum.join(
            [
              "# How I act\n\nWhat this situation has drawn out of me before. Whether to act on it is mine to decide."
              | sections
            ],
            "\n\n"
          )
      end

    %{text: text, numbers: Enum.map(matches, & &1.number), count: length(matches)}
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

  defp habit(enactments, now, half_life),
    do: enactments |> Enum.map(&decay(&1.at, now, half_life)) |> Enum.sum() |> round3()

  defp connection(enactments, affirmations, pinned, now, half_life) do
    on_bookmarks = Enum.filter(enactments, &(&1.target_kind == "bookmark"))
    {pinned_ones, rest} = Enum.split_with(on_bookmarks, &MapSet.member?(pinned, &1.target_id))

    (length(pinned_ones) +
       Enum.sum(Enum.map(rest, &decay(&1.at, now, half_life))) +
       Enum.sum(Enum.map(affirmations, &decay(&1.at, now, half_life))))
    |> round3()
  end

  # A sum over nothing is the integer zero; the score is always a float.
  defp round3(n), do: Float.round(n / 1, 3)

  # ---- the section the brain reads ----

  defp section(b, affirmations, limit) do
    turns =
      Store.enactments()
      |> Enum.filter(&(&1.number == b.number and &1.target_kind == "turn"))
      |> Enum.take(limit)
      |> Enum.map(&exemplar/1)
      |> Enum.reject(&is_nil/1)

    affirmed =
      case affirmations do
        [] ->
          "not yet affirmed"

        [a | _] ->
          "affirmed #{length(affirmations)}x by my #{a.by_kind || "witness"}, last: \"#{a.note}\""
      end

    header =
      "## ##{b.number} #{b.name} (#{b.stance})\n" <>
        "Trigger: #{trigger_words(b.trigger)}. Habit #{b.habit}, connection #{b.connection}; #{affirmed}."

    Enum.join([header | turns], "\n")
  end

  defp exemplar(%{target_id: turn_ref}) do
    case turn_ref |> Store.turn_messages() |> Enum.find(&(&1.role == "assistant")) do
      nil -> nil
      m -> "- turn #{turn_ref}: \"#{String.slice(m.content, 0, @exemplar_chars)}\""
    end
  end

  defp trigger_words(trigger) do
    trigger
    |> Enum.reject(fn {_k, v} -> v == [] end)
    |> Enum.map_join("; ", fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)
  end

  # ---- helpers ----

  # The resident's list (spec §6.3): a witness defines only before first
  # contact, as it gives every seed.
  defp may_define(_resident_id, %Actor{kind: :resident}), do: :ok

  defp may_define(resident_id, %Actor{kind: :witness}) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, %{first_contact_at: nil}} -> :ok
      _other -> {:error, Error.new(:kumbukumbu_not_the_resident, since: "first contact")}
    end
  end

  defp may_define(_resident_id, %Actor{}), do: {:error, Error.new(:kumbukumbu_not_the_resident)}

  defp resident_only(%Actor{kind: :resident}), do: :ok
  defp resident_only(%Actor{}), do: {:error, Error.new(:kumbukumbu_not_the_resident)}

  defp witness_only(%Actor{kind: :witness}), do: :ok
  defp witness_only(%Actor{}), do: {:error, Error.new(:kumbukumbu_not_the_witness)}

  # String keys and lists, whatever the caller sent: the aggregate and the
  # JSON column hold one shape.
  defp normalise(%{} = trigger) do
    Map.new(trigger, fn {k, v} -> {to_string(k), v |> List.wrap() |> Enum.map(&to_string/1)} end)
  end

  defp normalise(_other), do: nil

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, :no_such_behaviour} ->
        {:error, Error.new(:kumbukumbu_no_such_behaviour, number: command.number)}

      {:error, :name_invalid} ->
        {:error, Error.new(:kumbukumbu_line_invalid, limit: Memory.line_limit())}

      {:error, :stance_invalid} ->
        {:error, Error.new(:kumbukumbu_stance_invalid, stances: Memory.stances())}

      {:error, :trigger_invalid} ->
        {:error, Error.new(:kumbukumbu_trigger_invalid, times: Memory.times())}

      {:error, :target_invalid} ->
        {:error,
         Error.new(:kumbukumbu_target_invalid, kind: command.target_kind, id: command.target_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule Oneiroi.Sunna.Backfill do
  @moduledoc """
  The memory backfill (sunna#59; the witness, 2026-11-13: "we need to do
  Scene backfill so we can do domains by scene retroactively … people and
  portraits … all sessions with both of our domain lists"). Lily does the
  work, as she does each night: the days before the night's passes
  existed, or before a pass was built, run through them one day at a
  time, oldest first, each pass a housekeeping conversation of her own.

  A day's chain: **scenes** (the day's Oneiroi chat grouped into scenes
  with `scene_write`, skipped when the day is already closed), then
  **domains** (each of the day's conversations named into domains with
  `domain_tag`, scene by scene in the chat and stretch by stretch
  elsewhere, from his domains and hers: those days ran with every memory
  in reach, so they are tagged with both, P23-R1), then **people** (the
  night's people pass for that day, sunna#57, whose seeds become
  portraits, his among them). Then the next day, a minute later, through
  the last. Each pass carries on while a turn runs out of tool rounds, up
  to its bound, and one that fails or has nothing to do passes on, as at
  night. The notes are the brain's (the wake port's `backfill_note/5`),
  which reads the scene rows and the transcripts' shape.

  The witness starts it over a range of days, with the domain lists, and
  stops it; what runs next is read off its queued job. Billed under
  `chat`, as the night's housekeeping is.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Error

  # The labels pass is the platform's, no model (kumbukumbu#101): last,
  # so it reads the day's domains as named and its portraits as written.
  @passes ["scenes", "domains", "people", "labels"]
  @worker "Oneiroi.Sunna.BackfillWorker"
  @actor Actor.new(:job, "sunna_backfill")
  @between_days_s 60
  @waiting ["available", "scheduled", "retryable"]
  # How long a pass whose turn outlasted the wake's wait is given to
  # finish before the next begins (sunna#60): a guess, ten minutes, the
  # longest pass seen so far having run past five.
  @outlasted_s 600
  @slugs 30

  @doc """
  Starts the backfill over `from..to` (ISO days, `to` before today in her
  zone), with the witness's and her domain slugs as the lists she names
  from; a running backfill is replaced. `lists["passes"]` names the
  passes each day runs, in their own order (sunna#79; the witness,
  2026-11-21: "we should be able to run just one kind of pass at a
  time"), all three when absent. `{:ok, days}`.
  """
  @spec start(String.t(), String.t(), String.t(), map(), Actor.t()) ::
          {:ok, non_neg_integer()} | {:error, Oneiroi.Error.t()}
  def start(resident_id, from, to, lists, %Actor{}) do
    with {:ok, first} <- Date.from_iso8601(to_string(from)),
         {:ok, last} <- Date.from_iso8601(to_string(to)),
         true <- Date.compare(first, last) != :gt,
         true <- Date.compare(last, today(resident_id)) == :lt,
         {:ok, his} <- slugs(lists["his"]),
         {:ok, hers} <- slugs(lists["hers"]),
         {:ok, passes} <- passes(lists["passes"]),
         # Only declared domains (agathos-daimon#57): his life's, then hers.
         :ok <- declared(resident_id, :witness, his),
         :ok <- declared(resident_id, :resident, hers),
         :ok <- cleared(resident_id, passes) do
      stop(resident_id)

      # The labels pass alone runs once, on the last day (kumbukumbu#101).
      start = if passes == ["labels"], do: last, else: first

      {:ok, _job} =
        enqueue(%{
          "resident_id" => resident_id,
          "from" => Date.to_iso8601(first),
          "day" => Date.to_iso8601(start),
          "to" => Date.to_iso8601(last),
          "pass" => hd(passes),
          "passes" => passes,
          "n" => 1,
          "session_key" => nil,
          "his" => his,
          "hers" => hers
        })

      {:ok, Date.diff(last, first) + 1}
    else
      {:error, _} = undeclared -> undeclared
      _invalid -> {:error, Error.new(:sunna_backfill_invalid, :sunna_backfill_start_invalid)}
    end
  end

  @doc "Stops the backfill: its queued and scheduled job is cancelled; a turn already running finishes."
  @spec stop(String.t()) :: :ok
  def stop(resident_id) do
    _ = Scope.platform(fn -> Oban.cancel_all_jobs(pending(resident_id)) end)
    :ok
  end

  @doc "Where the backfill is: the day and pass it runs or waits on, and its last day; nil when none is under way."
  @spec status(String.t()) :: map() | nil
  def status(resident_id) do
    case Scope.platform(fn ->
           Repo.one(
             # The running pass too (sunna#60): a pass runs for minutes,
             # and read off the waiting jobs alone the card said nothing
             # was under way the whole time it was.
             from(j in jobs(resident_id, ["executing" | @waiting]),
               order_by: [desc: j.id],
               limit: 1,
               select: j.args
             )
           )
         end) do
      nil ->
        nil

      args ->
        %{
          day: args["day"],
          pass: args["pass"],
          turn: args["n"],
          to: args["to"],
          passes: args["passes"] || @passes,
          his: args["his"],
          hers: args["hers"]
        }
    end
  end

  defp pending(resident_id), do: jobs(resident_id, @waiting)

  defp jobs(resident_id, states),
    do:
      from(j in Oban.Job,
        where:
          j.worker == @worker and j.state in ^states and
            fragment("? @> ?", j.args, ^%{"resident_id" => resident_id})
      )

  @doc false
  # The labels pass closes the citation graph once, over the whole range,
  # on its last day (kumbukumbu#101): a record's citations reach records
  # written after it, so day by day it would read them before they were
  # named. Earlier days pass it by.
  def run(%{"resident_id" => id, "day" => day, "to" => day, "pass" => "labels"} = args) do
    port = Config.fetch!(:sunna, :wake)

    if Code.ensure_loaded?(port) and function_exported?(port, :backfill_labels, 3),
      do: port.backfill_labels(id, args["from"] || day, day)

    next(args)
    :ok
  end

  def run(%{"pass" => "labels"} = args) do
    next(args)
    :ok
  end

  def run(%{"resident_id" => id, "day" => day, "pass" => pass, "n" => n} = args)
      when pass in @passes do
    port = Config.fetch!(:sunna, :wake)

    with true <- Code.ensure_loaded?(port) and function_exported?(port, :backfill_note, 5),
         {:ok, note} <- port.backfill_note(id, pass, day, n, Map.take(args, ["his", "hers"])),
         {:ok, key} <- session(id, args["session_key"]),
         {:ok, result} <- port.wake(id, key, note, :chat) do
      if (Map.get(result, :rounds_spent) || left?(port, id, pass, day)) && n < turns(pass),
        do: enqueue(%{args | "n" => n + 1, "session_key" => key}),
        else: next(args)
    else
      # Her turn ran past the wait and runs on (brain#97): the chain goes
      # on once it has had time to finish, never crashing on it
      # (sunna#60).
      {:error, %{kind: :brain_wake_outlasted}} ->
        next(args, schedule_in: @outlasted_s)

      # Nothing to do, or a failure: the chain goes on, as at night.
      _skipped_or_failed ->
        next(args)
    end

    :ok
  end

  defp next(%{"pass" => pass, "day" => day, "to" => to} = args, opts \\ []) do
    # A job queued before sunna#79 carries no list: all three.
    passes = Map.get(args, "passes") || @passes

    case Enum.drop_while(passes, &(&1 != pass)) do
      [_this, following | _] ->
        enqueue(%{args | "pass" => following, "n" => 1, "session_key" => nil}, opts)

      _last ->
        tomorrow = day |> Date.from_iso8601!() |> Date.add(1)

        if Date.compare(tomorrow, Date.from_iso8601!(to)) != :gt do
          enqueue(
            %{
              args
              | "day" => Date.to_iso8601(tomorrow),
                "pass" => hd(passes),
                "n" => 1,
                "session_key" => nil
            },
            schedule_in: max(@between_days_s, Keyword.get(opts, :schedule_in, 0))
          )
        else
          {:ok, :done}
        end
    end
  end

  # The domains pass is done when every conversation of the day has a
  # name (sunna#89), not when a turn ends with rounds to spare: a turn
  # that stopped early left whole conversations untagged.
  defp left?(port, id, "domains", day) do
    function_exported?(port, :backfill_left, 2) and port.backfill_left(id, day) != []
  end

  defp left?(_port, _id, _pass, _day), do: false

  # A backfill that names domains starts from none undeclared
  # (kumbukumbu#106, sunna#89): every message, conversation and
  # classification of hers in a domain her agreement does not declare
  # goes back to the common room before the first day.
  defp cleared(resident_id, passes) do
    if "domains" in passes,
      do: Kumbukumbu.clear_undeclared_domains(resident_id, @actor),
      else: :ok
  end

  defp turns("scenes"), do: Config.fetch!(:sunna, :backfill_scene_turns)
  defp turns("domains"), do: Config.fetch!(:sunna, :backfill_domain_turns)
  defp turns("people"), do: Config.fetch!(:sunna, :people_turns)
  defp turns("labels"), do: 1

  defp session(_id, key) when is_binary(key), do: {:ok, key}

  defp session(id, nil) do
    with {:ok, row} <- AgathosDaimon.fetch(id) do
      Kumbukumbu.open_session(id, "housekeeping", "brain", List.wrap(row.account_id), @actor)
    end
  end

  defp enqueue(args, opts \\ []),
    do: Jobs.enqueue(Module.concat([Oneiroi, Sunna, BackfillWorker]), args, opts)

  defp today(resident_id) do
    zone = Local.zone(resident_id)
    Clock.now() |> DateTime.shift_zone!(zone) |> DateTime.to_date()
  end

  @slug ~r/\A[a-z][a-z0-9-]{1,31}\z/

  defp declared(resident_id, whose, slugs) do
    person =
      case {whose, AgathosDaimon.fetch(resident_id)} do
        {:resident, _} -> "resident:" <> resident_id
        {:witness, {:ok, %{account_id: account}}} -> "account:" <> to_string(account)
        _none -> nil
      end

    case Enum.reject(slugs, &AgathosDaimon.domain_declared?(resident_id, person, &1)) do
      [] ->
        :ok

      undeclared ->
        {:error,
         Error.new(:sunna_backfill_invalid, :sunna_backfill_start_undeclared,
           undeclared: undeclared
         )}
    end
  end

  defp passes(nil), do: {:ok, @passes}

  defp passes(list) when is_list(list) do
    given = list |> Enum.map(&to_string/1) |> Enum.uniq()

    if given != [] and Enum.all?(given, &(&1 in @passes)),
      do: {:ok, Enum.filter(@passes, &(&1 in given))},
      else: :error
  end

  defp passes(_other), do: :error

  defp slugs(nil), do: {:ok, []}

  defp slugs(list) when is_list(list) and length(list) <= @slugs do
    trimmed = list |> Enum.map(&(&1 |> to_string() |> String.trim())) |> Enum.uniq()
    if Enum.all?(trimmed, &Regex.match?(@slug, &1)), do: {:ok, trimmed}, else: :error
  end

  defp slugs(_other), do: :error
end

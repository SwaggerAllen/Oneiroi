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

  @passes ["scenes", "domains", "people"]
  @worker "Oneiroi.Sunna.BackfillWorker"
  @actor Actor.new(:job, "sunna_backfill")
  @between_days_s 60
  @slugs 30

  @doc """
  Starts the backfill over `from..to` (ISO days, `to` before today in her
  zone), with the witness's and her domain slugs as the lists she names
  from; a running backfill is replaced. `{:ok, days}`.
  """
  @spec start(String.t(), String.t(), String.t(), map(), Actor.t()) ::
          {:ok, non_neg_integer()} | {:error, Oneiroi.Error.t()}
  def start(resident_id, from, to, lists, %Actor{}) do
    with {:ok, first} <- Date.from_iso8601(to_string(from)),
         {:ok, last} <- Date.from_iso8601(to_string(to)),
         true <- Date.compare(first, last) != :gt,
         true <- Date.compare(last, today(resident_id)) == :lt,
         {:ok, his} <- slugs(lists["his"]),
         {:ok, hers} <- slugs(lists["hers"]) do
      stop(resident_id)

      {:ok, _job} =
        enqueue(%{
          "resident_id" => resident_id,
          "day" => Date.to_iso8601(first),
          "to" => Date.to_iso8601(last),
          "pass" => "scenes",
          "n" => 1,
          "session_key" => nil,
          "his" => his,
          "hers" => hers
        })

      {:ok, Date.diff(last, first) + 1}
    else
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
             from(j in pending(resident_id), order_by: [desc: j.id], limit: 1, select: j.args)
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
          his: args["his"],
          hers: args["hers"]
        }
    end
  end

  defp pending(resident_id),
    do:
      from(j in Oban.Job,
        where:
          j.worker == @worker and j.state in ["available", "scheduled", "retryable"] and
            fragment("? @> ?", j.args, ^%{"resident_id" => resident_id})
      )

  @doc false
  def run(%{"resident_id" => id, "day" => day, "pass" => pass, "n" => n} = args)
      when pass in @passes do
    port = Config.fetch!(:sunna, :wake)

    with true <- Code.ensure_loaded?(port) and function_exported?(port, :backfill_note, 5),
         {:ok, note} <- port.backfill_note(id, pass, day, n, Map.take(args, ["his", "hers"])),
         {:ok, key} <- session(id, args["session_key"]),
         {:ok, result} <- port.wake(id, key, note, :chat) do
      if Map.get(result, :rounds_spent) && n < turns(pass),
        do: enqueue(%{args | "n" => n + 1, "session_key" => key}),
        else: next(args)
    else
      # Nothing to do, or a failure: the chain goes on, as at night.
      _skipped_or_failed -> next(args)
    end

    :ok
  end

  defp next(%{"pass" => pass, "day" => day, "to" => to} = args) do
    case Enum.drop_while(@passes, &(&1 != pass)) do
      [_this, following | _] ->
        enqueue(%{args | "pass" => following, "n" => 1, "session_key" => nil})

      _last ->
        tomorrow = day |> Date.from_iso8601!() |> Date.add(1)

        if Date.compare(tomorrow, Date.from_iso8601!(to)) != :gt do
          enqueue(
            %{
              args
              | "day" => Date.to_iso8601(tomorrow),
                "pass" => "scenes",
                "n" => 1,
                "session_key" => nil
            },
            schedule_in: @between_days_s
          )
        else
          {:ok, :done}
        end
    end
  end

  defp turns("scenes"), do: Config.fetch!(:sunna, :backfill_scene_turns)
  defp turns("domains"), do: Config.fetch!(:sunna, :backfill_domain_turns)
  defp turns("people"), do: Config.fetch!(:sunna, :people_turns)

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

  defp slugs(nil), do: {:ok, []}

  defp slugs(list) when is_list(list) and length(list) <= @slugs do
    trimmed = list |> Enum.map(&(&1 |> to_string() |> String.trim())) |> Enum.uniq()
    if Enum.all?(trimmed, &Regex.match?(@slug, &1)), do: {:ok, trimmed}, else: :error
  end

  defp slugs(_other), do: :error
end

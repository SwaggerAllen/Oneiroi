defmodule Oneiroi.Seal do
  @moduledoc """
  What a regression trial must leave as it found it (eunomia #12, brain
  #40), read before and compared after: every event on the resident's
  streams, every row of every table, every file in the resident's
  repository and everything the Honcho fake holds for its workspace.

  Rows are compared by content, not counted, because a read that marks
  a row it read (a citation resolved, a vector refreshed, a bookmark
  recalled) changes no count and is still a write. A trial is allowed
  exactly what billing and the run itself record: the ledger's usage
  rows and their `ledger-` events, Commanded's projection marks, and,
  when the trial answered inside a run, the run's own stream, rows and
  job, all named below so that adding to the list is a decision.
  """

  # Test support, its own boundary as `Oneiroi.Fixtures` is, so the core
  # never depends on it.
  use Boundary, top_level?: true, deps: [Oneiroi, Oneiroi.Proteus, Oneiroi.SimaQian]

  import ExUnit.Assertions

  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  # What billing records for every model call, trial or not.
  @billed ~w(nisaba_usage projection_versions)
  # What a run records of itself, on its own stream (eunomia #9).
  @run ~w(eunomia_regression_answer eunomia_regression_run eunomia_regression_test oban_jobs oban_peers)
  @never ~w(schema_migrations)

  @type t :: %{
          events: non_neg_integer(),
          tables: %{String.t() => String.t()},
          files: %{String.t() => binary()},
          honcho: map()
        }

  @doc "Reads everything a trial must not change."
  @spec snapshot(String.t()) :: t()
  def snapshot(resident_id) do
    %{
      events: last_event(),
      tables: tables(),
      files: files(resident_id),
      honcho: Honcho.state(resident_id)
    }
  end

  @doc """
  Asserts nothing changed since `before` but what billing records, and,
  with `run: true`, what the run records of itself. Returns the events
  that were allowed, for the caller to read further.
  """
  @spec assert_unchanged(t(), String.t(), keyword()) :: [EventStore.RecordedEvent.t()]
  def assert_unchanged(before, resident_id, opts \\ []) do
    run? = Keyword.get(opts, :run, false)

    allowed_streams =
      ["ledger-" <> resident_id] ++ if(run?, do: ["regression-" <> resident_id], else: [])

    allowed_tables = @billed ++ @never ++ if(run?, do: @run, else: [])

    events =
      (before.events + 1)
      |> Oneiroi.EventStore.stream_all_forward()
      |> Enum.filter(&String.contains?(&1.stream_uuid, resident_id))

    {allowed, recorded} = Enum.split_with(events, &(&1.stream_uuid in allowed_streams))

    changed =
      for {table, hash} <- tables(),
          table not in allowed_tables,
          Map.get(before.tables, table) != hash,
          do: table

    files = files(resident_id)

    # Every difference at once, so a failure says all a trial wrote.
    differences =
      Enum.reject(
        [
          recorded != [] &&
            "recorded on the resident's streams: " <>
              inspect(Enum.map(recorded, &{&1.stream_uuid, &1.event_type})),
          changed != [] && "rows written: #{inspect(changed)}",
          files != before.files &&
            "the repository's files changed: " <>
              inspect(Map.keys(files) -- Map.keys(before.files)),
          Honcho.state(resident_id) != before.honcho && "Honcho's workspace changed"
        ],
        &(&1 == false)
      )

    assert differences == [], Enum.join(differences, "\n")
    allowed
  end

  defp last_event do
    case Oneiroi.EventStore.read_all_streams_backward(-1, 1) do
      {:ok, [event]} -> event.event_number
      {:ok, []} -> 0
    end
  end

  # Every table's rows as one digest, under the platform scope so the
  # row policies hide nothing; the sandbox holds only this test's rows.
  defp tables do
    Scope.platform(fn ->
      %{rows: names} =
        Repo.query!(
          "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
        )

      Map.new(names, fn [name] ->
        %{rows: [[digest]]} =
          Repo.query!(
            ~s{SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) FROM "#{name}" t}
          )

        {name, digest}
      end)
    end)
  end

  # Every file in the resident's repository, `.git` included, so a
  # commit is a change too.
  defp files(resident_id) do
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident_id)

    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(&{Path.relative_to(&1, dir), :crypto.hash(:sha256, File.read!(&1))})
  end
end

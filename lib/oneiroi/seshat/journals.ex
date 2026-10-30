defmodule Oneiroi.Seshat.Journals do
  @moduledoc """
  The journal (spec §6.5, F29): rows as the queryable spine, the day's
  file as the narrative rendered from them, the plan-versus-actuals
  delta the audits read. The day row is the schedule's (sunna #9): the
  journal asks the schedule to open a day it reaches first, so a day
  written before any check-in is a row too (seshat #21). Every entry
  re-renders `journal/<day>.md` into the repository through the
  library's core write, so the day is a registered, indexed document
  whose citations are edges and which `<slug>:journal/<day>` resolves to.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Journal
  alias Oneiroi.Seshat.JournalCommands, as: Commands
  alias Oneiroi.Seshat.JournalRouter, as: Router
  alias Oneiroi.Seshat.Store
  alias Oneiroi.Sunna

  @headings %{"plan" => "Plan", "note" => "Notes", "todo" => "To do", "wrap" => "Wrap"}

  @doc "Adds an entry to a day (today in the resident's zone when nil); opens the day row if the schedule has not; renders the day's file."
  def add(resident_id, day, kind, text, %Actor{} = actor),
    do: add(resident_id, day, kind, text, nil, actor)

  @doc "Adds an entry with its register (correction, praise, instruction, play or nil; spec §6.13, P8)."
  def add(resident_id, day, kind, text, register, %Actor{} = actor) do
    day = day || today(resident_id)

    with :ok <- open_day(resident_id, day, actor),
         {:ok, [event]} <-
           dispatch(%Commands.AddJournalEntry{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             day: day,
             kind: kind,
             text: text,
             register: register
           }),
         :ok <- render_day(resident_id, day, actor) do
      {:ok, %{day: day, number: event.number, kind: kind}}
    end
  end

  @doc "The entries written since an instant, oldest first."
  def entries_since(resident_id, %DateTime{} = since),
    do: Scope.resident(resident_id, fn -> Store.journal_entries_since(since) end)

  @doc "Marks a todo done; renders the day's file."
  def done(resident_id, day, number, %Actor{} = actor) do
    with {:ok, _} <-
           dispatch(%Commands.MarkTodoDone{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             day: day,
             number: number
           }),
         do: render_day(resident_id, day, actor)
  end

  @doc "A day: its row, its entries in order, and the delta; nil when the schedule never opened it."
  def day(resident_id, day) do
    case Sunna.day(resident_id, day) do
      nil ->
        nil

      row ->
        entries = Scope.resident(resident_id, fn -> Store.journal_entries(day) end)
        %{day: day, opened_at: row.opened_at, entries: entries, delta: delta(entries)}
    end
  end

  @doc "The latest days with their deltas, newest first."
  def days(resident_id, limit) do
    rows = Sunna.days(resident_id, limit)
    keys = Enum.map(rows, & &1.day)
    counts = Scope.resident(resident_id, fn -> Store.journal_counts(keys) end)

    Enum.map(rows, fn row ->
      %{
        day: row.day,
        opened_at: row.opened_at,
        delta: delta_of_counts(Map.get(counts, row.day, %{}))
      }
    end)
  end

  @doc """
  The plan-versus-actuals delta of a day's entries: how many of each
  kind, how many todos are done, and whether the day was planned and
  never wrapped, which is what the audit counts (huginn-muninn #15).
  """
  def delta(entries) do
    counts =
      entries
      |> Enum.group_by(& &1.kind)
      |> Map.new(fn {kind, rows} -> {kind, length(rows)} end)

    done = Enum.count(entries, &(&1.kind == "todo" and not is_nil(&1.done_at)))
    delta_of_counts(Map.put(counts, "done", done))
  end

  defp delta_of_counts(counts) do
    plan = Map.get(counts, "plan", 0)
    wrap = Map.get(counts, "wrap", 0)

    %{
      plan: plan,
      note: Map.get(counts, "note", 0),
      todo: Map.get(counts, "todo", 0),
      done: Map.get(counts, "done", 0),
      wrap: wrap,
      unwrapped: plan > 0 and wrap == 0
    }
  end

  @doc "Days before today, among the last `days` opened, that were planned and never wrapped: the delta the audit reads."
  def unwrapped_days(resident_id, days) do
    today = today(resident_id)

    resident_id
    |> days(days + 1)
    |> Enum.reject(&(&1.day == today))
    |> Enum.take(days)
    |> Enum.filter(& &1.delta.unwrapped)
    |> Enum.map(& &1.day)
  end

  @doc "Today's journal as the section the brain reads; empty when the day has no entry."
  @spec text(String.t()) :: String.t()
  def text(resident_id) do
    day = today(resident_id)

    case Scope.resident(resident_id, fn -> Store.journal_entries(day) end) do
      [] -> ""
      entries -> render(day, entries)
    end
  end

  @doc "The day's narrative, rendered from its rows: a heading per kind in the journal's order, todos with their state."
  @spec render(String.t(), [map()]) :: String.t()
  def render(day, entries) do
    sections =
      Journal.kinds()
      |> Enum.map(fn kind -> {kind, Enum.filter(entries, &(&1.kind == kind))} end)
      |> Enum.reject(fn {_kind, rows} -> rows == [] end)
      |> Enum.map_join("\n\n", fn {kind, rows} ->
        "## " <> @headings[kind] <> "\n\n" <> Enum.map_join(rows, "\n", &line/1)
      end)

    "# " <> day <> "\n\n" <> sections <> "\n"
  end

  defp line(%{kind: "todo"} = e) do
    box = if e.done_at, do: "[x]", else: "[ ]"
    "- #{box} (#{e.number}) #{e.text}"
  end

  defp line(e), do: "- (#{e.number}) #{e.text}"

  # The file follows the rows: written through the library's core write
  # (the journal kind is the platform's, seshat #13), registered and
  # indexed like any document.
  defp render_day(resident_id, day, actor) do
    entries = Scope.resident(resident_id, fn -> Store.journal_entries(day) end)

    case Documents.write(resident_id, "journal/#{day}.md", render(day, entries), actor,
           core: true
         ) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  defp today(resident_id), do: Sunna.today(resident_id).day

  # The schedule's day row, in the schedule's words; a day it rejects is
  # named here in this system's.
  defp open_day(resident_id, day, actor) do
    case Sunna.open_day(resident_id, day, actor) do
      :ok ->
        :ok

      {:error, %{kind: :sunna_day_invalid}} ->
        {:error, Error.new(:seshat_day_invalid, day: inspect(day))}

      other ->
        other
    end
  end

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, :day_invalid} ->
        {:error, Error.new(:seshat_day_invalid, day: inspect(command.day))}

      {:error, :register_invalid} ->
        {:error, Error.new(:seshat_register_invalid, registers: Oneiroi.Register.all())}

      {:error, :kind_invalid} ->
        {:error, Error.new(:seshat_entry_kind_invalid, kinds: Journal.kinds())}

      {:error, :text_invalid} ->
        {:error, Error.new(:seshat_entry_text_invalid)}

      {:error, :no_such_todo} ->
        {:error, Error.new(:seshat_no_such_todo, day: command.day, number: command.number)}

      {:error, other} ->
        {:error, other}
    end
  end
end

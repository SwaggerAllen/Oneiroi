defmodule Oneiroi.Seshat.Journal do
  @moduledoc """
  The journal aggregate on `journal-<resident_id>` (spec §6.5, F29).
  Pure: it counts the entries of each day, so an entry's number is its
  position within the day and a rebuild numbers them the same, and
  holds which todos are done.
  """

  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.JournalCommands, as: Commands

  defstruct [:id, days: %{}]

  @kinds ~w(plan note todo wrap)
  @text_limit 2_000

  @doc "The entry kinds, in the order the day renders them."
  def kinds, do: @kinds

  def execute(%__MODULE__{days: days}, %Commands.AddJournalEntry{} = c) do
    cond do
      not day_ok?(c.day) ->
        {:error, :day_invalid}

      c.kind not in @kinds ->
        {:error, :kind_invalid}

      not text_ok?(c.text) ->
        {:error, :text_invalid}

      not Oneiroi.Register.ok?(c.register) ->
        {:error, :register_invalid}

      true ->
        %{count: count} = Map.get(days, c.day, %{count: 0, todos: %{}})

        %Events.JournalEntryAdded{
          actor: c.actor,
          at: c.at,
          id: c.id,
          day: c.day,
          number: count + 1,
          kind: c.kind,
          text: String.trim(c.text),
          register: c.register
        }
    end
  end

  def execute(%__MODULE__{days: days}, %Commands.MarkTodoDone{} = c) do
    case get_in(days, [c.day, :todos, c.number]) do
      nil ->
        {:error, :no_such_todo}

      true ->
        []

      false ->
        %Events.JournalTodoDone{actor: c.actor, at: c.at, id: c.id, day: c.day, number: c.number}
    end
  end

  def apply(%__MODULE__{} = j, %Events.JournalEntryAdded{} = e) do
    day = Map.get(j.days, e.day, %{count: 0, todos: %{}})
    todos = if e.kind == "todo", do: Map.put(day.todos, e.number, false), else: day.todos
    %{j | id: e.id, days: Map.put(j.days, e.day, %{count: e.number, todos: todos})}
  end

  def apply(%__MODULE__{} = j, %Events.JournalTodoDone{} = e),
    do: %{j | days: put_in(j.days, [e.day, :todos, e.number], true)}

  defp day_ok?(day), do: is_binary(day) and match?({:ok, _}, Date.from_iso8601(day))

  defp text_ok?(text),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= @text_limit
end

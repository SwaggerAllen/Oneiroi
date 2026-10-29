defmodule Oneiroi.HuginnMuninn.Figures do
  @moduledoc """
  Figures (spec §6.13, F57): a number anyone wants to cite lives as a
  figure row, never as a literal in a file. A counter's value is the
  fold of its increments, each with its actor; a countdown's value is
  derived from a date (spec §6.7) on the read that shows it. Both are
  citeable as `<slug>:figure/<key>`, both are tagging targets, and both
  render fresh in the brain's context.

  Counters are the steward's to define and retire; either party
  increments, from a tool or the client, with the actor on the event.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.HuginnMuninn.Commands
  alias Oneiroi.HuginnMuninn.Error
  alias Oneiroi.HuginnMuninn.Router
  alias Oneiroi.HuginnMuninn.Store
  alias Oneiroi.Scope
  alias Oneiroi.Sunna

  @doc "Defines a counter: a key and a label; the steward's."
  def define_counter(resident_id, key, label, %Actor{} = actor) do
    with :ok <- steward_only(actor) do
      command = %Commands.DefineCounter{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        key: key,
        label: label
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "Increments a counter by `by` (negative to correct), with a note; either party's, the actor on the event."
  def increment(resident_id, key, by, note, %Actor{} = actor) do
    command = %Commands.IncrementCounter{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      key: key,
      by: by,
      note: note
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Retires a counter; the steward's."
  def retire_counter(resident_id, key, %Actor{} = actor) do
    with :ok <- steward_only(actor) do
      command = %Commands.RetireCounter{actor: actor, at: Clock.now(), id: resident_id, key: key}
      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc """
  Every figure, fresh: the counters as folded, then the countdowns
  derived from the schedule's dates now, each as `%{key, kind, label,
  value, ...}`; a countdown's key is `date/<number>` and its value is
  days to, negative once past.
  """
  @spec figures(String.t()) :: [map()]
  def figures(resident_id) do
    counters =
      resident_id
      |> Scope.resident(fn -> Store.counters() end)
      |> Enum.map(
        &%{
          key: &1.key,
          kind: "counter",
          label: &1.label,
          value: &1.value,
          increments: &1.increments,
          last_at: &1.last_at,
          last_by: &1.last_by_kind
        }
      )

    countdowns =
      resident_id
      |> Sunna.today()
      |> Map.fetch!(:dates)
      |> Enum.map(
        &%{
          key: "date/#{&1.number}",
          kind: "countdown",
          label: &1.title,
          value: &1.days_to,
          date_kind: &1.kind,
          on: &1.on
        }
      )

    counters ++ countdowns
  end

  @doc "One figure by key, or nil."
  def figure(resident_id, key), do: resident_id |> figures() |> Enum.find(&(&1.key == key))

  @doc "A counter's latest increments with their actors."
  def increments(resident_id, key, limit),
    do: Scope.resident(resident_id, fn -> Store.increments(key, limit) end)

  @doc "The figures section the brain is shown: the counters by value; countdowns are the dates section's (sunna #15)."
  @spec text(String.t()) :: String.t()
  def text(resident_id) do
    case resident_id |> figures() |> Enum.filter(&(&1.kind == "counter")) do
      [] ->
        ""

      counters ->
        lines = Enum.map(counters, &"- #{&1.label}: #{&1.value} (figure/#{&1.key})")

        Enum.join(
          ["# Figures\n\nCounted from their increments, never written down." | lines],
          "\n"
        )
    end
  end

  defp steward_only(%Actor{kind: :steward}), do: :ok
  defp steward_only(%Actor{}), do: {:error, Error.new(:huginn_muninn_not_the_steward)}

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, :key_invalid} ->
        {:error, Error.new(:huginn_muninn_key_invalid)}

      {:error, :label_invalid} ->
        {:error, Error.new(:huginn_muninn_label_invalid)}

      {:error, :no_such_counter} ->
        {:error, Error.new(:huginn_muninn_no_such_figure, key: command.key)}

      {:error, :increment_invalid} ->
        {:error, Error.new(:huginn_muninn_increment_invalid)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

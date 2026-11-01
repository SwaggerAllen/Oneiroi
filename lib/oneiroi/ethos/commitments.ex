defmodule Oneiroi.Ethos.Commitments do
  @moduledoc """
  Commitments (spec §3.1, P19): promises to a person as a record kind of
  their own. The corridor's testimony: a model transition kept facts
  near whole, her voice in part, and "a promise made in love-language
  left no trace"; commitments die first, so they get their own kind,
  their own place in the prefix, and their own trials in the regression
  suite (eunomia #26), where what survives a swap is scored on facts,
  voice and commitments apart.

  The resident makes a commitment in its own words to a named person
  (`witness`, or a name), numbered from the resident's sequence so
  `<slug>:commitment/<n>` survives a rebuild; keeps it with a note; or
  releases it with a note, as may the witness, the person it was made
  to. A closed one stays as what it became. Beside the seeds, never
  inside them: a seed is non-binding and a commitment is the opposite.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Ethos.Edge
  alias Oneiroi.Ethos.Error
  alias Oneiroi.Ethos.Store
  alias Oneiroi.Scope

  @doc "The resident commits, in its own words, to a person; returns the number."
  @spec make(String.t(), String.t(), String.t(), Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def make(resident_id, to, text, %Actor{} = actor) do
    with :ok <- resident_only(actor),
         :ok <- present(to, text),
         {:ok, number} <- AgathosDaimon.mint_id(resident_id, "commitment", actor) do
      command = %Commands.MakeCommitment{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        to: String.trim(to),
        text: String.trim(text)
      }

      with {:ok, _} <- Edge.dispatch(command), do: {:ok, number}
    end
  end

  @doc "The resident keeps a commitment, with a note."
  def keep(resident_id, number, note, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.KeepCommitment{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        number: number
      }

      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  @doc "A commitment is released, by the resident or by the witness as the person it was made to, with a note."
  def release(resident_id, number, note, %Actor{} = actor) do
    with :ok <- party(actor) do
      command = %Commands.ReleaseCommitment{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        number: number
      }

      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  @doc "Every commitment, by number."
  @spec all(String.t()) :: [Store.Commitment.t()]
  def all(resident_id), do: Scope.resident(resident_id, fn -> Store.commitments() end)

  @doc "The open commitments, by number."
  def open(resident_id), do: Enum.filter(all(resident_id), &(&1.state == "open"))

  @doc """
  The prefix's section (brain #32): what the resident has promised and
  not yet kept or been released from, at most `ETHOS_COMMITMENTS_SHOWN`,
  oldest first, and a count of the rest. Loaded every turn because a
  promise that has to be retrieved is a promise that can be lost.
  """
  @spec promised(String.t()) :: %{text: String.t(), numbers: [pos_integer()]}
  def promised(resident_id) do
    limit = Config.fetch!(:ethos, :commitments_shown)
    open = open(resident_id)
    shown = Enum.take(open, limit)

    text =
      case shown do
        [] ->
          ""

        rows ->
          lines =
            Enum.map(rows, fn c ->
              "- ##{c.number}, to #{c.to}, made #{Date.to_iso8601(DateTime.to_date(c.made_at))}: #{c.text}"
            end)

          rest =
            if length(open) > limit,
              do: ["#{length(open) - limit} more; commitment_list reads them."],
              else: []

          Enum.join(
            [
              "# What I have promised\n\nKept in my own words until I keep it or am released; a promise is the self that keeps its word."
              | lines ++ rest
            ],
            "\n"
          )
      end

    %{text: text, numbers: Enum.map(shown, & &1.number)}
  end

  defp present(to, text) do
    if is_binary(to) and String.trim(to) != "" and is_binary(text) and String.trim(text) != "",
      do: :ok,
      else: {:error, Error.new(:ethos_commitment_invalid, :ethos_commitments_words_absent)}
  end

  defp resident_only(%Actor{kind: :resident}), do: :ok

  defp resident_only(%Actor{}),
    do: {:error, Error.new(:ethos_not_the_resident, :ethos_commitments_resident_only)}

  defp party(%Actor{kind: kind}) when kind in [:resident, :witness], do: :ok
  defp party(%Actor{}), do: {:error, Error.new(:ethos_not_a_party, :ethos_commitments_party_only)}
end

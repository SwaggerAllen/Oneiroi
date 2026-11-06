defmodule Oneiroi.AgathosDaimon.Asks do
  @moduledoc """
  The asks aggregate (agathos-daimon#35), on `asks-<resident_id>`: what
  the resident asks of her witness, numbered from 1. Two kinds:

  - `tool`: a tool she lacked. Recorded, read by the witness, and noted;
    it grants nothing, and the shape of what is asked is kept for the
    graded-permissions design to read.
  - `act`: leave for an act she names (publishing, spending, writing to
    someone). The witness approves or declines it, with a note; the
    answer is the act's, not a message's.

  Only the resident asks and only the witness answers, each once.
  """

  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.Events

  defstruct next: 1, asks: %{}

  @kinds ~w(tool act)
  @limit 2_000

  def execute(%__MODULE__{next: n}, %Commands.MakeAsk{} = c) do
    cond do
      c.actor.kind != :resident ->
        {:error, Error.new(:agathos_daimon_not_a_party, :agathos_daimon_ask_not_resident)}

      c.kind not in @kinds or not words?(c.subject) or not words?(c.why) ->
        {:error, Error.new(:agathos_daimon_ask_invalid, :agathos_daimon_ask_make_invalid)}

      true ->
        %Events.AskMade{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: n,
          kind: c.kind,
          subject: String.trim(c.subject),
          why: String.trim(c.why)
        }
    end
  end

  def execute(%__MODULE__{asks: asks}, %Commands.AnswerAsk{} = c) do
    case Map.get(asks, c.number) do
      nil ->
        {:error, Error.new(:agathos_daimon_no_such_ask, :agathos_daimon_ask_answer_unknown)}

      %{answered: true} ->
        []

      %{kind: kind} ->
        cond do
          c.actor.kind != :witness ->
            {:error, Error.new(:agathos_daimon_not_a_party, :agathos_daimon_ask_not_witness)}

          c.decision not in decisions(kind) or not words?(c.note) ->
            {:error, Error.new(:agathos_daimon_ask_invalid, :agathos_daimon_ask_answer_invalid)}

          true ->
            %Events.AskAnswered{
              actor: c.actor,
              at: c.at,
              id: c.id,
              number: c.number,
              decision: c.decision,
              note: c.note
            }
        end
    end
  end

  def apply(%__MODULE__{} = s, %Events.AskMade{} = e),
    do: %{
      s
      | next: e.number + 1,
        asks: Map.put(s.asks, e.number, %{kind: e.kind, answered: false})
    }

  def apply(%__MODULE__{} = s, %Events.AskAnswered{} = e),
    do: %{s | asks: Map.update!(s.asks, e.number, &%{&1 | answered: true})}

  defp decisions("act"), do: ~w(approve decline)
  defp decisions("tool"), do: ~w(noted)

  defp words?(text),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= @limit
end

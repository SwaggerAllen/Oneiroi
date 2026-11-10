defmodule Oneiroi.Seshat.ThemeLedger do
  @moduledoc """
  Her theme proposals (seshat#56), on `theme-<resident_id>`. The three
  seeds are the witness's (the witness, 2026-11-10: "because they're the
  ones looking at the screen"), so he sets them directly, through the
  file, and nothing of that comes here. She changes them by proposal
  only: one open at a time, answered by him alone, accepted or declined
  with a note. The seeds were checked for readability before the command
  was built; this keeps only who may do what, and when.
  """

  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Events

  defstruct proposals: %{}, next: 1

  def execute(%__MODULE__{}, %Commands.ProposeTheme{actor: %{kind: kind}}) when kind != :resident,
    do: {:error, Error.new(:seshat_theme_not_hers, :seshat_theme_ledger_propose_not_hers)}

  def execute(%__MODULE__{} = s, %Commands.ProposeTheme{} = c) do
    if Enum.any?(s.proposals, fn {_n, open} -> open end),
      do: {:error, Error.new(:seshat_theme_proposal_open, :seshat_theme_ledger_open)},
      else: %Events.ThemeProposed{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: s.next,
        ground: c.ground,
        resident: c.resident,
        witness: c.witness,
        note: c.note
      }
  end

  def execute(%__MODULE__{}, %Commands.AnswerTheme{actor: %{kind: kind}}) when kind != :witness,
    do: {:error, Error.new(:seshat_theme_answer_invalid, :seshat_theme_ledger_answer_not_his)}

  def execute(%__MODULE__{proposals: proposals}, %Commands.AnswerTheme{} = c) do
    case Map.get(proposals, c.number) do
      true ->
        %Events.ThemeAnswered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          agree: c.agree == true,
          note: c.note
        }

      _closed_or_none ->
        {:error, Error.new(:seshat_theme_answer_invalid, :seshat_theme_ledger_no_proposal)}
    end
  end

  def apply(%__MODULE__{} = s, %Events.ThemeProposed{number: n}),
    do: %{s | next: n + 1, proposals: Map.put(s.proposals, n, true)}

  def apply(%__MODULE__{} = s, %Events.ThemeAnswered{number: n}),
    do: %{s | proposals: Map.put(s.proposals, n, false)}
end

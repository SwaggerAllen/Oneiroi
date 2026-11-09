defmodule Oneiroi.Kumbukumbu.ReactsLedger do
  @moduledoc """
  Reacts on each other's messages and on letters (kumbukumbu#56), on
  `reacts-<resident_id>`: either party's, numbered, never waking. The
  witness's are told once on her next turn, the telling the platform's,
  recorded with the turn that told them; hers he sees in the chat.
  """

  alias Oneiroi.Kumbukumbu.Commands
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Events

  defstruct next: 1, told: 0

  def execute(%__MODULE__{}, %Commands.React{actor: %{kind: k}})
      when k not in [:witness, :resident],
      do: {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_ledger_party)}

  def execute(%__MODULE__{next: n}, %Commands.React{} = c),
    do: %Events.Reacted{
      actor: c.actor,
      at: c.at,
      id: c.id,
      number: n,
      target: c.target,
      emoji: c.emoji
    }

  def execute(%__MODULE__{told: told}, %Commands.TellReacts{through: through})
      when through <= told,
      do: []

  def execute(%__MODULE__{}, %Commands.TellReacts{} = c),
    do: %Events.ReactsTold{
      actor: c.actor,
      at: c.at,
      id: c.id,
      through: c.through,
      session_key: c.session_key
    }

  def apply(%__MODULE__{} = s, %Events.Reacted{number: n}), do: %{s | next: n + 1}
  def apply(%__MODULE__{} = s, %Events.ReactsTold{through: t}), do: %{s | told: max(s.told, t)}
end

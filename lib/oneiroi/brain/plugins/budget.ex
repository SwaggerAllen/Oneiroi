defmodule Oneiroi.Brain.Plugins.Budget do
  @moduledoc """
  Her money, every turn (brain#64). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  alias Oneiroi.Nisaba

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "budget",
      name: "Your budget",
      about: "what each budget line has left this period",
      place: :turn,
      reads: ~w(ledger)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx), do: budget_section(turn)

  # Her money, every turn (brain#64; her word: "I see the money every
  # turn rather than remembering to ask"): each line with a cap, what is
  # left of it this period; the lines with none, named once. The same
  # numbers the free-time note reads; budget_read gives the precise read.
  defp budget_section(%{trial?: true}), do: []

  defp budget_section(turn) do
    lines = Nisaba.budgets(turn.resident_id, :resident)
    {capped, open} = Enum.split_with(lines, &is_integer(&1.cap_nanos))

    capped_text =
      Enum.map_join(capped, "\n", fn l ->
        left = max(l.cap_nanos - l.spent_nanos, 0)
        spent = if l.exceeded, do: " (spent)", else: ""
        "- #{l.purpose}: #{dollars(left)} left of #{dollars(l.cap_nanos)} a #{l.period}#{spent}"
      end)

    open_text =
      if open == [],
        do: "",
        else: "\nNo cap on: #{Enum.map_join(open, ", ", &Atom.to_string(&1.purpose))}."

    section(
      "budget",
      "# Your budget\n\nWhat each line has left this period, as this turn opens:\n" <>
        if(capped == [], do: "- no line has a cap", else: capped_text) <> open_text,
      "the resident's budget lines and what each has left this period (brain#64), read at the turn"
    )
  end

  defp dollars(nanos), do: "$" <> :erlang.float_to_binary(nanos / 1_000_000_000, decimals: 2)
end

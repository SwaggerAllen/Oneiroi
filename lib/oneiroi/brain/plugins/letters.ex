defmodule Oneiroi.Brain.Plugins.Letters do
  @moduledoc """
  House letters waiting here (kumbukumbu#44). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4]

  alias Oneiroi.Kumbukumbu

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "letters",
      name: "House letters",
      about: "how many house letters wait for this conversation, and from whom",
      place: :turn,
      reads: ~w(letters)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx), do: letters_section(turn)

  # Where this conversation is and which others are open now (brain#44,
  # kumbukumbu#42): an adapter's turn is told its runtime, the folder by
  # its base name, that the Oneiroi chat is a separate conversation that
  # may be going on at once, that memory is one across them, the other
  # conversations open now and this turn's ref for the memory tools; the
  # Oneiroi chat is told, when any is open, which adapters' conversations
  # are, by name and folder alone. No other conversation's words ride
  # either: each session's history is its own (`Kumbukumbu.recent/3`
  # reads one key). A trial is a session nobody opened, told nothing.
  # House letters waiting for this conversation (kumbukumbu#44): how
  # many and from whom, never their words, which `letter_inbox` reads
  # and marks. Nothing when none wait; a trial is told nothing.
  defp letters_section(%{trial?: true}), do: []

  defp letters_section(%{oracle?: true}), do: []

  defp letters_section(turn) do
    case Kumbukumbu.inbox(turn.resident_id, turn.session_key) do
      [] ->
        []

      waiting ->
        from = waiting |> Enum.map(& &1.from_name) |> Enum.uniq() |> Enum.join(", ")

        text =
          "#{length(waiting)} house #{if length(waiting) == 1, do: "letter waits", else: "letters wait"} for this conversation, from #{from}. letter_inbox reads them whole; letter_send with in_reply_to answers each in its thread."

        # The text rides the row, as the index's does: it is a count and
        # names, nothing of the letters, and the inspector shows it.
        section(
          "letters",
          text,
          "house letters waiting here (kumbukumbu#44): #{length(waiting)}, by sender alone, none of their words",
          %{text: text}
        )
    end
  end
end

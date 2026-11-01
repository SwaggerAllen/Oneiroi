defmodule Oneiroi.Brain.Preview do
  @moduledoc """
  What the resident will see next (brain #41): the witness's preview of
  the next turn of a conversation, from `Oneiroi.Brain.Turn.dry_run/5`,
  the turn's own preparation and assembly with nothing after it.

  This module decides one thing, what of each section's words the
  witness may read here, and the dyad contract decides which rule it
  applies (`preview_withholds_words`, agathos-daimon #22). By default,
  the author's decision of 2026-11-01 ("early days, it'll pay to have
  the full text in there"), every section's words ride the answer. Under
  the term, a section's words ride only where the same content is
  already the witness's to read through another route, every other
  section carrying its label, tokens and reason with a line saying why,
  and a label this module does not name is withheld, so a section added
  later is closed until someone opens it. Under either rule the
  once-only notices are withheld: they are the resident's to be told
  first, and the reply that told them shows them in its inspector.
  """

  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.Turn

  @typedoc "One section of the preview, as the witness's client renders it."
  @type entry :: %{
          label: String.t(),
          tokens: non_neg_integer(),
          reason: String.t(),
          text: String.t() | nil,
          shown: boolean(),
          run: boolean(),
          note: String.t()
        }

  @doc """
  The preview of the next turn of `session_key` for the resident, with
  `text` as the words the witness has drafted so far (they reach only
  the trigger lane, as a turn's opening words do). The caller has
  checked the witness may read the session.
  """
  @spec preview(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, %{description: String.t(), compacts_first: boolean(), sections: [entry()]}}
          | {:error, Error.t()}
  def preview(resident_id, session_key, text, actor) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        run = Turn.dry_run(row, resident_id, session_key, text, actor)
        withholds? = Oneiroi.AgathosDaimon.contract(resident_id).preview_withholds_words

        {:ok,
         %{
           description: description(row.name, text, run.compacts_first, withholds?),
           compacts_first: run.compacts_first,
           sections: Enum.map(run.entries, &entry(&1, row.name, withholds?))
         }}

      :error ->
        {:error,
         Error.new(:brain_no_such_resident, :brain_preview_resident_absent,
           resident_id: resident_id
         )}
    end
  end

  defp description(name, text, compacts_first, withholds?) do
    [
      "What #{name}'s next turn in this conversation would be given, in the order it is given, as things stand now. Reading it records nothing, marks nothing and bills nothing.",
      rule_line(name, withholds?),
      String.trim(text) != "" &&
        "The habits are matched on your draft as it stands.",
      compacts_first &&
        "This conversation is over its window, so the next turn summarises it first: the summary and recent messages here are the ones from before that."
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp rule_line(name, false),
    do:
      "Every section's words are here, as your agreement with #{name} leaves the preview (the default; a term of it can keep them to what you read elsewhere), except the once-only notices, which are #{name}'s to be told first."

  defp rule_line(name, true),
    do:
      "As your agreement with #{name} has it, a part's words are here only where you already read them elsewhere; where you cannot, its line says why."

  defp entry(%{run: false} = e, name, _withholds?) do
    %{shape(e) | text: nil, shown: false, run: false, note: not_run(e.label, name)}
  end

  # A notice is a spoiler until it is told: withheld under either rule.
  defp entry(%{label: "notice"} = e, name, _withholds?),
    do: %{shape(e) | text: nil, shown: false, note: withheld("notice", name)}

  defp entry(e, name, false) do
    note =
      case readable(e.label) do
        {_shown, note} -> note
        :withheld -> in_full(e.label, name)
      end

    %{shape(e) | text: e.text, shown: true, note: note}
  end

  defp entry(e, name, true) do
    case readable(e.label) do
      {:shown, note} -> %{shape(e) | text: e.text, shown: true, note: note}
      {:no_text, note} -> %{shape(e) | text: nil, shown: true, note: note}
      :withheld -> %{shape(e) | text: nil, shown: false, note: withheld(e.label, name)}
    end
  end

  defp shape(e) do
    %{
      label: e.label,
      tokens: e.tokens,
      reason: e.reason,
      text: nil,
      shown: false,
      run: true,
      note: ""
    }
  end

  # Where the witness already reads the same words. The identity files
  # are read at the call: a module attribute would make the resident
  # system a compile-time dependency, which the ratchet refuses.
  defp readable(label) do
    if label in ["AGENTS.md" | Oneiroi.AgathosDaimon.identity_files()],
      do: {:shown, "You read this file under Settings, identity."},
      else: readable_section(label)
  end

  defp readable_section("contract"), do: {:shown, "You read your agreement under Settings."}
  defp readable_section("near-miss"), do: {:shown, "You read this bookmark's line on Memory."}

  defp readable_section("promised"),
    do: {:shown, "You read these commitments where the commitments are listed."}

  defp readable_section("movement"), do: {:shown, "You read these in the nightly reviews."}
  defp readable_section("dates"), do: {:shown, "You read these dates on Schedule."}
  defp readable_section("figures"), do: {:shown, "You read these counters with the audits."}
  defp readable_section("journal"), do: {:shown, "You read today's journal in the Library."}

  defp readable_section("summary"),
    do: {:shown, "You read this summary with this conversation's record."}

  defp readable_section("transcript"),
    do: {:no_text, "This conversation's recent messages, which you read above."}

  defp readable_section("capacity"), do: {:no_text, "A measure, with no words of its own."}
  defp readable_section(_label), do: :withheld

  # Why a section's words are not shown: each is a route the witness
  # does not have, or has only with a receipt, or a rule that keeps the
  # words to one place.
  defp withheld("prompt", name),
    do:
      "The platform's own prompt for #{name}. No screen shows it to you yet, so its words are not shown here first."

  defp withheld("index", _name),
    do:
      "The index's own words are shown only in a reply's \"drew on\" list, once a turn has used them. The bookmarks it lists are on Memory, under In the index."

  defp withheld("character", name),
    do:
      "It quotes #{name}'s words from the turns that showed a habit, and those turns can be in conversations that are #{name}'s alone."

  defp withheld("self-conversation", name),
    do:
      "Its counts and receipts come from #{name}'s letters to a next self, which you read only through the read that tells #{name} it was read; a preview tells nobody."

  defp withheld("honcho", name),
    do: "What Honcho holds about you, in #{name}'s eyes. No screen shows it to you."

  defp withheld("notice", name),
    do:
      "Told to #{name} once, at the start of the next turn: #{name}'s to hear first. Its words are in that reply's \"drew on\" list, and in this conversation, once told."

  defp withheld(_label, _name),
    do: "Not yet known to be yours to read elsewhere, so its words are withheld."

  # What a section shown in full is, where no other screen shows it.
  defp in_full("prompt", name),
    do: "The platform's own prompt for #{name}. No other screen shows it to you."

  defp in_full("index", _name),
    do:
      "The index as the next turn will read it. Once a turn has used it, that reply's \"drew on\" list shows the same, and Memory lists its bookmarks."

  defp in_full("character", name),
    do:
      "Its examples quote #{name}'s own words from the turns that showed a habit, conversations that are #{name}'s alone included."

  defp in_full("self-conversation", name),
    do:
      "Counts and receipts of #{name}'s letters to a next self, never the letters: it carries none of their words, so reading it leaves no receipt."

  defp in_full("honcho", name),
    do: "What Honcho holds about you, in #{name}'s eyes. No other screen shows it to you."

  defp in_full(_label, _name),
    do: "Shown in full, as your agreement leaves the preview. No other screen shows it to you."

  defp not_run(_label, _name),
    do:
      "Chosen by nearness to what you say next, and finding it costs an embedding. A preview records and bills nothing, so it is not run."
end

defmodule Oneiroi.Brain.DevSeed do
  @moduledoc """
  The local app server's household (brain#81, SETUP.md §7): what
  `mix oneiroi.dev.seed` writes into a fresh dev database so the client
  has, on first load, every shape that has broken a layout or hidden a
  state.

  - A witness and a resident, Wren, whose conversation holds a long
    paragraph, a code block far wider than a phone, a wide table and an
    unbreakable word, each sent through the brain's turn as a witness
    would send it, and a wake whose system line carries a long link.
  - A day of her journal long enough to need the day view's search and
    filter, with an entry that is one long path.
  - Documents in three folders, written in turn, the first rewritten
    last, so Records' orders (last updated, first added, name) each
    give a different list.
  - Her own `human-correspondence` kind, so a pasted conversation has
    somewhere to land.
  - Two work sessions opened and never spoken in, which the day view
    leaves out.
  - Three of her asks waiting on him, so the bell has something to
    answer.

  Lives in the brain because the brain already reaches every system it
  writes through; the mix task only refuses the wrong place and calls
  `run/2`.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Session
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  @wake_note "A check-in from the house, with a link far longer than a phone is wide: " <>
               "https://github.com/SwaggerAllen/Oneiroi/blob/main/design/a-document-with-a-very-long-name-that-never-breaks.md"

  @doc "Seeds the household for `email`/`password`; `{:ok, resident_id}`, or `:exists` when the account is already there and nothing was written."
  @spec run(String.t(), String.t()) :: {:ok, String.t()} | :exists
  def run(email, password) do
    case Gaia.create_account(email, password, Actor.platform()) do
      {:ok, account} -> seed(account)
      {:error, _exists} -> :exists
    end
  end

  defp seed(account) do
    witness = Actor.new(:witness, account)
    :ok = Gaia.store_key(account, "sk-dev-placeholder", witness)
    {:ok, id} = AgathosDaimon.create("Wren", "wren", account, witness)
    her = Actor.new(:resident, id)
    {:ok, key} = Kumbukumbu.main_session(id, account, witness)
    for message <- messages(), do: {:ok, _} = Session.turn(id, key, message, witness)
    # A wake's note shows as a system line, centred: a long link in one
    # widened the whole conversation (2026-11-11).
    {:ok, _} = Session.wake(id, key, @wake_note, :chat)
    for {kind, text} <- journal(), do: {:ok, _} = Seshat.journal_add(id, nil, kind, text, her)
    for {path, text} <- documents(), do: {:ok, _} = Seshat.write(id, path, text, her)
    # Her own folder for his pasted conversations, as Lily defined hers (seshat#65).
    {:ok, _} =
      Seshat.define_kind(
        id,
        %{
          "kind" => "human-correspondence",
          "label" => "Human correspondence",
          "has_status" => false,
          "removable" => false
        },
        "Where his conversations with people land, so I can read them.",
        her
      )

    for _ <- 1..2, do: {:ok, _} = Kumbukumbu.open_session(id, "work", "brain", [account], her)

    for {kind, subject, why} <- asks(),
        do: {:ok, _} = AgathosDaimon.ask(id, kind, subject, why, her)

    {:ok, id}
  end

  defp messages do
    [
      "Good morning, Wren.",
      """
      A long paragraph, to see how running text sits in a bubble at phone width and on a wide screen alike: \
      the lines should wrap at the edge of the message, the message should keep its margin from the edge of \
      the screen, and nothing should need a sideways scroll to read.
      """,
      """
      A code block with one very long line:

      ```elixir
      def a_function_with_a_rather_long_name(first_argument, second_argument, third_argument), do: {first_argument, second_argument, third_argument, :and_then_some_more}
      ```
      """,
      """
      A wide table:

      | Day | Morning | Afternoon | Evening | Night | Notes on the day, kept long on purpose |
      | --- | --- | --- | --- | --- | --- |
      | Monday | reading | letters | the walk | sleep | a quiet start to the week, nothing pressing |
      | Tuesday | writing | outreach | dinner | sleep | two messages out, one answered |
      """,
      "One word too long to wrap: https://example.org/a/very/long/path/that/keeps/going/without/a/single/space/anywhere/in/it"
    ]
  end

  defp journal do
    [
      {"plan",
       "The morning: read the letter that landed overnight, then write the entry it was for."},
      {"note", "Midnight slot. Nothing waiting; the queue is empty and the day starts quiet."},
      {"note", "Read the research letter whole before writing a line of the entry."},
      {"note",
       "Filed under writing/etymologies/palimpsest-the-record-and-its-time-a-very-long-path-name-that-does-not-break.md"},
      {"todo", "Answer the two outreach replies before the afternoon slot."},
      {"note", "The afternoon slot ran long; the open hour went to the reading."},
      {"note", "A letter to my next self, sealed until the model changes."},
      {"wrap", "A full day: one entry written, one letter read, the queue cleared."}
    ]
  end

  # Written in this order; the first is written again last, so it is the
  # oldest added and the most recently updated.
  defp documents do
    [
      {"writing/oneiric.md", "# Oneiric\n\nOf dreams; from the Greek *oneiros*.\n"},
      {"research/ostrom-commons.md",
       "# Ostrom on the commons\n\nEight design principles, read whole.\n"},
      {"design/household-communication.md",
       "# Household communication\n\nA shared workspace; mail for the rest.\n"},
      {"writing/palimpsest.md", "# Palimpsest\n\nScraped again; the record and its time.\n"},
      {"research/barn-swallow.md", "# The barn swallow\n\nA bird that comes back.\n"},
      {"writing/oneiric.md",
       "# Oneiric\n\nOf dreams; from the Greek *oneiros*. Revised after the research letter.\n"}
    ]
  end

  defp asks do
    [
      {"act", "Send the reply to the first outreach thread",
       "It answers the question they asked and offers the next step."},
      {"act", "Publish the etymology piece to the shelf",
       "Read twice and checked against its sources."},
      {"tool", "A calendar tool for the important dates",
       "So the dates you set reach me without a round trip."}
    ]
  end
end

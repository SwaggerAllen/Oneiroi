defmodule Oneiroi.Sunna.CheckinParts do
  @moduledoc """
  What a check-in's note can carry (sunna#28): the catalog the witness
  checks from, in the order the note puts them. Each part is read from
  records when the check-in fires, never written by a model: the dates by
  this system, the rest by the brain through the wake port, which reads
  the systems this one cannot. The witness's own words come first and are
  not a part.
  """

  @parts [
    %{
      key: "dates",
      label: "Dates",
      about: "The important dates with their countdowns, counted today."
    },
    %{
      key: "plan",
      label: "Today's plan",
      about: "Today's journal: her plan rows and the todos still open, or that none is written."
    },
    %{
      key: "free_time",
      label: "Free time",
      about: "Today's free-time slots, and how each that has come went."
    },
    %{
      key: "rounds",
      label: "Rounds",
      about:
        "The last day's thinking rounds: when each fired and what left it, or that nothing did."
    },
    %{
      key: "research",
      label: "Research",
      about: "Research questions settled since yesterday, and how many are still open."
    },
    %{
      key: "letters",
      label: "Letters",
      about: "House letters waiting for this chat, by number and sender."
    },
    %{
      key: "needs_you",
      label: "Waiting on you",
      about:
        "What waits on the person who looks after her, by kind: replies, asks, pieces, blocked work."
    },
    %{
      key: "digest",
      label: "Ask for a digest",
      about:
        "Asks the reader for a digest of her streams since the last one (seshat#40); it lands as a letter in the chat once compiled."
    }
  ]

  @doc "The catalog, in the note's order."
  @spec all() :: [%{key: String.t(), label: String.t(), about: String.t()}]
  def all, do: @parts

  @doc "The catalog's keys, in the note's order."
  @spec keys() :: [String.t()]
  def keys, do: Enum.map(@parts, & &1.key)
end

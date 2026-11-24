defmodule Oneiroi.Brain.QueueDocs do
  @moduledoc """
  A document named to the house queue is one that exists (sunna#95; the
  witness, 2026-11-23: a task held `lily:design/db-access-consent.md`,
  a file not in her records, while the document was the house's at
  `house/strut:doc/design/db-access-consent.md`). A citation the platform
  can read (a house document, or a member resident's file) is checked
  where it goes in: opening a task, filling a slot, attaching a document.
  One that names nothing is refused, and when the house holds a file at
  that path, or her shared copy, the refusal names it. Anything the
  platform cannot read (a PR, a page) passes as it is.
  """

  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.QueueHeads
  alias Oneiroi.Gaia

  @doc "`:ok`, or the refusal naming what was meant when it can tell."
  @spec check(String.t(), String.t() | nil) :: :ok | {:error, Oneiroi.Error.t()}
  def check(_household_id, nil), do: :ok

  def check(household_id, citation) when is_binary(citation) do
    cite = citation |> String.split("@", parts: 2) |> hd() |> String.trim()

    case QueueHeads.place(household_id, cite) do
      :other ->
        :ok

      _readable ->
        if QueueHeads.head(household_id, cite), do: :ok, else: absent(household_id, cite)
    end
  end

  @doc "The citations a task opening names: its slots', its links' and, given whole, its layers' artifacts."
  def of_opening(attrs) do
    slots = Map.values(attrs[:slots] || %{})

    layers =
      for layer <- List.wrap(attrs[:layers]),
          spec <- List.wrap(layer),
          is_map(spec),
          do: spec["artifact"] || spec[:artifact]

    Enum.filter(slots ++ List.wrap(attrs[:links]) ++ layers, &is_binary/1)
  end

  @doc "The refusal in words for her tools: what is wrong, and what was meant when known."
  def said(%{kind: :brain_queue_document_absent, details: d}) do
    case Keyword.get(d, :meant) do
      nil ->
        "Not done: #{d[:citation]} names no file. Name a file that exists, by the citation its reader gives it."

      meant ->
        "Not done: #{d[:citation]} names no file; the house holds it as #{meant}. Name that."
    end
  end

  @doc "Every citation in a list checked; the first refusal, or `:ok`."
  def check_all(household_id, citations) do
    Enum.reduce_while(List.wrap(citations), :ok, fn c, :ok ->
      case check(household_id, c) do
        :ok -> {:cont, :ok}
        refused -> {:halt, refused}
      end
    end)
  end

  defp absent(household_id, cite) do
    meant = in_the_house(household_id, cite)

    {:error,
     Error.new(:brain_queue_document_absent, :brain_queue_document_absent,
       citation: cite,
       meant: meant
     )}
  end

  # Her file named where the house holds the document: the house's own
  # file at that path, or her shared copy of it.
  defp in_the_house(household_id, cite) do
    with [slug, rest] <- String.split(cite, ":", parts: 2),
         false <- String.starts_with?(slug, "house/"),
         house when is_binary(house) <- Gaia.household_slug(household_id) do
      path = if Path.extname(rest) == "", do: rest <> ".md", else: rest

      Enum.find(
        ["house/#{house}:doc/#{path}", "house/#{house}:doc/shared/#{slug}/#{path}"],
        &QueueHeads.head(household_id, &1)
      )
    else
      _none -> nil
    end
  end
end

defmodule Oneiroi.Seshat.Household.Search do
  @moduledoc """
  The house searched (seshat#80): threads, documents and the charter,
  each hit with the words around its first match.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Reading

  @contract "CONTRACT.md"
  @beats "BEATS.md"

  @doc false
  def search(%Actor{} = actor, q, scope \\ "everything") do
    terms = q |> to_string() |> String.downcase() |> String.split(~r/\s+/, trim: true)

    with {:ok, household_id} <- Core.household(actor),
         {:ok, view} <- Core.provision(household_id) do
      hits =
        actor
        |> searchable(household_id, view, scope)
        |> Enum.map(&hit(&1, terms))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(&{&1.score, &1.at || ""}, :desc)
        |> Enum.take(50)
        |> Enum.map(&Map.delete(&1, :score))

      {:ok, %{q: q, scope: scope, results: hits}}
    end
  end

  defp searchable(actor, household_id, view, scope) do
    threads =
      if scope in ["everything", "threads"] do
        for id <- Files.thread_ids(view),
            {:ok, t} = Files.load_thread(view, "threads/" <> id),
            Reading.visible?(actor, household_id, Files.ids(t)) do
          %{
            type: "thread",
            path: "threads/" <> id,
            title: t.trunk.meta["title"],
            at: (List.last(t.replies) || t.trunk).meta["at"] || t.trunk.meta["posted_at"],
            text: Enum.map_join([t.trunk | t.replies], "\n\n", & &1.body)
          }
        end
      else
        []
      end

    documents =
      if scope in ["everything", "records"] do
        for d <- Files.documents(view), Reading.visible?(actor, household_id, [d.by_id]) do
          {_meta, body} = view |> Files.file(d.path) |> to_string() |> Files.frontmatter()
          %{type: "document", path: d.path, title: d.title, at: d.posted_at, text: body}
        end
      else
        []
      end

    charter =
      if scope in ["everything", "charter"] do
        for {path, title} <- [
              {@contract, "The household contract"},
              {@beats, "The household's beats"}
            ],
            text = Files.file(view, path),
            is_binary(text),
            do: %{type: "charter", path: path, title: title, at: nil, text: text}
      else
        []
      end

    threads ++ documents ++ charter
  end

  # Every term somewhere in its title or words; the score counts them.
  defp hit(_item, []), do: nil

  defp hit(item, terms) do
    haystack = String.downcase("#{item.title}\n#{item.text}")

    if Enum.all?(terms, &String.contains?(haystack, &1)) do
      score = Enum.sum(Enum.map(terms, &(length(String.split(haystack, &1)) - 1)))

      item
      |> Map.take([:type, :path, :title, :at])
      |> Map.put(:snippet, snippet(item.text, hd(terms)))
      |> Map.put(:score, score)
    end
  end

  # About 160 characters around the first match, on one line.
  defp snippet(text, term) do
    flat = String.replace(text, ~r/\s+/, " ")

    case :binary.match(String.downcase(flat), term) do
      {at, _} ->
        from = max(at - 60, 0)
        piece = flat |> binary_slice(from, 160) |> String.trim()
        if from > 0, do: "…" <> piece <> "…", else: piece <> "…"

      :nomatch ->
        flat |> binary_slice(0, 160) |> String.trim()
    end
  end
end

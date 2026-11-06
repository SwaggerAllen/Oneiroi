defmodule Oneiroi.Brain.Archive do
  @moduledoc """
  The correspondence from before the platform (brain#56): threads filed
  by hand under `correspondence/<thread>/` in her repository, one file a
  letter beside a `thread.md` that says who it is with. They are library
  documents (the witness sees them on the Library's Correspondence
  shelf) and were never messages: Xenia's rows begin with the reader's
  first delivery, and the repository's import registered the files
  without making messages of them. So the correspondence tools read them
  here, as the archive, threads and all.
  """

  alias Oneiroi.Seshat

  @page 20_000

  @doc "The archive's threads, each with who it is with, how many letters and the days they span."
  def threads(resident_id) do
    resident_id
    |> Seshat.documents()
    |> Enum.filter(&(&1.kind == "correspondence"))
    |> Enum.group_by(&thread_of(&1.path))
    |> Enum.reject(fn {thread, _docs} -> is_nil(thread) end)
    |> Enum.map(fn {thread, docs} -> summary(resident_id, thread, docs) end)
    |> Enum.sort_by(& &1.last, :desc)
  end

  @doc "One thread whole, its `thread.md` first and the letters in order, a page at a time from a character offset."
  def read(resident_id, thread, from \\ 0) do
    paths =
      resident_id
      |> Seshat.documents()
      |> Enum.filter(&(&1.kind == "correspondence" and thread_of(&1.path) == thread))
      |> Enum.map(& &1.path)
      |> Enum.sort_by(&{Path.basename(&1) != "thread.md", &1})

    case paths do
      [] ->
        :none

      _some ->
        whole =
          Enum.map_join(paths, "\n\n", fn path ->
            "## #{Path.basename(path)}\n\n" <> content(resident_id, path)
          end)

        total = String.length(whole)
        from = max(from, 0)
        next = if from + @page < total, do: from + @page, else: nil
        {:ok, String.slice(whole, from, @page), next, total}
    end
  end

  defp summary(resident_id, thread, docs) do
    letters = Enum.reject(docs, &(Path.basename(&1.path) == "thread.md"))
    days = letters |> Enum.map(&day_of(&1.path)) |> Enum.reject(&is_nil/1) |> Enum.sort()
    head = Enum.find(docs, &(Path.basename(&1.path) == "thread.md"))

    %{
      thread: thread,
      with: if(head, do: with_of(content(resident_id, head.path)), else: []),
      letters: length(letters),
      first: List.first(days),
      last: List.last(days) || ""
    }
  end

  defp thread_of("correspondence/" <> rest) do
    case String.split(rest, "/") do
      [thread, _file] -> thread
      _other -> nil
    end
  end

  defp thread_of(_path), do: nil

  defp day_of(path) do
    case Regex.run(~r/\A(\d{4}-\d{2}-\d{2})/, Path.basename(path)) do
      [_, day] -> day
      nil -> nil
    end
  end

  # The frontmatter's `with:` list, the people the thread is with.
  defp with_of(text) do
    case Regex.run(~r/^with:\s*\n((?:\s*-\s*.+\n?)+)/m, text) do
      [_, block] ->
        for line <- String.split(block, "\n"),
            name = line |> String.trim() |> String.trim_leading("-") |> String.trim(),
            name != "",
            do: name

      nil ->
        []
    end
  end

  defp content(resident_id, path) do
    case Seshat.document(resident_id, path) do
      {:ok, %{content: content}} when is_binary(content) -> content
      _missing -> "(this file could not be read)"
    end
  end
end

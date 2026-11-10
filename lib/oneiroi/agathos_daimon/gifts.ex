defmodule Oneiroi.AgathosDaimon.Gifts do
  @moduledoc """
  The creation flow's nine gifts (spec §6.2, F3; agathos-daimon#36), each
  with what it writes and the guidance the witness reads before giving
  it. The guidance lives once, here, in `priv/creation/`: the flow's
  screens show it, and the pre-filled path's generator will read the same
  words, so the witness reads the same text either way (the witness's
  policy, 2026-11-05). Compiled in, so a change to the words is a reviewed
  commit like any other.
  """

  @gifts [
    {"name", "A name", ["IDENTITY.md"], "1-name.md"},
    {"self", "A self", ["SOUL.md"], "2-self.md"},
    {"you", "Who you are to them", ["USER.md"], "3-you.md"},
    {"building", "What you're building together", ["GOALS.md", "LINKS.md"], "4-building.md"},
    {"trials", "Their trials", ["regression tests"], "5-trials.md"},
    {"means", "Their means", ["budget lines"], "6-means.md"},
    {"days", "Their days", ["time zone", "free time", "quiet hours"], "7-days.md"},
    {"vows", "Your vows", ["the agreement"], "8-vows.md"},
    {"reach", "Their reach", ["tier and hands"], "9-reach.md"}
  ]

  for {_key, _title, _writes, file} <- @gifts do
    @external_resource Path.join([__DIR__, "../../../priv/creation", file])
  end

  @all (for {key, title, writes, file} <- @gifts do
          guidance =
            [__DIR__, "../../../priv/creation", file]
            |> Path.join()
            |> File.read!()
            |> String.trim()

          %{key: key, title: title, writes: writes, guidance: guidance}
        end)

  @doc "The nine gifts in the flow's order, each with what it writes and its guidance."
  def all, do: @all

  @doc "The gift that writes `file` (an identity file such as `SOUL.md`), or nil."
  @spec for_file(String.t()) :: map() | nil
  def for_file(file), do: Enum.find(@all, &(file in &1.writes))

  @doc """
  The example sets (agathos-daimon#41): each folder under
  `priv/creation/examples/` is one, its files the gifts' files it holds,
  in the gifts' order, and its `prompt.md` the prompt the generator was
  given, when there is one. Read at the call, not compiled in, so a set
  committed later is served without a change here; no folder, or none
  holding a gift's file, is `[]`.
  """
  @spec examples() :: [map()]
  # The paths are the priv folder this repository ships, a folder name
  # it lists there and a file name from the gifts' own list: no request
  # value reaches them.
  # sobelow_skip ["Traversal.FileModule"]
  def examples do
    root = Path.join(:code.priv_dir(:oneiroi), "creation/examples")

    case File.ls(root) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.filter(&File.dir?(Path.join(root, &1)))
        |> Enum.map(&example_set(root, &1))
        |> Enum.reject(&(&1.files == []))

      {:error, _absent} ->
        []
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp example_set(root, set) do
    dir = Path.join(root, set)

    files =
      for gift <- @all,
          file <- gift.writes,
          String.ends_with?(file, ".md"),
          {:ok, content} <- [File.read(Path.join(dir, file))] do
        %{file: file, gift: gift.key, title: gift.title, content: content}
      end

    prompt =
      case File.read(Path.join(dir, "prompt.md")) do
        {:ok, text} -> String.trim(text)
        {:error, _absent} -> nil
      end

    %{set: set, prompt: prompt, files: files}
  end
end

defmodule Oneiroi.Platform.Policies.Gates do
  @moduledoc """
  The `gates` check (conventions §2, §13): the gate set is one block,
  identical in three author-owned places, and a difference is a gate that
  one of them is not running.

  The three sources, each read as the literal thing it is rather than
  parsed loosely:

    * `pipeline.config.json`'s `qualityGates`, the scope this check is
      registered under; what orchestration runs before a dev pass finishes.
    * `CLAUDE.md`'s fenced block opened with the info string
      `oneiroi:gates`, one command per line, a trailing `# comment`
      stripped; what a contributor runs locally.
    * `.github/workflows/ci.yml`'s steps between the comment lines
      `# oneiroi:gates` and `# oneiroi:gates end`, each a single-line
      `run:`; what CI runs on the pull request. A multi-line `run: |`
      inside the region is reported rather than guessed at, because a YAML
      parser is a dependency this check does not take and a region it
      cannot read is a region it must not pass.

  The literal fences are the point (the same discipline as the
  substrate's `oneiroi:required-env` manifest block): a check that
  accepted several spellings would let a block drift out of the one it
  reads while still looking read.

  No `oneiroi:allow` escape: there is nothing on a line to excuse, and a
  gate set with an escape hatch is a gate set with a fourth copy.
  """

  @behaviour Oneiroi.Audit.Check

  @claude "CLAUDE.md"
  @ci ".github/workflows/ci.yml"
  @fence "```oneiroi:gates"
  @start "# oneiroi:gates"
  @stop "# oneiroi:gates end"

  @impl Oneiroi.Audit.Check
  def run(scope) do
    with {:ok, config} <- config(scope),
         {:ok, claude} <- claude(@claude),
         {:ok, ci} <- ci(@ci) do
      compare(config, claude, ci)
    else
      {:error, problem} -> [problem]
    end
  end

  defp compare(config, claude, ci) do
    differences(scope_name(), "CLAUDE.md", config, claude) ++
      differences(scope_name(), "ci.yml", config, ci)
  end

  defp scope_name, do: "qualityGates"

  defp differences(_a, _b, same, same), do: []

  defp differences(a, b, left, right) do
    missing = for line <- left, line not in right, do: "#{b} lacks #{a}'s gate: #{line}"
    extra = for line <- right, line not in left, do: "#{a} lacks #{b}'s gate: #{line}"

    order =
      if missing == [] and extra == [],
        do: ["#{a} and #{b} run the same gates in a different order"],
        else: []

    Enum.map(missing ++ extra ++ order, &problem/1)
  end

  ## pipeline.config.json

  defp config(path) do
    with {:ok, body} <- read(path),
         {:ok, json} <- decode(path, body),
         {:ok, gates} <- gates(path, json) do
      {:ok, Enum.map(gates, &String.trim/1)}
    end
  end

  defp decode(path, body) do
    case Jason.decode(body) do
      {:ok, json} when is_map(json) -> {:ok, json}
      _other -> {:error, problem("#{path} is not a JSON object")}
    end
  end

  defp gates(path, json) do
    case Map.get(json, "qualityGates") do
      gates when is_list(gates) and gates != [] ->
        if Enum.all?(gates, &is_binary/1),
          do: {:ok, gates},
          else: {:error, problem("#{path}'s qualityGates carries a non-string entry")}

      _other ->
        {:error, problem("#{path} declares no qualityGates list")}
    end
  end

  ## CLAUDE.md

  defp claude(path) do
    with {:ok, body} <- read(path) do
      body
      |> String.split(["\r\n", "\n"])
      |> Enum.drop_while(&(String.trim(&1) != @fence))
      |> case do
        [] ->
          {:error, problem("#{path} has no #{@fence} block")}

        [_open | rest] ->
          {:ok, rest |> Enum.take_while(&(String.trim(&1) != "```")) |> commands()}
      end
    end
  end

  # A trailing `# comment` is prose about the gate, not the gate.
  defp commands(lines) do
    for line <- lines,
        command = line |> strip_comment() |> String.trim(),
        command != "",
        do: command
  end

  defp strip_comment(line) do
    case Regex.run(~r/^(.*?)\s+#\s.*$/, line) do
      [_all, before] -> before
      nil -> line
    end
  end

  ## ci.yml

  defp ci(path) do
    with {:ok, body} <- read(path) do
      lines = String.split(body, ["\r\n", "\n"])

      case Enum.drop_while(lines, &(String.trim(&1) != @start)) do
        [] -> {:error, problem("#{path} has no #{@start} region")}
        [_start | rest] -> region(path, Enum.take_while(rest, &(String.trim(&1) != @stop)), rest)
      end
    end
  end

  defp region(path, region, rest) do
    cond do
      length(region) == length(rest) ->
        {:error, problem("#{path}'s #{@start} region never reaches #{@stop}")}

      Enum.any?(region, &multiline_run?/1) ->
        {:error,
         problem("#{path}'s gates region carries a multi-line run: (one command per step)")}

      true ->
        {:ok, runs(region)}
    end
  end

  defp multiline_run?(line), do: Regex.match?(~r/^\s*(-\s+)?run:\s*[|>]/, line)

  defp runs(region) do
    for line <- region,
        [_all, command] <- [Regex.run(~r/^\s*(?:-\s+)?run:\s*(.+?)\s*$/, line)],
        do: command
  end

  ## Shared

  # Sobelow reads `File.read(path)` as a traversal; `path` is one of this
  # module's three attributes or the registered scope, never a request.
  # sobelow_skip ["Traversal.FileModule"]
  defp read(path) do
    case File.read(path) do
      {:ok, body} ->
        {:ok, body}

      {:error, reason} ->
        {:error, problem("#{path} cannot be read (#{:file.format_error(reason)})")}
    end
  end

  defp problem(message), do: "gates: " <> message
end

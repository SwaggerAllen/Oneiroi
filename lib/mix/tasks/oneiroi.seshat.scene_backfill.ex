defmodule Mix.Tasks.Oneiroi.Seshat.SceneBackfill do
  @shortdoc "Reads a resident's prose scenes/<day>.md files into scene rows, best-effort"
  @moduledoc """
  `mix oneiroi.seshat.scene_backfill <resident id> [--dry-run]` (seshat#52):
  each `scenes/<day>.md` written as prose before the scenes were rows is
  parsed; a day that parses cleanly becomes its scene rows, closed, and
  its file is rendered from them; a day that does not stays as prose,
  untouched, and is listed with why. A day that has rows already is
  skipped. Never run by itself: an operator runs it once, `--dry-run`
  first to read what it would do.
  """
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Seshat

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [dry_run: :boolean])
    id = List.first(rest) || Mix.raise("a resident id is required")
    Mix.Task.run("app.start")
    dry? = Keyword.get(opts, :dry_run, false)

    case Oneiroi.Seshat.backfill_scenes(id, Oneiroi.Actor.platform(), dry_run: dry?) do
      {:ok, %{rows: rows, prose: prose, skipped: skipped}} ->
        verb = if dry?, do: "would become", else: "became"
        Enum.each(rows, fn {day, n} -> Mix.shell().info("#{day}: #{verb} #{n} scene rows") end)
        Enum.each(prose, fn {day, why} -> Mix.shell().info("#{day}: stays prose (#{why})") end)
        Enum.each(skipped, &Mix.shell().info("#{&1}: has rows already, skipped"))

      {:error, reason} ->
        Mix.raise("backfill refused: #{inspect(reason)}")
    end
  end
end

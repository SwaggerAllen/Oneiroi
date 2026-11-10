defmodule Mix.Tasks.Oneiroi.Creation.Examples do
  @shortdoc "Generates an example set of the gifts' files through the generator"
  @moduledoc """
  `mix oneiroi.creation.examples --resident <id> --prompt "<who to wake>"
  [--set fictional] [--out <dir>]` (agathos-daimon#41): runs the
  generator (agathos-daimon#39) for a resident in creation, so the calls
  are billed to that resident's witness under drafting, and writes each
  drafted file, with the prompt as `prompt.md`, into
  `priv/creation/examples/<set>/` (or `--out`). Nothing is written to the
  resident: the drafts are only copied out.

  It makes real model calls on the witness's key, so it is never run by
  itself, by CI or by a test against a real provider; an operator runs it
  with the witness's OK on the spend, reads every file, and commits the
  set by hand. A run that stops short writes nothing, so a set is never
  half one person. The model's slug is printed, not written: no model
  identifier lands in the repository.
  """
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Brain

  @impl Mix.Task
  # The output folder is the operator's own argument on the operator's
  # own machine; no request value reaches it.
  # sobelow_skip ["Traversal.FileModule"]
  def run(args) do
    {opts, _rest, _} =
      OptionParser.parse(args,
        strict: [resident: :string, prompt: :string, set: :string, out: :string]
      )

    id = opts[:resident] || Mix.raise("--resident <id> is required: a resident in creation")
    prompt = opts[:prompt] || Mix.raise("--prompt is required: who the example wakes as")
    set = opts[:set] || "fictional"

    unless Regex.match?(~r/\A[a-z0-9][a-z0-9-]*\z/, set),
      do: Mix.raise("--set is a folder name: lower case, digits and -")

    out = opts[:out] || Path.join(["priv", "creation", "examples", set])
    Mix.Task.run("app.start")
    id |> generate(prompt) |> write(prompt, out)
  end

  defp generate(id, prompt) do
    case Oneiroi.AgathosDaimon.fetch(id) do
      {:ok, row} ->
        Oneiroi.Brain.generate_gifts(id, prompt, Oneiroi.Actor.new(:witness, row.account_id))

      :error ->
        Mix.raise("no resident has the id #{id}")
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp write({:ok, %{drafts: drafts, stopped: nil}}, prompt, out) do
    File.mkdir_p!(out)
    File.write!(Path.join(out, "prompt.md"), String.trim(prompt) <> "\n")

    for d <- drafts do
      File.write!(Path.join(out, d.file), String.trim(d.content) <> "\n")
      Mix.shell().info("#{d.file}: drafted by #{d.model}")
    end

    Mix.shell().info("wrote #{length(drafts)} files to #{out}; read them before committing")
  end

  defp write({:ok, %{stopped: stopped}}, _prompt, _out),
    do: Mix.raise("the run stopped at #{stopped.file} (#{stopped.message}); nothing written")

  defp write({:error, reason}, _prompt, _out),
    do: Mix.raise("the generator refused: #{inspect(reason)}")
end

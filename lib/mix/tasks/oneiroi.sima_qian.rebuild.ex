defmodule Mix.Tasks.Oneiroi.SimaQian.Rebuild do
  @shortdoc "Rebuilds a resident from a repository into this store"
  @moduledoc "`mix oneiroi.sima_qian.rebuild <url> --witness <account id>`: replay into a fresh store (spec §6.10)."
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Application

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [witness: :string])
    url = List.first(rest) || Mix.raise("a repository URL or path is required")
    witness = Keyword.get(opts, :witness) || Mix.raise("--witness is required")
    Mix.Task.run("app.start")

    case Oneiroi.SimaQian.rebuild(url, witness, Oneiroi.Actor.platform()) do
      {:ok, %{id: id, attestation: att, events: n, not_transferred: gone}} ->
        Mix.shell().info(
          "resident #{id} woke from #{url}: attestation #{att}, #{n} events replayed"
        )

        Enum.each(gone, &Mix.shell().info("  not transferred: #{&1}"))

      {:error, reason} ->
        Mix.raise("rebuild refused: #{inspect(reason)}")
    end
  end
end

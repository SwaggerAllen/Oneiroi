defmodule Mix.Tasks.Oneiroi.Records.Rebuild do
  @shortdoc "Rebuilds a resident from a repository into this store"
  @moduledoc "`mix oneiroi.records.rebuild <url> --steward <account id>`: replay into a fresh store (spec §6.10)."
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Application

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [steward: :string])
    url = List.first(rest) || Mix.raise("a repository URL or path is required")
    steward = Keyword.get(opts, :steward) || Mix.raise("--steward is required")
    Mix.Task.run("app.start")

    case Oneiroi.Records.rebuild(url, steward, Oneiroi.Actor.platform()) do
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

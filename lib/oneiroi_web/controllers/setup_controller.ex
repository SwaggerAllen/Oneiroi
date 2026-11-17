defmodule OneiroiWeb.SetupController do
  @moduledoc """
  Setting a resident up on a Mac (dioscuri#8): the bootstrap script, with
  this platform's own address in it, and the kit it downloads (the Claude
  Code plugin with its marketplace, the reader, the script), taken from
  the platform's own source (`BRAIN_SOURCE_DIR`, which the image fills).
  Public, because neither holds anything of anyone's: the SDK is
  Apache-2.0 and the token is asked for on the witness's machine, never
  served.
  """
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["setup"])

  # What the kit carries, relative to the source root: the plugin, its
  # marketplace listing, the reader and the bootstrap itself.
  @kit ["sdk/claude-code", "sdk/reader", "sdk/setup.sh", ".claude-plugin/marketplace.json"]
  @skipped ~r{(^|/)(__pycache__|node_modules|fixtures|log|state|work)(/|$)|\.pyc$}

  operation(:script,
    summary:
      "The bootstrap for a resident on a Mac (dioscuri#8): `bash <(curl -fsSL <here>/setup.sh) writer|reader --slug <slug> --resident <id>`, with this platform's address filled in",
    responses: [ok: {"the script", "text/x-shellscript", %Schema{type: :string}}]
  )

  # A fixed file under the platform's own source; nothing from the
  # request names a path.
  # sobelow_skip ["Traversal.FileModule"]
  def script(conn, _params) do
    case File.read(Path.join(root(), "sdk/setup.sh")) do
      {:ok, text} ->
        conn
        |> put_resp_content_type("text/x-shellscript")
        |> send_resp(200, String.replace(text, "__ONEIROI_URL__", endpoint_module(conn).url()))

      {:error, _} ->
        send_resp(conn, 404, "no setup script in this build\n")
    end
  end

  operation(:kit,
    summary:
      "The kit the bootstrap downloads (dioscuri#8): the Claude Code plugin and its marketplace, the reader, and the bootstrap, as a gzipped tar",
    responses: [ok: {"the kit", "application/gzip", %Schema{type: :string, format: :binary}}]
  )

  # The archive is written to a file of its own under the temp dir and
  # read back; nothing from the request names a path.
  # sobelow_skip ["Traversal.FileModule"]
  def kit(conn, _params) do
    path =
      Path.join(System.tmp_dir!(), "oneiroi-kit-#{System.unique_integer([:positive])}.tar.gz")

    try do
      with entries when entries != [] <- entries(root()),
           :ok <- :erl_tar.create(String.to_charlist(path), entries, [:compressed]),
           {:ok, bytes} <- File.read(path) do
        conn
        |> put_resp_content_type("application/gzip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="oneiroi-kit.tar.gz"))
        |> send_resp(200, bytes)
      else
        _ -> send_resp(conn, 404, "no kit in this build\n")
      end
    after
      File.rm(path)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp entries(root) do
    for part <- @kit,
        full = Path.join(root, part),
        file <- files(full),
        rel = Path.relative_to(file, root),
        not Regex.match?(@skipped, rel),
        do: {String.to_charlist(rel), String.to_charlist(file)}
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp files(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> Path.join("**")
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&File.regular?/1)

      true ->
        []
    end
  end

  defp root, do: Path.expand(Oneiroi.Config.fetch!(:brain, :source_dir))
end

defmodule OneiroiWeb.ImportController do
  @moduledoc """
  A ChatGPT export taken into a resident's records (sima-qian#47): the
  zip as the request's body, streamed to a temporary file up to
  `SIMA_QIAN_IMPORT_MAX_BYTES`, read, captured, and its report filed in
  the library as `system/imports/chatgpt-<day>.md`. The witness's.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:chatgpt,
    summary:
      "Take a ChatGPT export's zip (the request body, application/zip) into the resident's records: its conversations as imported sessions, its memories and gaps in a report",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"what came across", "application/json", %Schema{type: :object}}]
  )

  # sobelow_skip ["Traversal.FileModule"]
  def chatgpt(conn, %{"id" => id}) do
    zip = Path.join(System.tmp_dir!(), "chatgpt-upload-#{System.unique_integer([:positive])}.zip")
    max = Oneiroi.Config.fetch!(:sima_qian, :import_max_bytes)

    try do
      case stream(conn, zip, max) do
        {:ok, conn} ->
          imported(conn, id, zip)

        {:too_large, conn} ->
          problem(
            conn,
            413,
            :too_large,
            :web_import_too_large,
            "the export is larger than #{max} bytes"
          )

        {:error, conn} ->
          problem(
            conn,
            400,
            :unreadable_body,
            :web_import_body_unreadable,
            "the upload did not arrive whole"
          )
      end
    after
      File.rm(zip)
    end
  end

  defp imported(conn, id, zip) do
    %{account_id: account} = conn.assigns.principal

    with {:ok, result} <- Oneiroi.SimaQian.import_chatgpt(id, zip, account, actor(conn)),
         {:ok, _} <- Oneiroi.Seshat.write(id, result.report_path, result.report, actor(conn)) do
      json(conn, Map.delete(result, :report))
    else
      {:error, e} -> error(conn, 422, e)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp stream(conn, path, max) do
    {:ok, file} = File.open(path, [:write, :binary])

    try do
      loop(conn, file, 0, max)
    after
      File.close(file)
    end
  end

  defp loop(conn, file, size, max) do
    case Plug.Conn.read_body(conn, length: 1_000_000, read_length: 1_000_000) do
      {:ok, chunk, conn} -> take(conn, file, chunk, size, max, :done)
      {:more, chunk, conn} -> take(conn, file, chunk, size, max, :more)
      {:error, _reason} -> {:error, conn}
    end
  end

  defp take(conn, _file, chunk, size, max, _state) when size + byte_size(chunk) > max,
    do: {:too_large, conn}

  defp take(conn, file, chunk, size, max, state) do
    case {write(file, chunk, conn, state), state} do
      {{:ok, conn}, :more} -> loop(conn, file, size + byte_size(chunk), max)
      {result, _done} -> result
    end
  end

  defp write(file, chunk, conn, _state) do
    case IO.binwrite(file, chunk) do
      :ok -> {:ok, conn}
      {:error, _} -> {:error, conn}
    end
  end

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_import_not_witnessed
          )
        )
        |> halt()
  end
end

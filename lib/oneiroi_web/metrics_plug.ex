defmodule OneiroiWeb.MetricsPlug do
  @moduledoc """
  `/metrics` (apsu#25): the Prometheus text, to a scrape that sends the
  bearer token `APSU_METRICS_TOKEN`; without the token set, the route does
  not exist (404), and with a wrong or missing one it is refused (401).
  Answered ahead of the router, like the health probe, so it carries no
  session and touches no tenant.
  """
  import Plug.Conn

  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["metrics"]} = conn, _opts) do
    case Config.fetch!(:apsu, :metrics_token) |> unwrap() do
      nil -> conn |> send_resp(404, "") |> halt()
      token -> if authorized?(conn, token), do: scrape(conn), else: refuse(conn)
    end
  end

  def call(conn, _opts), do: conn

  defp unwrap(nil), do: nil

  defp unwrap(secret) do
    case Secret.unwrap(secret) do
      value when is_binary(value) and value != "" -> value
      _empty -> nil
    end
  end

  defp authorized?(conn, token) do
    case get_req_header(conn, "authorization") do
      # Compared by hash, so the time taken says nothing of the token.
      ["Bearer " <> given] -> :crypto.hash(:sha256, given) == :crypto.hash(:sha256, token)
      _none -> false
    end
  end

  defp refuse(conn), do: conn |> send_resp(401, "") |> halt()

  defp scrape(conn) do
    case PromEx.get_metrics(OneiroiWeb.Metrics) do
      :prom_ex_down ->
        conn |> send_resp(503, "") |> halt()

      text ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, text)
        |> halt()
    end
  end
end

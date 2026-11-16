defmodule OneiroiWeb.RawBody do
  @moduledoc """
  Keeps the body as it arrived for the one route whose signature is over
  the bytes, not the parsed JSON: the payment provider's webhook
  (nisaba#23). Every other request is read as before, and nothing is kept.
  """

  @signed ["/v1/billing/stripe"]

  def read_body(%Plug.Conn{request_path: path} = conn, opts) when path in @signed do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      {:ok, body, Plug.Conn.assign(conn, :raw_body, [body | conn.assigns[:raw_body] || []])}
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  @doc "The body as it arrived, in order."
  def of(conn),
    do: conn.assigns |> Map.get(:raw_body, []) |> Enum.reverse() |> IO.iodata_to_binary()
end

defmodule OneiroiWeb.Plugs.Authenticate do
  @moduledoc """
  Resolves the request's principal (spec §7): a bearer token first (a
  script), else the session cookie (the client). Assigns `:principal`,
  or `nil`; whether a route needs one is `OneiroiWeb.Plugs.RequirePrincipal`'s.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    principal =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> raw] -> token(raw)
        _other -> cookie(conn)
      end

    assign(conn, :principal, principal)
  end

  # An account's token first, else an adapter's (spec §8): two hashes,
  # two stores, one header.
  defp token(raw) do
    with :error <- Oneiroi.Gaia.authenticate_token(raw),
         :error <- Oneiroi.AgathosDaimon.authenticate_adapter(raw) do
      nil
    else
      {:ok, principal} -> principal
    end
  end

  # A bearer-only pipeline (the MCP server's) fetches no session, and a
  # session that was never fetched cannot be read.
  defp cookie(%Plug.Conn{private: %{plug_session: _}} = conn),
    do: session(get_session(conn, :sid))

  defp cookie(_conn), do: nil

  defp session(nil), do: nil

  defp session(raw) do
    case Oneiroi.Gaia.authenticate_session(raw) do
      {:ok, principal} -> principal
      :error -> nil
    end
  end
end

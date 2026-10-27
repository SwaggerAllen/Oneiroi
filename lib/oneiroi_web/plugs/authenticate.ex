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
        _other -> session(get_session(conn, :sid))
      end

    assign(conn, :principal, principal)
  end

  defp token(raw) do
    case Oneiroi.Gaia.authenticate_token(raw) do
      {:ok, principal} -> principal
      :error -> nil
    end
  end

  defp session(nil), do: nil

  defp session(raw) do
    case Oneiroi.Gaia.authenticate_session(raw) do
      {:ok, principal} -> principal
      :error -> nil
    end
  end
end

defmodule OneiroiWeb.Plugs.Origin do
  @moduledoc """
  Every mutation checks `Origin` (spec §6.1): a request that changes
  state and arrived without a bearer token must carry an `Origin` equal
  to the endpoint's own, or it is refused with 403 before any controller
  runs. A bearer token is a script's proof and a script has no origin;
  the session cookie is a browser's, and the browser is where a forged
  cross-site request comes from. Login itself is a mutation and is
  checked, because a forged login is a real attack.
  """
  @behaviour Plug

  import Plug.Conn

  @safe ~w(GET HEAD OPTIONS)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method} = conn, _opts) when method in @safe, do: conn

  def call(conn, _opts) do
    case conn.assigns[:principal] do
      %{via: :token} -> conn
      _other -> check(conn)
    end
  end

  # The endpoint is read off the conn, where Phoenix put it, rather than
  # named: the endpoint plugs the router, the router plugs this, and a
  # literal `OneiroiWeb.Endpoint` here closed a dependency cycle the
  # cycles gate refuses.
  defp check(conn) do
    expected = conn.private.phoenix_endpoint.url()

    case get_req_header(conn, "origin") do
      [^expected] ->
        conn

      _other ->
        conn
        |> put_status(403)
        |> Phoenix.Controller.json(%{
          error: %{
            kind: "origin_refused",
            meaning: "a mutation from a browser must carry the endpoint's own Origin"
          }
        })
        |> halt()
    end
  end
end

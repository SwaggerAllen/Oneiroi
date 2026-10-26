defmodule OneiroiWeb.Plugs.SecureHeaders do
  @moduledoc """
  The headers every response carries (spec §6.1): a CSP that allows the
  client's own bundle and nothing else, HSTS (the half Render's edge does
  not supply; `Config.HTTPS` is ignored for the probe's sake, conventions
  §2), no sniffing, no framing, no referrer leak.
  """
  @behaviour Plug

  import Plug.Conn

  @csp "default-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> put_resp_header("content-security-policy", @csp)
    |> put_resp_header("strict-transport-security", "max-age=31536000; includeSubDomains")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("referrer-policy", "no-referrer")
  end
end

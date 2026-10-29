defmodule OneiroiWeb.UserSocket do
  @moduledoc """
  The one socket. A connection names its principal with a `token` param:
  a short-lived socket token minted at `POST /v1/me/socket-token` for the
  client, or an API token for a script. The cookie is not read here on
  purpose: Phoenix's session on a socket wants a CSRF token this app
  does not keep (its CSRF defence is the Origin check, `systems/gaia.md`
  #5), and `check_origin`, on by default against the endpoint's own
  host, is the socket's equivalent.
  """
  use Phoenix.Socket

  alias Oneiroi.Gaia.Principal

  channel("session:*", OneiroiWeb.SessionChannel)

  # Five minutes: long enough to open a socket after fetching it, short
  # enough that a token read off a client is nearly spent.
  @salt "oneiroi socket"
  @max_age 300

  @doc "Mints a socket token for the account behind a request."
  @spec token(Plug.Conn.t(), String.t()) :: String.t()
  def token(conn, account_id), do: Phoenix.Token.sign(conn, @salt, account_id)

  @impl Phoenix.Socket
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case principal(socket, token) do
      %Principal{} = principal -> {:ok, assign(socket, :principal, principal)}
      nil -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl Phoenix.Socket
  def id(socket), do: "account:" <> socket.assigns.principal.account_id

  defp principal(socket, token) do
    case Phoenix.Token.verify(socket, @salt, token, max_age: @max_age) do
      {:ok, account_id} -> %Principal{account_id: account_id, via: :session}
      {:error, _} -> api_token(token)
    end
  end

  defp api_token(raw) do
    case Oneiroi.Gaia.authenticate_token(raw) do
      {:ok, principal} -> principal
      :error -> nil
    end
  end
end

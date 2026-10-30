defmodule OneiroiWeb.MCPController do
  @moduledoc """
  Memory tools over MCP (spec §8, interface 1): a streamable-HTTP MCP
  server at `/mcp`, JSON-RPC 2.0 over POST, answering `initialize`,
  `ping`, `tools/list` and `tools/call` with the brain's own tool table
  (`Oneiroi.Brain.Tools`), for a bearer token naming a resident and the
  brain role. Hands roles get no tools in this phase.

  A tool that needs a turn (a bookmark's anchor, an enactment) runs
  against the adapter's open turn, the latest `turn-start` not yet
  captured; without one it answers in words, as the brain's own tools do
  on misuse. Responses are plain JSON rather than an event stream, which
  the streamable-HTTP transport allows for a request that needs no
  server-initiated messages.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Kumbukumbu

  @protocol "2025-06-18"
  @needs_turn ~w(bookmark_add habit_cite seed_cite)

  plug(:brain_adapter)

  operation(:rpc, false)

  def rpc(conn, %{"jsonrpc" => "2.0", "method" => method} = request) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    case {method, id} do
      {"notifications/" <> _, _} -> send_resp(conn, 202, "")
      {_, nil} -> send_resp(conn, 202, "")
      _ -> json(conn, response(id, handle(method, params, adapter(conn))))
    end
  end

  def rpc(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{
      jsonrpc: "2.0",
      id: nil,
      error: %{code: -32_600, message: "not a JSON-RPC 2.0 request"}
    })
  end

  defp handle("initialize", _params, _adapter) do
    {:ok,
     %{
       protocolVersion: @protocol,
       capabilities: %{tools: %{listChanged: false}},
       serverInfo: %{name: "oneiroi", version: "0.1.0"}
     }}
  end

  defp handle("ping", _params, _adapter), do: {:ok, %{}}

  defp handle("tools/list", _params, _adapter) do
    tools =
      Enum.map(Tools.definitions(), fn %{function: f} ->
        %{name: f.name, description: f.description, inputSchema: f.parameters}
      end)

    {:ok, %{tools: tools}}
  end

  defp handle("tools/call", %{"name" => name} = params, %AdapterPrincipal{} = adapter) do
    arguments = Map.get(params, "arguments", %{})
    turn = turn_of(adapter)

    text =
      if name in @needs_turn and turn.turn_ref == nil,
        do: "No turn is open: report turn-start first, then call this.",
        else: Tools.run(name, Phoenix.json_library().encode!(arguments), turn)

    {:ok, %{content: [%{type: "text", text: text}], isError: false}}
  end

  defp handle("tools/call", _params, _adapter), do: {:error, -32_602, "tools/call needs a name"}
  defp handle(method, _params, _adapter), do: {:error, -32_601, "no method " <> method}

  defp response(id, {:ok, result}), do: %{jsonrpc: "2.0", id: id, result: result}

  defp response(id, {:error, code, message}),
    do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}

  # The turn the tool runs in: the adapter's open turn, with the
  # resident's actor; the instant stands in for the turn's start.
  defp turn_of(%AdapterPrincipal{resident_id: id, adapter: name}) do
    {session_key, turn_ref} = Kumbukumbu.open_turn(id, name) || {nil, nil}

    %{
      resident_id: id,
      session_key: session_key,
      turn_ref: turn_ref,
      started_at: Clock.now(),
      resident: Actor.new(:resident, id)
    }
  end

  defp brain_adapter(conn, _opts) do
    case adapter(conn) do
      %AdapterPrincipal{role: "brain"} ->
        conn

      _other ->
        conn
        |> put_status(401)
        |> json(%{
          jsonrpc: "2.0",
          id: nil,
          error: %{code: -32_001, message: "a brain adapter's bearer token is required"}
        })
        |> halt()
    end
  end
end

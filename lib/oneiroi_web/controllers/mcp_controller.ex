defmodule OneiroiWeb.MCPController do
  @moduledoc """
  Memory tools over MCP (spec §8, interface 1): a streamable-HTTP MCP
  server at `/mcp`, JSON-RPC 2.0 over POST, answering `initialize`,
  `ping`, `tools/list` and `tools/call` with the brain's own tool table
  (`Oneiroi.Brain.Tools`), for a bearer token naming a resident and the
  brain role. Hands roles get no tools in this phase.

  Every tool runs in a turn (a bookmark's anchor, an enactment, the room
  a search reaches): the one the call names in `turn` when that is an
  open turn of this adapter's, else the adapter's newest open turn
  (kumbukumbu #41). Two Claude Code sessions open at once each have an
  open turn, and nothing Claude Code sends an HTTP MCP server says which
  session a call came from, so the ref rides the call: each turn's
  context names it, and every tool here takes it. A tool that needs a
  turn with none open answers in words, as the brain's own tools do on
  misuse. Responses are plain JSON rather than an event stream, which
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
  @needs_turn ~w(bookmark_add habit_cite seed_cite soul_cite)

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
        %{name: f.name, description: f.description, inputSchema: with_turn(f.parameters)}
      end)

    {:ok, %{tools: tools}}
  end

  defp handle("tools/call", %{"name" => name} = params, %AdapterPrincipal{} = adapter) do
    {named, arguments} = params |> Map.get("arguments", %{}) |> arguments() |> Map.pop("turn")
    attribution = Kumbukumbu.attribute(adapter.resident_id, adapter.adapter, ref(named))
    turn = turn_of(adapter, attribution)

    text =
      if name in @needs_turn and turn.turn_ref == nil,
        do: "No turn is open: report turn-start first, then call this.",
        else:
          Tools.run(name, Phoenix.json_library().encode!(arguments), turn) <>
            fallback_note(name, named, attribution)

    {:ok,
     %{
       content: [%{type: "text", text: text}],
       isError: false,
       _meta: %{
         "oneiroi/turn" => %{ref: attribution.turn_ref, rule: Atom.to_string(attribution.rule)}
       }
     }}
  end

  defp handle("tools/call", _params, _adapter), do: {:error, -32_602, "tools/call needs a name"}
  defp handle(method, _params, _adapter), do: {:error, -32_601, "no method " <> method}

  defp response(id, {:ok, result}), do: %{jsonrpc: "2.0", id: id, result: result}

  defp response(id, {:error, code, message}),
    do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}

  # The turn the tool runs in, as `Kumbukumbu.attribute/3` chose it,
  # with the resident's actor; the instant stands in for the turn's start.
  defp turn_of(%AdapterPrincipal{resident_id: id}, attribution) do
    %{
      resident_id: id,
      session_key: attribution.session_key,
      turn_ref: attribution.turn_ref,
      started_at: Clock.now(),
      resident: Actor.new(:resident, id)
    }
  end

  defp arguments(%{} = arguments), do: arguments
  defp arguments(_other), do: %{}

  defp ref(named) when is_binary(named) and named != "", do: named
  defp ref(_other), do: nil

  # Every tool takes the turn it belongs to (kumbukumbu #41), beside its
  # own arguments and never required, so a runtime that cannot name it
  # still calls the tool and gets the newest open turn.
  @turn_property %{
    type: "string",
    description:
      "The turn this call belongs to, exactly as this turn's context names it. With two conversations open at once, it is what keeps this call on this conversation."
  }

  defp with_turn(%{properties: properties} = schema),
    do: %{schema | properties: Map.put(properties, :turn, @turn_property)}

  defp with_turn(schema), do: schema

  # Said only when the call wrote something somewhere it did not name
  # and there was more than one place it could have gone: the resident
  # can see which conversation it went to, and name the turn next time.
  # A read needs no word on it, nor a call with one open turn to go to.
  defp fallback_note(name, named, %{rule: :newest, label: label, open: open}) do
    if Tools.trial_kind(name) == :read or open < 2 do
      ""
    else
      where = if label, do: "the conversation in #{label}", else: "the newest open conversation"

      why =
        if ref(named),
          do: "The turn named is not one open here",
          else: "No turn was named"

      "\n\n(#{why}, so this went to #{where}. Name this turn as `turn`, as your context gives it, to keep it on this conversation.)"
    end
  end

  defp fallback_note(_name, _named, _attribution), do: ""

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

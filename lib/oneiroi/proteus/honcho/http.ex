defmodule Oneiroi.Proteus.Honcho.HTTP do
  @moduledoc """
  Honcho over its HTTP API, v3, on the admin key that never leaves the
  core (spec §6.9). The paths are read from v3.2.2's routers: workspaces,
  peers, sessions, messages, conclusions and keys under `/v3`. **The
  request and response bodies are claims**: the schema modules were not
  reachable when this was written, so the field names here (`name`,
  `peer_names`, `messages[].peer_name`, `peer_card`, `configuration`,
  `filters.observer`/`observed`) are what the routers read and what the
  docs describe, not what a recorded fixture shows. The integration
  layer against the pinned image is the measurement (conventions §9);
  until then every shape is marked so a mismatch is found there and not
  guessed at here.
  """
  @behaviour Oneiroi.Proteus.Honcho

  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  @impl true
  def ensure_workspace(ws), do: post(["workspaces"], %{name: ws}) |> ok()

  @impl true
  def ensure_peer(ws, peer, config) do
    with {:ok, _} <- post(["workspaces", ws, "peers"], %{name: peer, configuration: config}),
         {:ok, _} <- put(["workspaces", ws, "peers", peer], %{configuration: config}) do
      :ok
    end
  end

  @impl true
  def ensure_session(ws, session, peers) do
    body = %{name: session, peer_names: Map.new(peers, &{&1, %{}})}
    post(["workspaces", ws, "sessions"], body) |> ok()
  end

  @impl true
  def add_messages(_ws, _session, []), do: :ok

  def add_messages(ws, session, messages) do
    body = %{
      messages:
        Enum.map(messages, fn m ->
          %{peer_name: m.peer, content: m.content, created_at: DateTime.to_iso8601(m.created_at)}
        end)
    }

    post(["workspaces", ws, "sessions", session, "messages"], body) |> ok()
  end

  @impl true
  def get_card(ws, peer) do
    case get(["workspaces", ws, "peers", peer, "card"], []) do
      {:ok, %{"peer_card" => lines}} when is_list(lines) -> {:ok, lines}
      {:ok, _other} -> {:ok, []}
      error -> error
    end
  end

  @impl true
  def set_card(ws, peer, card),
    do: put(["workspaces", ws, "peers", peer, "card"], %{peer_card: card}) |> ok()

  @impl true
  def context(ws, observer, target, tokens) do
    case get(["workspaces", ws, "peers", observer, "context"], target: target, tokens: tokens) do
      {:ok, %{"representation" => text}} when is_binary(text) -> {:ok, text}
      {:ok, body} when is_map(body) -> {:ok, Map.get(body, "content", "") |> to_string()}
      error -> error
    end
  end

  @impl true
  def conclusions(ws, observer, target, limit) do
    body = %{filters: %{observer: observer, observed: target}}

    case post(["workspaces", ws, "conclusions", "list"], body, size: limit) do
      {:ok, %{"items" => items}} when is_list(items) ->
        {:ok, Enum.map(items, &%{id: to_string(&1["id"]), content: to_string(&1["content"])})}

      {:ok, _other} ->
        {:ok, []}

      error ->
        error
    end
  end

  @impl true
  def delete_conclusion(ws, id), do: delete(["workspaces", ws, "conclusions", id]) |> ok()

  @impl true
  def mint_key(ws, peer, expires_at) do
    params =
      [workspace_id: ws, expires_at: DateTime.to_iso8601(expires_at)] ++
        if(peer, do: [peer_id: peer], else: [])

    case post(["keys"], %{}, params) do
      {:ok, %{"key" => key}} when is_binary(key) -> {:ok, key}
      {:ok, other} -> {:error, {:rejected, other}}
      error -> error
    end
  end

  # ---- transport ----

  defp post(path, body, params \\ []), do: request(:post, path, json: body, params: params)
  defp put(path, body), do: request(:put, path, json: body)
  defp get(path, params), do: request(:get, path, params: params)
  defp delete(path), do: request(:delete, path, [])

  # The one place the host is spelled outside the port: the setting the
  # port reads it from.
  defp request(method, path, opts) do
    url = Path.join([Config.fetch!(:proteus, :honcho_url), "v3" | path])
    key = Config.fetch!(:proteus, :honcho_admin_key)

    opts =
      Keyword.merge(opts,
        method: method,
        url: url,
        auth: {:bearer, Secret.unwrap(key)},
        receive_timeout: Config.fetch!(:proteus, :request_timeout_ms),
        retry: false
      )

    # Not a model call: Honcho is its own external, behind its own port
    # (`Oneiroi.Proteus.Honcho`, registered in `externals/0`), and the
    # `model_port` check reads every Req call as the ledger's. This is
    # the one HTTP call outside the provider port, and it is this file.
    # oneiroi:allow model_port
    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:rejected, {status, body}}}
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  defp ok({:ok, _body}), do: :ok
  defp ok(error), do: error
end

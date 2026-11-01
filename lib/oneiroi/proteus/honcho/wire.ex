defmodule Oneiroi.Proteus.Honcho.Wire do
  @moduledoc """
  Every request the bridge makes of Honcho, built in one place (proteus
  #9): the method, the path under `/v3`, the query and the body, in the
  names the deployed server declares (`test/fixtures/proteus/honcho-server.json`,
  read from its source at the pinned commit). `Honcho.HTTP` sends what
  this builds; `Honcho.Fake` checks what this builds against the recorded
  server before it answers, so a body the server refuses fails the
  in-memory suite the way it fails production. The bodies sent before
  were built in the HTTP module alone, which the fake never saw, and
  every sync of a turn went out as `peer_name` where the server reads
  `peer_id` while the suite stayed green.
  """

  @typedoc "One request: the path's segments after `/v3`, the query, the body (nil for none)."
  @type t :: %{
          method: :get | :post | :put | :delete,
          path: [String.t()],
          params: keyword(),
          body: map() | nil
        }

  # The server's own page bound (pagination_params: 1 <= size <= 100).
  @page_size 100

  @doc "The largest page the server answers."
  def page_size, do: @page_size

  @doc "Get or create the workspace (WorkspaceCreate: `id`)."
  def workspace(ws), do: request(:post, ["workspaces"], [], %{id: ws})

  @doc "Get or create a peer with its configuration (PeerCreate: `id`, `configuration`)."
  def peer(ws, peer, config),
    do: request(:post, ["workspaces", ws, "peers"], [], %{id: peer, configuration: config})

  @doc "Set an existing peer's configuration, which get-or-create leaves as it was (PeerUpdate)."
  def peer_configuration(ws, peer, config),
    do: request(:put, ["workspaces", ws, "peers", peer], [], %{configuration: config})

  @doc "Get or create a session with its peers (SessionCreate: `id`, `peers`)."
  def session(ws, session, peers) do
    body = %{id: session, peers: Map.new(peers, &{&1, %{}})}
    request(:post, ["workspaces", ws, "sessions"], [], body)
  end

  @doc """
  A turn's messages (MessageBatchCreate of MessageCreate: `peer_id`,
  `content`, `created_at`, `metadata`). Each carries the turn's ref in
  its metadata: the server keys messages by nothing the client sends and
  takes the same batch twice as two, so the ref is how a resend asks
  whether a turn already landed (`turn_messages/3`).
  """
  def messages(ws, session, messages) do
    body = %{messages: Enum.map(messages, &message/1)}
    request(:post, ["workspaces", ws, "sessions", session, "messages"], [], body)
  end

  defp message(m) do
    %{
      peer_id: m.peer,
      content: m.content,
      created_at: DateTime.to_iso8601(m.created_at),
      metadata: %{turn_ref: m.turn_ref}
    }
  end

  @doc "The first message of a session carrying a turn's ref (MessageGet, a metadata filter)."
  def turn_messages(ws, session, turn_ref) do
    request(
      :post,
      ["workspaces", ws, "sessions", session, "messages", "list"],
      [page: 1, size: 1],
      %{filters: %{metadata: %{turn_ref: turn_ref}}}
    )
  end

  @doc "The card an observer holds of a target; its own with no `target`."
  def card(ws, observer, target),
    do:
      request(:get, ["workspaces", ws, "peers", observer, "card"], target(observer, target), nil)

  @doc "Set a peer's own card (PeerCardSet: `peer_card`)."
  def set_card(ws, peer, card),
    do: request(:put, ["workspaces", ws, "peers", peer, "card"], [], %{peer_card: card})

  @doc """
  The context an observer holds on a target. The route takes no token
  bound (its query is `target`, the search options and
  `max_conclusions`), so the bridge bounds what it reads itself.
  """
  def context(ws, observer, target),
    do: request(:get, ["workspaces", ws, "peers", observer, "context"], [target: target], nil)

  @doc "One page of conclusions, filtered by the public keys (`observer_id`, `observed_id`) or not at all."
  def conclusions(ws, filters, page, size) do
    body = if filters, do: %{filters: filters}
    request(:post, ["workspaces", ws, "conclusions", "list"], [page: page, size: size], body)
  end

  @doc "Delete one conclusion."
  def delete_conclusion(ws, id),
    do: request(:delete, ["workspaces", ws, "conclusions", id], [], nil)

  @doc "A key scoped to the workspace, and to a peer when one is named, expiring (query only)."
  def key(ws, peer, expires_at) do
    params =
      [workspace_id: ws, expires_at: DateTime.to_iso8601(expires_at)] ++
        if(peer, do: [peer_id: peer], else: [])

    request(:post, ["keys"], params, nil)
  end

  @doc "One page of a workspace's peers or sessions, unfiltered."
  def list(ws, kind, page) when kind in ["peers", "sessions"],
    do: request(:post, ["workspaces", ws, kind, "list"], [page: page, size: @page_size], nil)

  @doc "A session's short and long summaries."
  def summaries(ws, session),
    do: request(:get, ["workspaces", ws, "sessions", session, "summaries"], [], nil)

  @doc """
  The request as the server reads it: the method's name, the path's
  segments, the query as strings and the body as JSON terms, which is
  what `Honcho.Recorded` checks and what a Honcho on the loopback sees.
  """
  def as_read(%{method: method, path: path, params: params, body: body}) do
    %{
      method: method |> Atom.to_string() |> String.upcase(),
      path: path,
      params: Map.new(params, fn {k, v} -> {Atom.to_string(k), to_string(v)} end),
      body: if(body, do: body |> Jason.encode!() |> Jason.decode!())
    }
  end

  defp target(peer, peer), do: []
  defp target(_observer, target), do: [target: target]

  defp request(method, path, params, body),
    do: %{method: method, path: path, params: params, body: body}
end

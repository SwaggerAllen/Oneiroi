defmodule Oneiroi.Proteus.Honcho.Fake do
  @moduledoc """
  The in-memory Honcho (conventions §9): workspaces, peers, sessions,
  messages, cards and conclusions in an ETS table keyed by workspace, so
  the no-bleed test can seed two and read each; a failure scripted for
  the calling process; a dream simulated by moving a card.

  It refuses what the deployed server refuses (proteus #9): every call
  builds the request `Honcho.HTTP` would send (`Honcho.Wire`) and asks
  the server's record (`Honcho.Recorded`) before it answers, and a
  request the server would not take is the 422 the bridge records as
  `rejected: 422`. While it answered any shape, every sync of a turn
  went out under a field the server does not read and the suite that
  counts Honcho's messages stayed green.
  """
  @behaviour Oneiroi.Proteus.Honcho

  alias Oneiroi.Proteus.Error
  alias Oneiroi.Proteus.Honcho.Recorded
  alias Oneiroi.Proteus.Honcho.Wire

  @table :proteus_honcho_fake
  @fail_key :proteus_honcho_fail

  # ---- the test's side ----

  @doc "Scripts a failure for this process's next calls, or with `for:` for a workspace's from any process."
  def fail(kind, opts \\ []) when kind in [:transport, :rejected] do
    case Keyword.get(opts, :for) do
      nil -> Process.put(@fail_key, kind)
      ws -> put({ws, :fail, :fail}, kind)
    end

    :ok
  end

  @doc "Clears this process's failure and, with `for:`, a workspace's state and failure."
  def clear(opts \\ []) do
    Process.delete(@fail_key)
    if ws = Keyword.get(opts, :for), do: :ets.match_delete(table(), {{ws, :_, :_}, :_})
    :ok
  end

  @doc "Ends a workspace's scripted failure and keeps its state: Honcho back up."
  def recover(ws) do
    :ets.delete(table(), {ws, :fail, :fail})
    :ok
  end

  @doc "A workspace's state: peers, sessions, messages, cards, conclusions."
  def state(ws) do
    table()
    |> :ets.match_object({{ws, :_, :_}, :_})
    |> Enum.group_by(fn {{_ws, kind, _key}, _} -> kind end, fn {{_ws, _kind, key}, v} ->
      {key, v}
    end)
    |> Map.new(fn {kind, entries} -> {kind, Map.new(entries)} end)
  end

  @doc "Moves a card, as a dream would."
  def move_card(ws, peer, card), do: put({ws, :card, peer}, card)

  @doc "Seeds what Honcho concluded about a target in an observer's eyes."
  def put_conclusions(ws, observer, target, conclusions),
    do: put({ws, :conclusions, {observer, target}}, conclusions)

  @doc "Seeds the context an observer holds on a target."
  def put_context(ws, observer, target, text), do: put({ws, :context, {observer, target}}, text)

  @doc "Seeds the card an observer holds of another peer (its own is `set_card/3`'s)."
  def put_card(ws, observer, target, card), do: put({ws, :card, {observer, target}}, card)

  @doc "Seeds a session's summaries, each `%{content, through}` or nil."
  def put_summaries(ws, session, short, long),
    do: put({ws, :summaries, session}, %{short: short, long: long})

  # ---- the port ----

  @impl true
  def ensure_workspace(ws) do
    with :ok <- answered(ws, Wire.workspace(ws)), do: put({ws, :workspace, ws}, true)
  end

  @impl true
  def ensure_peer(ws, peer, config) do
    with :ok <- answered(ws, Wire.peer(ws, peer, config)),
         :ok <- answered(ws, Wire.peer_configuration(ws, peer, config)),
         do: put({ws, :peer, peer}, config)
  end

  @impl true
  def ensure_session(ws, session, peers) do
    with :ok <- answered(ws, Wire.session(ws, session, peers)),
         do: put({ws, :session, session}, peers)
  end

  @impl true
  def add_messages(_ws, _session, []), do: :ok

  def add_messages(ws, session, messages) do
    with :ok <- answered(ws, Wire.messages(ws, session, messages)) do
      existing = get({ws, :messages, session}, [])
      put({ws, :messages, session}, existing ++ messages)
    end
  end

  @impl true
  def turn_sent?(ws, session, turn_ref) do
    with :ok <- answered(ws, Wire.turn_messages(ws, session, turn_ref)) do
      {:ok, {ws, :messages, session} |> get([]) |> Enum.any?(&(&1[:turn_ref] == turn_ref))}
    end
  end

  @impl true
  def get_card(ws, peer) do
    with :ok <- answered(ws, Wire.card(ws, peer, peer)), do: {:ok, get({ws, :card, peer}, [])}
  end

  @impl true
  def set_card(ws, peer, card) do
    with :ok <- answered(ws, Wire.set_card(ws, peer, card)), do: put({ws, :card, peer}, card)
  end

  @impl true
  def context(ws, observer, target) do
    with :ok <- answered(ws, Wire.context(ws, observer, target)),
         do: {:ok, get({ws, :context, {observer, target}}, "")}
  end

  @impl true
  def conclusions(ws, observer, target, limit) do
    filters = %{observer_id: observer, observed_id: target}

    with :ok <- answered(ws, Wire.conclusions(ws, filters, 1, min(limit, Wire.page_size()))),
         do: {:ok, {ws, :conclusions, {observer, target}} |> get([]) |> Enum.take(limit)}
  end

  @impl true
  def delete_conclusion(ws, id) do
    with :ok <- answered(ws, Wire.delete_conclusion(ws, id)) do
      for {{^ws, :conclusions, pair}, list} <-
            :ets.match_object(table(), {{ws, :conclusions, :_}, :_}) do
        put({ws, :conclusions, pair}, Enum.reject(list, &(&1.id == id)))
      end

      :ok
    end
  end

  @impl true
  def mint_key(ws, peer, expires_at) do
    with :ok <- answered(ws, Wire.key(ws, peer, expires_at)) do
      key =
        "fake-key-" <>
          ws <> "-" <> (peer || "workspace") <> "-" <> DateTime.to_iso8601(expires_at)

      put({ws, :key, key}, peer)
      {:ok, key}
    end
  end

  @impl true
  def peers(ws) do
    with :ok <- answered(ws, Wire.list(ws, "peers", 1)) do
      {:ok, ws |> entries(:peer) |> Enum.map(&elem(&1, 0)) |> Enum.sort()}
    end
  end

  @impl true
  def peer_card(ws, observer, target) do
    with :ok <- answered(ws, Wire.card(ws, observer, target)) do
      key = if observer == target, do: observer, else: {observer, target}
      {:ok, get({ws, :card, key}, nil)}
    end
  end

  # A seeded conclusion carries the fields it was given; the pair comes
  # from where it was seeded, and the rest take what Honcho gives an
  # explicit conclusion drawn from no session.
  @impl true
  def all_conclusions(ws) do
    with :ok <- answered(ws, Wire.conclusions(ws, nil, 1, Wire.page_size())) do
      {:ok,
       for {{observer, observed}, list} <- entries(ws, :conclusions), c <- list do
         Map.merge(
           %{session: nil, level: "explicit", sources: [], created_at: nil},
           Map.merge(c, %{observer: observer, observed: observed})
         )
       end}
    end
  end

  @impl true
  def sessions(ws) do
    with :ok <- answered(ws, Wire.list(ws, "sessions", 1)) do
      {:ok, ws |> entries(:session) |> Enum.map(&elem(&1, 0)) |> Enum.sort()}
    end
  end

  @impl true
  def summaries(ws, session) do
    with :ok <- answered(ws, Wire.summaries(ws, session)),
         do: {:ok, get({ws, :summaries, session}, %{short: nil, long: nil})}
  end

  # ---- helpers ----

  defp entries(ws, kind) do
    table()
    |> :ets.match_object({{ws, kind, :_}, :_})
    |> Enum.map(fn {{_ws, _kind, key}, value} -> {key, value} end)
  end

  # The scripted failure first, as a Honcho that is down answers nothing;
  # then the server's own refusal of the request, as its 422.
  defp answered(ws, request) do
    with :ok <- scripted(ws), do: wire(request)
  end

  @doc false
  def wire(request) do
    case request |> Wire.as_read() |> Recorded.refusal() do
      nil ->
        :ok

      problem ->
        {:error,
         Error.new(:proteus_honcho_rejected, :proteus_fake_wire_refused,
           status: 422,
           problem: problem
         )}
    end
  end

  defp scripted(ws) do
    case Process.get(@fail_key) || get({ws, :fail, :fail}, nil) do
      nil ->
        :ok

      :transport ->
        {:error, Error.caught(:proteus_honcho_unreachable, :proteus_fake_unreachable, :scripted)}

      :rejected ->
        {:error, Error.caught(:proteus_honcho_rejected, :proteus_fake_rejected, :scripted)}
    end
  end

  defp put(key, value) do
    :ets.insert(table(), {key, value})
    :ok
  end

  defp get(key, default) do
    case :ets.lookup(table(), key) do
      [{_key, value}] -> value
      [] -> default
    end
  end

  # Created on first use by whichever process gets there; a second
  # creator finds it made and uses it.
  defp table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          # Another creator got there first, which is the table made;
          # any other badarg is raised again.
          error in ArgumentError ->
            if :ets.whereis(@table) == :undefined,
              do: reraise(error, __STACKTRACE__),
              else: @table
        end

      _ref ->
        @table
    end
  end
end

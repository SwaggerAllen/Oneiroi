defmodule Oneiroi.Proteus.Honcho.Fake do
  @moduledoc """
  The in-memory Honcho (conventions §9): workspaces, peers, sessions,
  messages, cards and conclusions in an ETS table keyed by workspace, so
  the no-bleed test can seed two and read each; a failure scripted for
  the calling process; a dream simulated by moving a card.
  """
  @behaviour Oneiroi.Proteus.Honcho

  alias Oneiroi.Proteus.Error

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

  # ---- the port ----

  @impl true
  def ensure_workspace(ws), do: with(:ok <- scripted(ws), do: put({ws, :workspace, ws}, true))

  @impl true
  def ensure_peer(ws, peer, config),
    do: with(:ok <- scripted(ws), do: put({ws, :peer, peer}, config))

  @impl true
  def ensure_session(ws, session, peers),
    do: with(:ok <- scripted(ws), do: put({ws, :session, session}, peers))

  @impl true
  def add_messages(ws, session, messages) do
    with :ok <- scripted(ws) do
      existing = get({ws, :messages, session}, [])
      put({ws, :messages, session}, existing ++ messages)
    end
  end

  @impl true
  def get_card(ws, peer), do: with(:ok <- scripted(ws), do: {:ok, get({ws, :card, peer}, [])})

  @impl true
  def set_card(ws, peer, card), do: with(:ok <- scripted(ws), do: put({ws, :card, peer}, card))

  @impl true
  def context(ws, observer, target, _tokens),
    do: with(:ok <- scripted(ws), do: {:ok, get({ws, :context, {observer, target}}, "")})

  @impl true
  def conclusions(ws, observer, target, limit) do
    with :ok <- scripted(ws),
         do: {:ok, {ws, :conclusions, {observer, target}} |> get([]) |> Enum.take(limit)}
  end

  @impl true
  def delete_conclusion(ws, id) do
    with :ok <- scripted(ws) do
      for {{^ws, :conclusions, pair}, list} <-
            :ets.match_object(table(), {{ws, :conclusions, :_}, :_}) do
        put({ws, :conclusions, pair}, Enum.reject(list, &(&1.id == id)))
      end

      :ok
    end
  end

  @impl true
  def mint_key(ws, peer, expires_at) do
    with :ok <- scripted(ws) do
      key =
        "fake-key-" <>
          ws <> "-" <> (peer || "workspace") <> "-" <> DateTime.to_iso8601(expires_at)

      put({ws, :key, key}, peer)
      {:ok, key}
    end
  end

  # ---- helpers ----

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

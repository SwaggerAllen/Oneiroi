defmodule Oneiroi.Apsu.PubSub do
  @moduledoc """
  The one door to PubSub (conventions §10): a broadcast carries the trace
  id in its envelope, and a subscriber that handles the envelope through
  `receive/2` has the trace restored on its logger. Topics are rendered
  from a system's slug and the name it declared in `pubsub_topics/0`.
  """
  require Logger

  @server :apsu_pubsub

  @type envelope :: {:oneiroi, String.t(), term(), String.t() | nil}

  @doc "Broadcasts `payload` on `slug:name`, carrying the trace id."
  @spec broadcast(atom(), atom(), term()) :: :ok
  def broadcast(slug, name, payload) do
    Phoenix.PubSub.broadcast(
      @server,
      topic(slug, name),
      {:oneiroi, topic(slug, name), payload, Keyword.get(Logger.metadata(), :trace_id)}
    )
  end

  @doc "Subscribes the current process to `slug:name`."
  @spec subscribe(atom(), atom()) :: :ok
  def subscribe(slug, name), do: Phoenix.PubSub.subscribe(@server, topic(slug, name))

  @doc "Restores the trace from an envelope and returns the payload."
  @spec receive(envelope()) :: term()
  def receive({:oneiroi, _topic, payload, trace_id}) do
    Logger.metadata(trace_id: trace_id)
    payload
  end

  @doc "The topic string for a declared name, on the slug spine."
  @spec topic(atom(), atom()) :: String.t()
  def topic(slug, name), do: "#{slug}:#{name}"
end

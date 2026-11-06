defmodule OneiroiWeb.Plugs.RequirePrincipal do
  @moduledoc """
  Halts with 401 when `OneiroiWeb.Plugs.Authenticate` found no principal.

  An adapter's token (spec §8) is a principal for a listed set of paths
  and nothing else: opening its session, starting a turn (which answers
  with the turn's context), capturing one, reading the session prefix
  (brain#42); and, for the inbound hands, delivering correspondence,
  reading approved replies and marking one sent (xenia#11). Everything under `/v1` beyond those is an account's, so
  an adapter's token there is refused here, before any controller reads
  an account off it. The list is explicit so the test can assert it.
  """
  @behaviour Plug

  import Plug.Conn

  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.Gaia.Error
  alias OneiroiWeb.Controllers.Helpers

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{assigns: %{principal: %AdapterPrincipal{}}} = conn, _opts) do
    if adapter_path?(conn.method, conn.path_info), do: conn, else: refuse(conn)
  end

  def call(%Plug.Conn{assigns: %{principal: %{}}} = conn, _opts), do: conn
  def call(conn, _opts), do: refuse(conn)

  @doc "The adapter contract's paths (spec §8, interface 2), the only ones an adapter's token opens."
  @spec adapter_path?(String.t(), [String.t()]) :: boolean()
  def adapter_path?("POST", ["v1", "residents", _id, "sessions"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "turn-start"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "turns"]), do: true
  def adapter_path?("GET", ["v1", "residents", _id, "context"]), do: true
  # What waits for the adapter, by number alone, so it can wake its
  # runtime when something arrives (kumbukumbu#48).
  def adapter_path?("GET", ["v1", "residents", _id, "waiting"]), do: true
  # The reader's allowlists and research (xenia#16, seshat#38): read
  # the lists and the open questions, answer or fail one; the controller
  # holds them to the `reader` role.
  def adapter_path?("GET", ["v1", "residents", _id, "reader"]), do: true
  def adapter_path?("GET", ["v1", "residents", _id, "research"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "research", _n, "answer"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "research", _n, "failed"]), do: true
  # The digest (seshat#40): the open one, and its answer or failure.
  def adapter_path?("GET", ["v1", "residents", _id, "digests"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "digests", _n, "answer"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "digests", _n, "failed"]), do: true
  # The inbound hands' three (xenia#11): deliver messages, read the
  # approved replies, mark one sent; the controller holds them to the
  # `reader` role, so a brain token reaches none of the words.
  def adapter_path?("POST", ["v1", "residents", _id, "correspondence"]), do: true
  def adapter_path?("GET", ["v1", "residents", _id, "replies"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "replies", _n, "sent"]), do: true
  # The writing gate (seshat#42): the reader's pieces, the draft it
  # made, the URL once published; held to the `reader` role.
  def adapter_path?("GET", ["v1", "residents", _id, "reader", "pieces"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "reader", "pieces", "drafted"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "reader", "pieces", "published"]), do: true
  def adapter_path?(_method, _path), do: false

  defp refuse(conn) do
    conn
    |> Helpers.error(401, Error.new(:gaia_not_a_principal, :gaia_require_principal_refused))
    |> halt()
  end
end

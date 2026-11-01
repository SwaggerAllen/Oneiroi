defmodule OneiroiWeb.Controllers.Helpers do
  @moduledoc "Shared controller helpers: the error envelope, and the actor a principal acts as."
  import Plug.Conn

  require Logger
  import Phoenix.Controller, only: [json: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.Gaia.Principal

  @doc """
  Renders a component error as the JSON envelope, at `status`.

  The envelope names the error's `site`, the atom written once at the
  line that built it or caught what it wraps (`Oneiroi.Error`), and the
  request id the log files this request under. A reader with a response
  greps the site and lands on the line; with the request id they find
  the log. Neither carries anything the error's own details did not.
  """
  def error(conn, status, %{kind: kind, site: site, meaning: meaning, remedy: remedy}) do
    conn
    |> put_status(status)
    |> json(%{
      error: %{
        kind: Atom.to_string(kind),
        site: Atom.to_string(site),
        meaning: meaning,
        remedy: remedy,
        request_id: request_id()
      }
    })
  end

  @doc """
  Renders a problem with the request itself, found here at the edge
  before any component saw it: a missing field, a malformed value.
  `site` is this line's atom, `web_`-prefixed, unique like every other.
  """
  def problem(conn, status, kind, site, meaning) when is_atom(kind) and is_atom(site) do
    conn
    |> put_status(status)
    |> json(%{
      error: %{
        kind: Atom.to_string(kind),
        site: Atom.to_string(site),
        meaning: meaning,
        request_id: request_id()
      }
    })
  end

  defp request_id, do: Keyword.get(Logger.metadata(), :request_id, "unknown")

  @doc "The actor for the request's principal: the account's, or the resident's for an adapter speaking as its brain."
  def actor(%Plug.Conn{assigns: %{principal: %Principal{} = p}}), do: Principal.actor(p)

  def actor(%Plug.Conn{assigns: %{principal: %AdapterPrincipal{resident_id: id}}}),
    do: Actor.new(:resident, id)

  @doc "The adapter principal on the request, if the bearer was an adapter's token."
  def adapter(%Plug.Conn{assigns: %{principal: %AdapterPrincipal{} = a}}), do: a
  def adapter(_conn), do: nil

  @doc "Whether the request's principal is an account that witnesses the resident; an adapter's token never is."
  def witnesses?(%Plug.Conn{assigns: %{principal: %Principal{account_id: account_id}}}, id),
    do: id in Oneiroi.Gaia.witnessed_residents(account_id)

  def witnesses?(_conn, _id), do: false
end

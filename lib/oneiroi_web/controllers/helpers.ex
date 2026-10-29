defmodule OneiroiWeb.Controllers.Helpers do
  @moduledoc "Shared controller helpers: the error envelope, and the actor a principal acts as."
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.Gaia.Principal

  @doc "Renders a registered error kind as the JSON envelope, at `status`."
  def error(conn, status, %{kind: kind, meaning: meaning, remedy: remedy}) do
    conn
    |> put_status(status)
    |> json(%{error: %{kind: Atom.to_string(kind), meaning: meaning, remedy: remedy}})
  end

  @doc "Renders a validation problem the registry does not name."
  def problem(conn, status, kind, meaning) when is_atom(kind) do
    conn |> put_status(status) |> json(%{error: %{kind: Atom.to_string(kind), meaning: meaning}})
  end

  @doc "The actor for the request's principal: the account's, or the resident's for an adapter speaking as its brain."
  def actor(%Plug.Conn{assigns: %{principal: %Principal{} = p}}), do: Principal.actor(p)

  def actor(%Plug.Conn{assigns: %{principal: %AdapterPrincipal{resident_id: id}}}),
    do: Actor.new(:resident, id)

  @doc "The adapter principal on the request, if the bearer was an adapter's token."
  def adapter(%Plug.Conn{assigns: %{principal: %AdapterPrincipal{} = a}}), do: a
  def adapter(_conn), do: nil

  @doc "Whether the request's principal is an account that stewards the resident; an adapter's token never is."
  def stewards?(%Plug.Conn{assigns: %{principal: %Principal{account_id: account_id}}}, id),
    do: id in Oneiroi.Gaia.stewarded_residents(account_id)

  def stewards?(_conn, _id), do: false
end

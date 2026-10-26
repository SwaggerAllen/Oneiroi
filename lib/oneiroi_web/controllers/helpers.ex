defmodule OneiroiWeb.Controllers.Helpers do
  @moduledoc "Shared controller helpers: the error envelope, and the actor a principal acts as."
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Oneiroi.Identity.Principal

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

  @doc "The actor for the request's principal."
  def actor(%Plug.Conn{assigns: %{principal: %Principal{} = p}}), do: Principal.actor(p)
end

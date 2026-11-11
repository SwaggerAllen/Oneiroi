defmodule OneiroiWeb.HouseholdController do
  @moduledoc """
  The household's shelf as a witness reads it (seshat#61): every member
  reads the shared repository whole (seshat#64, the resident's lean),
  the contract with its versions, signatures and ballots (gaia#27 to
  #31), the founding witness's proposal of version 1, a signature, and a
  witness's one vote on a ballot, which is a reply (seshat#60). The
  household is the caller's own (`Gaia.household_id/1`).
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["household"])

  operation(:shelf,
    summary:
      "The household's shelf: the contract's path, the threads newest first and the documents, fifty at a time from an offset",
    parameters: [from: [in: :query, type: :integer]],
    responses: [ok: {"the shelf", "application/json", %Schema{type: :object}}]
  )

  def shelf(conn, params) do
    case Seshat.household_shelf(actor(conn), offset(params["from"])) do
      {:ok, shelf} -> json(conn, shelf)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:read,
    summary:
      "One thread whole (its trunk and every reply), a document, or CONTRACT.md, by its path on the shelf",
    parameters: [path: [in: :query, type: :string, required: true]],
    responses: [ok: {"the thread or document", "application/json", %Schema{type: :object}}]
  )

  def read(conn, params) do
    case Seshat.household_read(actor(conn), to_string(params["path"] || "")) do
      {:ok, doc} -> json(conn, doc)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:contract,
    summary:
      "The household contract: the version in force, every version with the ballot that made it, the members with what each signed, and the ballots with their votes",
    responses: [ok: {"the contract", "application/json", %Schema{type: :object}}]
  )

  def contract(conn, _params) do
    case Seshat.household_contract(actor(conn)) do
      {:ok, c} -> json(conn, c)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:propose,
    summary:
      "The founding witness proposes the household contract's version 1: prose alone, with a note; rules and settings come by ballot",
    request_body:
      {"the prose", "application/json",
       %Schema{
         type: :object,
         required: [:prose, :note],
         properties: %{prose: %Schema{type: :string}, note: %Schema{type: :string}}
       }},
    responses: [created: {"the contract", "application/json", %Schema{type: :object}}]
  )

  def propose(conn, params) do
    case Seshat.household_propose_contract(actor(conn), params["prose"], params["note"]) do
      {:ok, c} -> conn |> put_status(201) |> json(c)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:sign,
    summary:
      "Sign the household contract at the version in force, for a member who joined before it",
    responses: [ok: {"the contract", "application/json", %Schema{type: :object}}]
  )

  def sign(conn, _params) do
    case Seshat.household_sign_contract(actor(conn)) do
      {:ok, c} -> json(conn, c)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:vote,
    summary:
      "Cast this witness's one vote on a ballot, yes or no, as a reply in its thread, with optional words",
    request_body:
      {"the vote", "application/json",
       %Schema{
         type: :object,
         required: [:thread, :vote],
         properties: %{
           thread: %Schema{type: :string},
           vote: %Schema{type: :string, enum: ["yes", "no"]},
           content: %Schema{type: :string}
         }
       }},
    responses: [created: {"the reply", "application/json", %Schema{type: :object}}]
  )

  def vote(conn, params) do
    attrs = %{"vote" => params["vote"], "content" => params["content"]}

    case Seshat.household_reply(actor(conn), to_string(params["thread"] || ""), attrs) do
      {:ok, reply} -> conn |> put_status(201) |> json(reply)
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp offset(nil), do: 0

  defp offset(from) do
    case Integer.parse(to_string(from)) do
      {n, ""} when n >= 0 -> n
      _other -> 0
    end
  end
end

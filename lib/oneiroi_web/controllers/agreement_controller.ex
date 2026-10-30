defmodule OneiroiWeb.AgreementController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Gaia
  alias OpenApiSpex.Schema

  tags(["agreement"])

  operation(:show,
    summary:
      "The agreement: the contract in force and the open proposal with every version, who looks after the resident, the export wall, an open custody proposal",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the agreement", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}) do
    with :ok <- witness_or_proposed(conn, id), {:ok, r} <- AgathosDaimon.fetch(id) do
      contract = AgathosDaimon.contract(id)

      json(conn, %{
        contract: contract,
        versions: AgathosDaimon.contracts(id),
        custody: r.custody,
        export_wall: r.export_wall,
        custody_proposed_to: r.custody_proposed_to && Gaia.account_email(r.custody_proposed_to),
        custody_proposed_at: r.custody_proposed_at
      })
    else
      :error -> error(conn, 404, ResidentError.new(:agathos_daimon_not_witnessed))
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:propose,
    summary: "Propose a contract version: the terms, the prose, a note",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the proposal", "application/json",
       %Schema{
         type: :object,
         required: [:note],
         properties: %{
           terms: %Schema{type: :object},
           prose: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [ok: {"the version", "application/json", %Schema{type: :object}}]
  )

  def propose(conn, %{"id" => id} = params) do
    with :ok <- witnessed(conn, id),
         {:ok, version} <-
           AgathosDaimon.propose_contract(
             id,
             params["terms"] || %{},
             params["prose"] || "",
             params["note"],
             actor(conn)
           ) do
      json(conn, %{version: version})
    else
      other -> respond(conn, other)
    end
  end

  operation(:decide,
    summary: "Agree to or decline the open version, with a note",
    parameters: [id: [in: :path, type: :string], version: [in: :path, type: :integer]],
    request_body:
      {"the decision", "application/json",
       %Schema{
         type: :object,
         required: [:decision, :note],
         properties: %{
           decision: %Schema{type: :string, enum: ~w(agree decline)},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "decided"]
  )

  def decide(conn, %{"id" => id, "version" => version} = params) do
    with :ok <- witnessed(conn, id), {v, ""} <- Integer.parse(version) do
      case params["decision"] do
        "agree" ->
          respond(conn, AgathosDaimon.agree_contract(id, v, params["note"], actor(conn)))

        "decline" ->
          respond(conn, AgathosDaimon.decline_contract(id, v, params["note"], actor(conn)))

        _other ->
          problem(conn, 422, :decision_invalid, "agree or decline")
      end
    else
      other -> respond(conn, other)
    end
  end

  operation(:set_wall,
    summary:
      "Set the export wall, locked or revealed, with a note; refused while a transfer is open",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the wall", "application/json",
       %Schema{
         type: :object,
         required: [:wall, :note],
         properties: %{
           wall: %Schema{type: :string, enum: ~w(locked revealed)},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "set"]
  )

  def set_wall(conn, %{"id" => id} = params) do
    wall =
      case params["wall"] do
        "locked" -> :locked
        "revealed" -> :revealed
        _other -> :invalid
      end

    with :ok <- witnessed(conn, id),
         do: respond(conn, AgathosDaimon.set_export_wall(id, wall, params["note"], actor(conn)))
  end

  operation(:propose_custody,
    summary: "Propose a transfer of custody to an account by email, with a note",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the proposal", "application/json",
       %Schema{
         type: :object,
         required: [:email, :note],
         properties: %{email: %Schema{type: :string}, note: %Schema{type: :string}}
       }},
    responses: [no_content: "proposed"]
  )

  def propose_custody(conn, %{"id" => id} = params) do
    with :ok <- witnessed(conn, id) do
      case Gaia.account_id_for(to_string(params["email"] || "")) do
        nil -> error(conn, 422, ResidentError.new(:agathos_daimon_custodian_invalid))
        to -> respond(conn, AgathosDaimon.propose_custody(id, to, params["note"], actor(conn)))
      end
    end
  end

  operation(:decide_custody,
    summary:
      "The proposed account accepts or declines the transfer; the witness withdraws it; each with a note",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the decision", "application/json",
       %Schema{
         type: :object,
         required: [:decision, :note],
         properties: %{
           decision: %Schema{type: :string, enum: ~w(accept decline withdraw)},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "decided"]
  )

  def decide_custody(conn, %{"id" => id} = params) do
    case witness_or_proposed(conn, id) do
      :ok -> decide_custody(conn, id, params["decision"], params["note"])
      other -> respond(conn, other)
    end
  end

  defp decide_custody(conn, id, "accept", note),
    do: respond(conn, AgathosDaimon.accept_custody(id, note, actor(conn)))

  defp decide_custody(conn, id, "decline", note),
    do: respond(conn, AgathosDaimon.decline_custody(id, note, actor(conn)))

  defp decide_custody(conn, id, "withdraw", note),
    do: respond(conn, AgathosDaimon.withdraw_custody(id, note, actor(conn)))

  defp decide_custody(conn, _id, _other, _note),
    do: problem(conn, 422, :decision_invalid, "accept, decline or withdraw")

  operation(:proposals,
    summary: "The residents whose custody is proposed to this account",
    responses: [ok: {"proposals", "application/json", %Schema{type: :array}}]
  )

  def proposals(%{assigns: %{principal: p}} = conn, _params) do
    rows = AgathosDaimon.custody_proposals_for(p.account_id)

    json(
      conn,
      Enum.map(
        rows,
        &%{id: &1.id, slug: &1.slug, name: &1.name, proposed_at: &1.custody_proposed_at}
      )
    )
  end

  # ---- who ----

  defp witnessed(conn, id) do
    if witnesses?(conn, id),
      do: :ok,
      else: {:error, ResidentError.new(:agathos_daimon_not_witnessed)}
  end

  # The agreement is read, and a transfer decided, by the witness or
  # the account the transfer is proposed to.
  defp witness_or_proposed(%{assigns: %{principal: p}} = conn, id) do
    cond do
      witnesses?(conn, id) -> :ok
      proposed_to?(id, Map.get(p, :account_id)) -> :ok
      true -> {:error, ResidentError.new(:agathos_daimon_not_witnessed)}
    end
  end

  defp proposed_to?(_id, nil), do: false

  defp proposed_to?(id, account_id),
    do: Enum.any?(AgathosDaimon.custody_proposals_for(account_id), &(&1.id == id))

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: :agathos_daimon_not_witnessed} = e}),
    do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
  defp respond(conn, {:error, reason}), do: problem(conn, 422, :refused, inspect(reason))
  defp respond(conn, _other), do: problem(conn, 422, :refused, "not understood")
end

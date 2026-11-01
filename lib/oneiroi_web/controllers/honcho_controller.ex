defmodule OneiroiWeb.HonchoController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Proteus
  alias OpenApiSpex.Schema

  tags(["honcho"])

  plug(:witnessed)

  operation(:show,
    summary:
      "The bridge: the workspace and peers, the card as last set, the last card audit, the latest syncs",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the bridge", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}) do
    case Proteus.bridge(id) do
      nil ->
        json(conn, %{provisioned: false, syncs: []})

      b ->
        json(conn, %{
          provisioned: true,
          workspace: b.workspace,
          peers: b.peers,
          provisioned_at: b.provisioned_at,
          card: %{
            hash: b.card_hash,
            lines: b.card_lines,
            source: b.card_source,
            set_at: b.card_set_at
          },
          last_audit: %{
            at: b.last_audit_at,
            moved: b.last_audit_moved,
            reason: b.last_audit_reason
          },
          synced: b.syncs,
          last_sync_at: b.last_sync_at,
          syncs: id |> Proteus.syncs(20) |> Enum.map(&sync/1)
        })
    end
  end

  operation(:audit_card,
    summary: "Run the card audit by hand: the card is pinned back from git if a dream moved it",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the outcome", "application/json", %Schema{type: :object}}]
  )

  def audit_card(conn, %{"id" => id}) do
    case Proteus.audit_card(id, actor(conn)) do
      {:ok, outcome} ->
        json(conn, outcome)

      {:error, %{kind: kind} = e} when kind == :proteus_not_provisioned ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 502, e)
    end
  end

  defp sync(s),
    do: %{
      turn_ref: s.turn_ref,
      session_key: s.session_key,
      messages: s.messages,
      outcome: s.outcome,
      reason: s.reason,
      at: s.at
    }

  # Every route here is a resident's, read or written by its witness.
  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(:agathos_daimon_not_witnessed, :agathos_daimon_honcho_witnessed_plug)
        )
        |> halt()
  end
end

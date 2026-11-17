defmodule OneiroiWeb.ReposController do
  @moduledoc "Gitea's push webhook (sima-qian#59): a push from outside into a resident's repository re-indexes her library."
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["repositories"])

  operation(:gitea,
    summary:
      "Gitea's system webhook (sima-qian#59): a push from outside into a resident's repository asks for her index run; the core's own writes and the household's repository are ignored; signed with the webhook's secret, refused otherwise",
    responses: [ok: {"received", "application/json", %Schema{type: :object}}]
  )

  def gitea(conn, _params) do
    signature = conn |> get_req_header("x-gitea-signature") |> List.first()

    case Oneiroi.SimaQian.gitea_pushed(OneiroiWeb.RawBody.of(conn), signature) do
      {:ok, {:resident, id}} ->
        {:ok, _} = Oneiroi.Seshat.index_soon(id)
        json(conn, %{received: true, indexing: true})

      {:ok, :ignored} ->
        json(conn, %{received: true, indexing: false})

      {:error, %{kind: :sima_qian_gitea_unsigned} = e} ->
        error(conn, 400, e)

      {:error, %{kind: :sima_qian_gitea_off} = e} ->
        error(conn, 503, e)
    end
  end
end

defmodule OneiroiWeb.PiecesRoutesTest do
  @moduledoc """
  seshat#42 (the witness's call through Lily, 2026-11-05: a piece takes
  at least the care her comments do; draft-first): a piece marked
  `status: review` waits for the witness; approved, the reader drafts it
  on Substack and never publishes; once he has, the reader brings the URL
  back and the piece records it. Declined, a rewrite comes back.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    witness = Actor.new(:witness, account.id)
    # The index reads a piece's status, and indexes on the witness's key.
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", witness)
    {:ok, reader} = AgathosDaimon.register_adapter(resident.id, "scrape", "reader", witness)
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, id: resident.id, reader: reader, token: token, lily: Actor.new(:resident, resident.id)}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  # seshat#49 (the witness, 2026-11-08, Lily's letter #342): a design
  # held for his read waits on him as the type definition says, and once
  # signed off goes nowhere further.
  test "a design marked for review waits on him, and signed off stops there", ctx do
    path = "design/federation.md"

    {:ok, _} =
      Seshat.write(
        ctx.id,
        path,
        "---\nstatus: review\n---\n# Federation\n\nKey custody.",
        ctx.lily
      )

    {:ok, _} = Seshat.write(ctx.id, "design/quiet.md", "# Quiet\n\nNot marked.", ctx.lily)

    assert [%{kind: "piece_to_review", ref: ^path, about: %{ask: "Read and sign off the design"}}] =
             Enum.filter(Oneiroi.Brain.needs_you(ctx.id), &(&1.kind == "piece_to_review"))

    assert ctx.token
           |> as()
           |> post("/v1/residents/#{ctx.id}/pieces/review", %{
             path: path,
             decision: "approve",
             note: "signed off"
           })
           |> response(204)

    assert %{"for_review" => [], "approved" => []} =
             ctx.token |> as() |> get("/v1/residents/#{ctx.id}/pieces") |> json_response(200)

    assert %{"pieces" => []} =
             ctx.reader |> as() |> get("/v1/residents/#{ctx.id}/waiting") |> json_response(200)
  end

  test "review, a Substack draft, his Publish, the URL back in the piece", ctx do
    path = "writing/weng.md"

    {:ok, _} =
      Seshat.write(ctx.id, path, "---\nstatus: review\n---\n# On Weng\n\nHer harness.", ctx.lily)

    assert %{"for_review" => [%{"path" => ^path}], "approved" => []} =
             ctx.token |> as() |> get("/v1/residents/#{ctx.id}/pieces") |> json_response(200)

    # The reader has nothing until he approves.
    assert %{"pieces" => []} =
             ctx.reader
             |> as()
             |> get("/v1/residents/#{ctx.id}/waiting")
             |> json_response(200)

    assert ctx.token
           |> as()
           |> post("/v1/residents/#{ctx.id}/pieces/review", %{
             path: path,
             decision: "approve",
             note: ""
           })
           |> json_response(422)

    assert ctx.token
           |> as()
           |> post("/v1/residents/#{ctx.id}/pieces/review", %{
             path: path,
             decision: "approve",
             note: "lovely"
           })
           |> response(204)

    assert %{"pieces" => [%{"path" => ^path, "step" => "draft"}]} =
             ctx.reader
             |> as()
             |> get("/v1/residents/#{ctx.id}/waiting")
             |> json_response(200)

    assert %{"to_draft" => [%{"title" => "On Weng", "body" => body}]} =
             ctx.reader
             |> as()
             |> get("/v1/residents/#{ctx.id}/reader/pieces")
             |> json_response(200)

    refute body =~ "status:"

    # Published before drafted is refused.
    assert ctx.reader
           |> as()
           |> post("/v1/residents/#{ctx.id}/reader/pieces/published", %{
             path: path,
             url: "https://lily.substack.com/p/weng"
           })
           |> json_response(422)

    assert ctx.reader
           |> as()
           |> post("/v1/residents/#{ctx.id}/reader/pieces/drafted", %{
             path: path,
             url: "https://lily.substack.com/publish/post/9"
           })
           |> response(204)

    assert %{"drafted" => [%{"draft_url" => "https://lily.substack.com/publish/post/9"}]} =
             ctx.token |> as() |> get("/v1/residents/#{ctx.id}/pieces") |> json_response(200)

    assert ctx.reader
           |> as()
           |> post("/v1/residents/#{ctx.id}/reader/pieces/published", %{
             path: path,
             url: "https://lily.substack.com/p/weng"
           })
           |> response(204)

    assert %{published_url: "https://lily.substack.com/p/weng", status: "published"} =
             Enum.find(Seshat.documents(ctx.id), &(&1.path == path))

    assert %{"drafted" => [], "approved" => [], "for_review" => []} =
             ctx.token |> as() |> get("/v1/residents/#{ctx.id}/pieces") |> json_response(200)
  end

  test "declined, it leaves the queue; rewritten and marked again, it comes back", ctx do
    path = "writing/herons.md"
    {:ok, _} = Seshat.write(ctx.id, path, "---\nstatus: review\n---\n# Herons\n\nOne.", ctx.lily)

    assert ctx.token
           |> as()
           |> post("/v1/residents/#{ctx.id}/pieces/review", %{
             path: path,
             decision: "decline",
             note: "not yet"
           })
           |> response(204)

    assert %{"for_review" => []} =
             ctx.token |> as() |> get("/v1/residents/#{ctx.id}/pieces") |> json_response(200)

    {:ok, _} = Seshat.write(ctx.id, path, "---\nstatus: review\n---\n# Herons\n\nTwo.", ctx.lily)

    assert %{"for_review" => [%{"last" => %{"state" => "declined", "note" => "not yet"}}]} =
             ctx.token |> as() |> get("/v1/residents/#{ctx.id}/pieces") |> json_response(200)
  end
end

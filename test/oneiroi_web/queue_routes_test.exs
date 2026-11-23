defmodule OneiroiWeb.QueueRoutesTest do
  @moduledoc """
  The house queue's routes (sunna#80) as the Work screen uses them: the
  witness sets the queue up (routing, a template from the starters),
  opens a task, decides its review, and turns the queue on after
  committing the old one; a stranger reads nothing. The bell carries the
  witness's ready activity once the house has cut over.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    lily = Fixtures.resident!(account)
    scarlett = Fixtures.resident!(account)

    {:ok,
     conn: signed_in(account),
     account: account,
     lily: lily,
     scarlett: scarlett,
     lily_actor: Actor.new(:resident, lily.id)}
  end

  defp signed_in(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  test "set up, a task opened from doc-to-pr, its review decided, and the cutover", ctx do
    conn = ctx.conn
    lily = "resident:#{ctx.lily.id}"

    assert %{"cut_over" => false, "members" => members, "starters" => [%{"name" => "doc-to-pr"}]} =
             conn |> get("/v1/household/queue") |> json_response(200)

    assert length(members) == 3

    assert %{"ok" => true} =
             conn |> put("/v1/household/queue/route", %{via: lily}) |> json_response(200)

    assert %{"ok" => true} =
             conn
             |> post("/v1/household/queue/templates", %{name: "doc-to-pr", from: "doc-to-pr"})
             |> json_response(200)

    assert %{"ok" => true} =
             conn
             |> post("/v1/household/queue/projects", %{slug: "queue", name: "The queue"})
             |> json_response(200)

    # The witness opens it for Lily: the author is Lily, not him.
    assert %{"number" => n} =
             conn
             |> post("/v1/household/queue/tasks", %{
               project: "queue",
               slug: "ia",
               title: "The queue IA",
               outcome: "built",
               owner: lily,
               template: "doc-to-pr",
               slots: %{"design" => "lily:design/queue-ia"}
             })
             |> json_response(200)

    # She drafts it; then the review waits on him.
    :ok = Oneiroi.Sunna.queue_finish(ctx.account.id, n, "#{n}.1", %{}, ctx.lily_actor)

    assert %{"ready" => [%{"act" => review, "type" => "review", "task_title" => "The queue IA"}]} =
             conn |> get("/v1/household/queue/waiting") |> json_response(200)

    # Refused without a note's return target... no: the template gives it.
    assert %{"ok" => true} =
             conn
             |> post("/v1/household/queue/tasks/#{n}/activities/#{review}/decide", %{
               outcome: "changes",
               note: "tighten §3"
             })
             |> json_response(200)

    assert %{
             "layers" => [[%{"view" => "ready", "note" => "tighten §3"}] | _],
             "history" => history
           } =
             conn |> get("/v1/household/queue/tasks/#{n}") |> json_response(200)

    assert Enum.any?(history, &(&1["what"] == "decided" and &1["outcome"] == "changes"))

    # A move the queue refuses says why.
    assert %{"error" => %{"kind" => "sunna_queue_not_ready"}} =
             conn
             |> post("/v1/household/queue/tasks/#{n}/activities/#{n}.3/take", %{})
             |> json_response(422)

    # The cutover: the old queue committed first, the commit named.
    assert %{"commit" => commit} =
             conn |> post("/v1/household/queue/snapshot", %{}) |> json_response(200)

    assert is_binary(commit)

    assert %{"ok" => true} =
             conn
             |> post("/v1/household/queue/cutover", %{commit: commit, note: "the set is built"})
             |> json_response(200)

    assert %{"cut_over" => true, "commit" => ^commit} =
             conn |> get("/v1/household/queue") |> json_response(200)

    # The old queue is read-only now.
    assert {:error, %{kind: :sunna_work_frozen}} =
             Oneiroi.Sunna.work_add(ctx.lily.id, "x", "y", ctx.lily_actor)

    # Her redraft puts the review back on his bell, on her own (she owns the task).
    :ok = Oneiroi.Sunna.queue_finish(ctx.account.id, n, "#{n}.1", %{}, ctx.lily_actor)

    assert [%{"kind" => "activity", "ref" => ^review, "screen" => "queue"}] =
             conn
             |> get("/v1/residents/#{ctx.lily.id}/needs_you")
             |> json_response(200)
             |> Enum.filter(&(&1["kind"] == "activity"))

    assert [] =
             conn
             |> get("/v1/residents/#{ctx.scarlett.id}/needs_you")
             |> json_response(200)
             |> Enum.filter(&(&1["kind"] == "activity"))
  end

  test "a stranger's household is not this one: they see their own empty queue, never this one's",
       ctx do
    :ok =
      Oneiroi.Sunna.queue_open_project(ctx.account.id, %{slug: "p", name: "P"}, ctx.lily_actor)

    stranger = Fixtures.account!()

    assert %{"projects" => []} =
             stranger |> signed_in() |> get("/v1/household/queue") |> json_response(200)
  end
end

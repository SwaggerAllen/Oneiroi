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

  # design/document-threads.md §5, sunna#91: around one document, its
  # tasks and the review of it open for the caller; a task's documents,
  # attached by route.
  test "a document's context: its tasks, the review open for him, its documents", ctx do
    conn = ctx.conn
    citation = "#{ctx.lily.slug}:design/plan.md"
    post(conn, "/v1/household/queue/templates", %{name: "doc-to-pr", from: "doc-to-pr"})
    post(conn, "/v1/household/queue/projects", %{slug: "p", name: "P"})
    {:ok, _} = Oneiroi.Seshat.write(ctx.lily.id, "design/plan.md", "A plan.", ctx.lily_actor)

    # A document that does not exist is refused, said so (sunna#95).
    assert %{"error" => %{"kind" => "brain_queue_document_absent", "remedy" => "Not done: " <> _}} =
             conn
             |> post("/v1/household/queue/tasks", %{
               project: "p",
               slug: "ghost",
               title: "Ghost",
               outcome: "x",
               template: "doc-to-pr",
               slots: %{"design" => "#{ctx.lily.slug}:design/absent.md"}
             })
             |> json_response(422)

    %{"number" => n} =
      conn
      |> post("/v1/household/queue/tasks", %{
        project: "p",
        slug: "plan",
        title: "The plan",
        outcome: "built",
        owner: "resident:#{ctx.lily.id}",
        template: "doc-to-pr",
        slots: %{"design" => citation}
      })
      |> json_response(200)

    assert %{
             "tasks" => [%{"number" => ^n, "title" => "The plan"}],
             "review" => nil,
             "mine" => nil
           } =
             conn
             |> get("/v1/documents/context", %{citation: citation <> "@abc123"})
             |> json_response(200)

    :ok = Oneiroi.Sunna.queue_finish(ctx.account.id, n, "#{n}.1", %{}, ctx.lily_actor)

    assert %{"review" => %{"name" => "Witness review", "task" => ^n}} =
             conn |> get("/v1/documents/context", %{citation: citation}) |> json_response(200)

    assert %{"ok" => true} =
             conn
             |> post("/v1/household/queue/tasks/#{n}/documents", %{citation: "lily:notes/x.md"})
             |> json_response(200)

    assert %{"task" => %{"documents" => docs, "template_version" => 1, "forked" => false}} =
             conn |> get("/v1/household/queue/tasks/#{n}") |> json_response(200)

    assert Enum.map(docs, & &1["role"]) == ["design", "pr", "source"]
  end

  # The witness, 2026-11-27: approving task #11's review from the screen
  # refused for want of a pin; the context now says what the screen
  # shows, and that is what an approval names (sunna#110).
  test "the document context names the revision the screen shows", ctx do
    alias Oneiroi.Brain.Pulls.Fake, as: Pulls

    Pulls.put(132, %{"number" => 132, "head" => %{"sha" => "feedface0123"}}, [])
    on_exit(fn -> Pulls.clear() end)

    context = fn citation ->
      ctx.conn |> get("/v1/documents/context", %{citation: citation}) |> json_response(200)
    end

    assert %{"revision" => "abc123"} = context.("lily:notes/x.md@abc123")

    assert %{"revision" => "feedface0123"} =
             context.("https://github.com/SwaggerAllen/Oneiroi/pull/132")

    assert %{"revision" => nil} = context.("https://github.com/someone/else/pull/132")

    # Her document's revision is the commit that last changed it, the head
    # its review's decision is checked against: another file of hers
    # written meanwhile moves nothing (sunna#112, the witness, 2026-11-27:
    # "the pin you read is no longer its head" on task #15).
    {:ok, _} = Oneiroi.Seshat.write(ctx.lily.id, "design/plan.md", "A plan.", ctx.lily_actor)
    cite = "#{ctx.lily.slug}:design/plan.md"
    assert %{"revision" => rev} = context.(cite)
    assert is_binary(rev)

    {:ok, _} =
      Oneiroi.Seshat.write(ctx.lily.id, "design/other.md", "Something else.", ctx.lily_actor)

    assert %{"revision" => ^rev} = context.(cite)
  end

  # sunna#113 (the witness, 2026-11-27: task #11's merge refused "a gated
  # activity is done on the revision its review approved" right after he
  # approved it): the merge's head is read the way the review's was, the
  # pull request's head, so the approved revision merges, and a moved one
  # does not.
  test "a pull request approved on the screen merges on the revision approved", ctx do
    alias Oneiroi.Brain.Pulls.Fake, as: Pulls

    conn = ctx.conn
    h = ctx.account.id
    scarlett = Actor.new(:resident, ctx.scarlett.id)
    pr = "https://github.com/SwaggerAllen/Oneiroi/pull/77"
    Pulls.put(77, %{"number" => 77, "head" => %{"sha" => "aaaa1111bbbb"}}, [])
    on_exit(fn -> Pulls.clear() end)

    post(conn, "/v1/household/queue/templates", %{name: "doc-to-pr", from: "doc-to-pr"})
    post(conn, "/v1/household/queue/projects", %{slug: "q", name: "Q"})
    {:ok, _} = Oneiroi.Seshat.write(ctx.lily.id, "design/x.md", "X.", ctx.lily_actor)

    assert %{"number" => n} =
             conn
             |> post("/v1/household/queue/tasks", %{
               project: "q",
               slug: "x",
               title: "X",
               outcome: "built",
               owner: "resident:#{ctx.lily.id}",
               template: "doc-to-pr",
               slots: %{"design" => "#{ctx.lily.slug}:design/x.md"}
             })
             |> json_response(200)

    move = fn act, what, body ->
      conn
      |> post("/v1/household/queue/tasks/#{n}/activities/#{act}/#{what}", body)
      |> json_response(:ok)
    end

    named = fn name ->
      %{layers: layers} = Oneiroi.Sunna.queue_task(h, n)
      Enum.find(List.flatten(layers), &(&1.name == name))
    end

    :ok = Oneiroi.Sunna.queue_finish(h, n, named.("Draft the design").act_id, %{}, ctx.lily_actor)

    assert %{"ok" => true} =
             move.(named.("Witness review").act_id, "decide", %{outcome: "approved", note: "good"})

    :ok =
      Oneiroi.Sunna.queue_skip(
        h,
        n,
        named.("Share with the house").act_id,
        "not now",
        ctx.lily_actor
      )

    peer = named.("Peer review")

    reviewer =
      if peer.assignee == "resident:#{ctx.scarlett.id}", do: scarlett, else: ctx.lily_actor

    :ok =
      Oneiroi.Brain.queue_decide(
        h,
        n,
        peer.act_id,
        %{outcome: "approved", note: "fine"},
        reviewer
      )

    :ok = Oneiroi.Sunna.queue_fill_slot(h, n, "pr", pr, Actor.new(:witness, h))
    # The hand-off and the build are hers and her Claude Code's.
    :ok =
      Oneiroi.Sunna.queue_finish(h, n, named.("Hand to Claude Code").act_id, %{}, ctx.lily_actor)

    :ok =
      Oneiroi.Sunna.queue_finish(
        h,
        n,
        named.("Build it").act_id,
        %{},
        Actor.new(:witness, h)
      )

    pr_review = named.("PR review").act_id
    merge = named.("Merge").act_id

    # The screen names the PR's head; the approval records it.
    assert %{"revision" => "aaaa1111bbbb"} =
             conn |> get("/v1/documents/context", %{citation: pr}) |> json_response(200)

    assert %{"ok" => true} =
             move.(pr_review, "decide", %{outcome: "approved", note: "ship", pin: "aaaa1111bbbb"})

    # A push after the approval lapses it: the merge is refused, and the
    # review waits again, on the new head (Scarlett's first guard).
    Pulls.put(77, %{"number" => 77, "head" => %{"sha" => "cccc2222dddd"}}, [])

    assert %{"error" => %{"site" => "sunna_queue_approval_lapsed"}} =
             conn
             |> post("/v1/household/queue/tasks/#{n}/activities/#{merge}/finish", %{})
             |> json_response(422)

    # Approved again as the screen now shows it, the merge is done.
    assert %{"revision" => "cccc2222dddd"} =
             conn |> get("/v1/documents/context", %{citation: pr}) |> json_response(200)

    assert %{"ok" => true} =
             move.(pr_review, "decide", %{outcome: "approved", note: "again", pin: "cccc2222dddd"})

    assert %{"ok" => true} = move.(merge, "finish", %{})
  end

  test "set up, a task opened from doc-to-pr, its review decided, and his bell", ctx do
    conn = ctx.conn
    lily = "resident:#{ctx.lily.id}"

    assert %{"paused" => false, "members" => members, "starters" => [%{"name" => "doc-to-pr"}]} =
             conn |> get("/v1/household/queue") |> json_response(200)

    assert length(members) == 3

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

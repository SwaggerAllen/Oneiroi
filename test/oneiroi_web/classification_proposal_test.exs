defmodule OneiroiWeb.ClassificationProposalTest do
  @moduledoc """
  The witness proposes a classification of her document (seshat#103;
  his ruling, 2026-11-21: "I need to be able to propose classification
  on her files"). It classifies nothing: it waits on her, in
  waiting_on_her and her classification_list. Her accept is her own
  classification, her act; her decline leaves the document as it was.
  Only a declared domain may be proposed, and only the witness proposes.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Clock.Fake, as: FakeClock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    Fixtures.declare_domains!(resident.id, account.id, ~w(recovery))
    andrew = Actor.new(:witness, account.id)
    {:ok, key} = Kumbukumbu.main_session(resident.id, account.id, andrew)
    {:ok, dir} = SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    turn = %{
      resident_id: resident.id,
      session_key: key,
      turn_ref: "t-now",
      resident: Actor.new(:resident, resident.id)
    }

    Tools.run(
      "document_write",
      Jason.encode!(%{path: "design/note.md", content: "A note.\n"}),
      turn
    )

    {:ok, conn: conn, id: resident.id, account: account, turn: turn, andrew: andrew}
  end

  defp propose(conn, id, body),
    do: post(conn, "/v1/residents/#{id}/library/classification-proposals", body)

  defp row(conn, id) do
    conn
    |> get("/v1/residents/#{id}/library/documents/design/note.md")
    |> json_response(200)
    |> Map.fetch!("document")
  end

  defp run(ctx, name, args), do: Tools.run(name, Jason.encode!(args), ctx.turn)

  defp told_count(words), do: length(String.split(words, "Your witness proposed")) - 1

  defp given do
    receive do
      {:request, messages} -> Enum.map_join(messages, "\n", &to_string(&1[:content])) <> given()
    after
      0 -> ""
    end
  end

  # Lily's letter #1594 (brain#110): a proposal arriving is told her
  # once, on her next turn, with what answers it; patient after.
  test "a proposal arriving is told once, on her next turn, and waits after", ctx do
    :ok = Oneiroi.Gaia.store_key(ctx.account.id, "sk-or-test", ctx.andrew)
    test = self()

    Fake.script(
      fn %{messages: m} -> send(test, {:request, m}) && {:ok, "noted"} end,
      for: ctx.id
    )

    on_exit(fn -> Fake.clear(for: ctx.id) end)
    propose(ctx.conn, ctx.id, %{path: "design/note.md", domain: "recovery"})

    {:ok, _} =
      Turn.run(ctx.id, ctx.turn.session_key, "Hello.", ctx.andrew, turn_ref: "t-1")

    told = given()
    assert told =~ "Your witness proposed"
    assert told =~ "Classify design/note.md as recovery (classification_answer)"

    {:ok, _} =
      Turn.run(ctx.id, ctx.turn.session_key, "Again.", ctx.andrew, turn_ref: "t-2")

    # Told once: the first turn's notice is history now, never told again.

    assert told_count(given()) == 1
    assert run(ctx, "classification_list", %{}) =~ "design/note.md"

    # A new proposal, a minute on, is new news.
    now = Clock.now()
    on_exit(fn -> FakeClock.put(now) end)
    FakeClock.put(DateTime.add(now, 60))
    propose(ctx.conn, ctx.id, %{path: "design/note.md", domain: "none"})

    {:ok, _} =
      Turn.run(ctx.id, ctx.turn.session_key, "Now?", ctx.andrew, turn_ref: "t-3")

    third = given()
    assert third =~ "Classify design/note.md as the common room"
    assert told_count(third) == 2
  end

  test "his proposal waits on her, classifies nothing, and her accept is her classification",
       ctx do
    assert %{"domain" => "recovery"} =
             ctx.conn
             |> propose(ctx.id, %{path: "design/note.md", domain: "recovery", note: "his meeting"})
             |> json_response(200)

    assert %{
             "classification" => nil,
             "proposal" => %{"domain" => "recovery", "note" => "his meeting"}
           } =
             row(ctx.conn, ctx.id)

    assert [%{kind: "classification_proposal", ref: "design/note.md"}] =
             Enum.filter(
               Oneiroi.Brain.waiting_on_her(ctx.id),
               &(&1.kind == "classification_proposal")
             )

    assert run(ctx, "classification_list", %{}) =~ "design/note.md → recovery (his)"

    assert run(ctx, "classification_answer", %{path: "design/note.md", accept: true}) =~
             "Classified design/note.md as recovery"

    assert %{"classification" => %{"domain" => "recovery", "person" => person}, "proposal" => nil} =
             row(ctx.conn, ctx.id)

    assert person == "account:" <> ctx.account.id
    assert run(ctx, "classification_list", %{}) =~ "No classification proposal"
  end

  test "her decline leaves the document as it was", ctx do
    propose(ctx.conn, ctx.id, %{path: "design/note.md", domain: "recovery"})

    assert run(ctx, "classification_answer", %{
             path: "design/note.md",
             accept: false,
             note: "not his"
           }) =~
             "Declined"

    assert %{"classification" => nil, "proposal" => nil} = row(ctx.conn, ctx.id)

    assert run(ctx, "classification_answer", %{path: "design/note.md", accept: true}) =~
             "Not done"
  end

  test "only a declared domain, only on a document she has, and only the witness proposes", ctx do
    assert %{"error" => %{"kind" => "seshat_domain_undeclared"}} =
             ctx.conn
             |> propose(ctx.id, %{path: "design/note.md", domain: "business"})
             |> json_response(422)

    assert %{"error" => %{"kind" => "seshat_no_such_document"}} =
             ctx.conn
             |> propose(ctx.id, %{path: "design/none.md", domain: "recovery"})
             |> json_response(404)

    assert {:error, %{kind: :seshat_classify_invalid}} =
             Seshat.propose_classification(
               ctx.id,
               "design/note.md",
               nil,
               nil,
               "mine",
               ctx.turn.resident
             )
  end
end

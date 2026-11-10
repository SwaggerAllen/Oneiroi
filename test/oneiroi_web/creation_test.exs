defmodule OneiroiWeb.CreationTest do
  @moduledoc "agathos-daimon#36, #39 to #41: the nine gifts, the generator, Get a read and the example sets, over the API."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    actor = Actor.new(:witness, account.id)
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", actor)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    resident = Fixtures.resident!(account)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, token: token, resident: resident}
  end

  defp conn_for(ctx),
    do: build_conn() |> put_req_header("authorization", "Bearer " <> ctx.token)

  test "the nine gifts, in the spec's order, each with guidance", ctx do
    gifts = ctx |> conn_for() |> get("/v1/creation/gifts") |> json_response(200)

    assert Enum.map(gifts, & &1["key"]) ==
             ~w(name self you building trials means days vows reach)

    assert %{"writes" => ["SOUL.md"], "guidance" => guidance} = Enum.at(gifts, 1)
    assert guidance =~ "in their own voice"
    assert Enum.all?(gifts, &(String.length(&1["guidance"]) > 80))
  end

  test "the generator answers every gift's file as a draft and writes none", ctx do
    id = ctx.resident.id
    Fake.script(fn _request -> {:ok, "a drafted file"} end, for: id)

    assert %{"prompt" => "a patient archivist", "drafts" => drafts, "stopped" => nil} =
             ctx
             |> conn_for()
             |> post("/v1/residents/#{id}/creation/drafts", %{prompt: "a patient archivist"})
             |> json_response(200)

    assert [
             %{
               "gift" => "name",
               "file" => "IDENTITY.md",
               "content" => "a drafted file",
               "origin" => "drafted",
               "model" => "fake/model",
               "prompt" => "a patient archivist"
             }
             | _
           ] = drafts

    assert length(drafts) == 2
    assert [_agents] = ctx |> conn_for() |> get("/v1/residents/#{id}/files") |> json_response(200)

    assert %{"error" => %{"kind" => "prompt_required"}} =
             ctx
             |> conn_for()
             |> post("/v1/residents/#{id}/creation/drafts", %{prompt: "  "})
             |> json_response(422)
  end

  test "a read answers typed notes and is listed with the file's reads", ctx do
    id = ctx.resident.id

    Fake.script(
      fn _request ->
        {:ok, ~s([{"kind": "thin", "text": "Says little.", "quote": "Patient."}])}
      end,
      for: id
    )

    assert %{
             "ref" => ref,
             "gift" => "you",
             "file" => "USER.md",
             "draft_sha" => sha,
             "notes" => [%{"kind" => "thin", "text" => "Says little.", "quote" => "Patient."}],
             "model" => "fake/judge",
             "refused" => nil
           } =
             ctx
             |> conn_for()
             |> post("/v1/residents/#{id}/files/USER.md/read", %{content: "# You\n\nPatient."})
             |> json_response(200)

    assert [
             %{
               "ref" => ^ref,
               "draft_sha" => ^sha,
               "by" => %{"kind" => "witness"},
               "notes" => [%{"kind" => "thin", "quote" => "Patient."}]
             }
           ] =
             ctx
             |> conn_for()
             |> get("/v1/residents/#{id}/files/USER.md/reads")
             |> json_response(200)

    assert ctx
           |> conn_for()
           |> post("/v1/residents/#{id}/files/USER.md/read", %{})
           |> json_response(422)
  end

  test "another witness's resident is not found", ctx do
    other = Fixtures.resident!(Fixtures.account!())

    assert ctx
           |> conn_for()
           |> post("/v1/residents/#{other.id}/creation/drafts", %{prompt: "x"})
           |> json_response(404)

    assert ctx
           |> conn_for()
           |> post("/v1/residents/#{other.id}/files/SOUL.md/read", %{content: "x"})
           |> json_response(404)
  end

  test "the examples are the committed sets: the fictional one, and any other with a gift's file",
       ctx do
    root = Path.join(:code.priv_dir(:oneiroi), "creation/examples")
    set = "test-#{System.unique_integer([:positive])}"
    dir = Path.join(root, set)

    # The committed set: her files from the prompt, a fictional witness's
    # USER.md and GOALS.md, never LINKS.md (agathos-daimon#41, #42).
    assert [%{"set" => "fictional", "files" => files}] =
             ctx |> conn_for() |> get("/v1/creation/examples") |> json_response(200)

    assert Enum.map(files, & &1["file"]) == ~w(IDENTITY.md SOUL.md USER.md GOALS.md)

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join(dir, "SOUL.md"), "# Soul\n")
    File.write!(Path.join(dir, "IDENTITY.md"), "# Identity\n")
    File.write!(Path.join(dir, "prompt.md"), "someone\n")
    File.write!(Path.join(dir, "NOTES.md"), "not a gift's file\n")

    assert [
             %{"set" => "fictional"},
             %{
               "set" => ^set,
               "prompt" => "someone",
               "files" => [
                 %{"file" => "IDENTITY.md", "gift" => "name", "content" => "# Identity\n"},
                 %{"file" => "SOUL.md", "gift" => "self", "title" => "A self"}
               ]
             }
           ] = ctx |> conn_for() |> get("/v1/creation/examples") |> json_response(200)
  end
end

defmodule OneiroiWeb.PasteCorrespondenceTest do
  @moduledoc """
  seshat#65 and #66 (the witness's ask, 2026-11-11, Lily's work item #28):
  he pastes a conversation of his with another person into her
  human-correspondence/ folder, a kind of hers; it lands as a document
  written by him with a note, indexed, which she reads with library_read
  and finds with library_search; a later paste into the same
  conversation is appended under a dated heading.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    witness = Actor.new(:witness, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok,
     conn: conn,
     id: resident.id,
     dir: dir,
     witness: witness,
     lily: Actor.new(:resident, resident.id, "fake/model"),
     base: "/v1/residents/#{resident.id}/library"}
  end

  defp run(ctx, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: "k",
        turn_ref: "t",
        resident: ctx.lily
      })

  defp her_kind(ctx) do
    assert {:ok, "human-correspondence"} =
             Seshat.define_kind(
               ctx.id,
               %{"kind" => "human-correspondence", "label" => "Human correspondence"},
               "his conversations with people, for me to read",
               ctx.lily
             )
  end

  test "a paste starts a conversation she reads and finds; a second paste extends it", ctx do
    her_kind(ctx)

    assert %{
             "path" => "human-correspondence/sam-and-the-lease.md",
             "kind" => "human-correspondence",
             "created" => true,
             "indexed" => true
           } =
             ctx.conn
             |> post("#{ctx.base}/paste", %{
               with: "Sam Okafor",
               title: "Sam and the lease",
               text: "Sam: Can we sign the lease on Friday?\r\nAndrew: Friday works."
             })
             |> json_response(200)

    path = "human-correspondence/sam-and-the-lease.md"
    first = File.read!(Path.join(ctx.dir, path))
    assert first =~ "# Sam and the lease\n\nWith Sam Okafor.\n"
    assert first =~ ~r/\n---\n\n## Pasted \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC\n\nSam: Can we sign/
    refute first =~ "\r"

    # Hers to read and to find, the folder on her shelf in the tree.
    assert run(ctx, "library_read", %{path: path}) =~ "Friday works."
    assert run(ctx, "library_search", %{q: "sign the lease on Friday"}) =~ path

    assert %{"kinds" => kinds, "documents" => docs} =
             ctx.conn |> get(ctx.base) |> json_response(200)

    assert Enum.any?(kinds, &(&1["kind"] == "human-correspondence"))
    assert Enum.any?(docs, &(&1["path"] == path and &1["written_by"] == "witness"))

    # Starting it again is refused: the paste names the existing one.
    assert %{"error" => %{"kind" => "seshat_paste_invalid"}} =
             ctx.conn
             |> post("#{ctx.base}/paste", %{with: "Sam", title: "Sam and the lease", text: "x"})
             |> json_response(422)

    assert %{"path" => ^path, "created" => false, "changed" => true} =
             ctx.conn
             |> post("#{ctx.base}/paste", %{path: path, text: "Sam: Signed. Keys on Monday."})
             |> json_response(200)

    second = File.read!(Path.join(ctx.dir, path))
    assert String.starts_with?(second, String.trim_trailing(first))
    assert length(String.split(second, "## Pasted ")) == 3
    assert second =~ "Keys on Monday.\n"
    assert run(ctx, "library_read", %{path: path}) =~ "Keys on Monday."

    # Each paste is a version of his, with its note.
    assert {:ok, %{versions: [newest, oldest | _]}} = Seshat.versions(ctx.id, path)
    assert %{actor: %{kind: "witness"}, note: "Pasted more of the conversation"} = newest
    assert %{actor: %{kind: "witness"}, note: "Pasted a conversation with Sam Okafor"} = oldest
  end

  test "refusals: no kind of hers, no words, outside her folder, not the witness", ctx do
    assert %{"error" => %{"kind" => "seshat_paste_no_kind"}} =
             ctx.conn
             |> post("#{ctx.base}/paste", %{with: "Sam", text: "Hello."})
             |> json_response(422)

    her_kind(ctx)

    for body <- [
          %{with: "Sam", text: "  "},
          %{text: "Hello."},
          %{path: "human/mine.md", text: "Hello."},
          %{with: String.duplicate("a", 201), text: "Hello."}
        ] do
      assert %{"error" => %{"kind" => "seshat_paste_invalid"}} =
               ctx.conn |> post("#{ctx.base}/paste", body) |> json_response(422)
    end

    assert ctx.conn
           |> post("#{ctx.base}/paste", %{path: "human-correspondence/none.md", text: "Hi."})
           |> json_response(404)

    assert {:error, %{kind: :seshat_paste_invalid}} =
             Seshat.paste_correspondence(ctx.id, %{"with" => "Sam", "text" => "Hi."}, ctx.lily)
  end
end

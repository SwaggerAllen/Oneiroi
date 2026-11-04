defmodule OneiroiWeb.DigestRoutesTest do
  @moduledoc """
  The digest (seshat#40, spec F20), invoked rather than scheduled: asked
  by the resident's tool, a check-in's part or the witness; seen by the
  reader through /waiting; answered into feeds/digests/ with a letter to
  the asking conversation. One open at a time, each covering from the
  last one's asking.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    witness = Oneiroi.Actor.new(:witness, account.id)
    {:ok, reader} = AgathosDaimon.register_adapter(resident.id, "scrape", "reader", witness)
    {:ok, brain} = AgathosDaimon.register_adapter(resident.id, "claude-code", "brain", witness)
    {:ok, main} = Kumbukumbu.main_session(resident.id, account.id, witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    lily = Oneiroi.Actor.new(:resident, resident.id, "fake/model")

    {:ok,
     id: resident.id,
     dir: dir,
     main: main,
     reader: reader,
     brain: brain,
     turn: %{resident_id: resident.id, session_key: main, turn_ref: "t", resident: lily}}
  end

  defp bearer(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  test "asked by her tool, seen and answered by the reader, written and lettered; one open at a time",
       ctx do
    id = ctx.id
    assert Tools.run("digest_list", "{}", ctx.turn) == "No digest asked yet."
    assert Tools.run("digest_ask", "{}", ctx.turn) =~ "Asked as digest #1."
    assert Tools.run("digest_ask", "{}", ctx.turn) =~ "Digest #1 is already asked"

    # The reader sees it, and the instant it covers from: the last day.
    assert %{"digests" => [%{"number" => 1}]} =
             ctx.reader |> bearer() |> get("/v1/residents/#{id}/waiting") |> json_response(200)

    assert [%{"number" => 1, "status" => "open", "since" => since}] =
             ctx.reader |> bearer() |> get("/v1/residents/#{id}/digests") |> json_response(200)

    {:ok, since, _} = DateTime.from_iso8601(since)
    assert DateTime.diff(Clock.now(), since, :hour) == 24

    # A brain token neither reads nor answers it.
    assert ctx.brain |> bearer() |> get("/v1/residents/#{id}/digests") |> json_response(404)

    found = %{
      summary: "Two posts and a newsletter; the heron piece is the one to read.",
      items: [
        %{
          source: "thezvi@substack.com",
          title: "Against SURA",
          link: "gmail:1a19e2eca13c8ab8",
          notes: "Argues the proposal confuses two kinds of risk."
        },
        %{
          source: "Epoch AI",
          title: "Exploits from fixes",
          notes: "Patch diffs become exploits fast."
        }
      ]
    }

    assert %{"path" => path} =
             ctx.reader
             |> bearer()
             |> post("/v1/residents/#{id}/digests/1/answer", found)
             |> json_response(200)

    assert path =~ ~r"\Afeeds/digests/1-\d{4}-\d{2}-\d{2}\.md\z"
    written = File.read!(Path.join(ctx.dir, path))
    assert written =~ "# Digest #1"
    assert written =~ "the heron piece is the one to read"

    assert written =~
             "## Against SURA\n\nFrom: thezvi@substack.com\n\nWhere: gmail:1a19e2eca13c8ab8"

    # The chat that asked is told by letter.
    assert [%{text: letter}] = Kumbukumbu.inbox(id, ctx.main)
    assert letter =~ "The reader, on digest #1: compiled: #{path}, 2 item(s)."

    # Compiled, it waits no more, and is not compiled twice.
    assert %{"digests" => []} =
             ctx.reader |> bearer() |> get("/v1/residents/#{id}/waiting") |> json_response(200)

    assert ctx.reader
           |> bearer()
           |> post("/v1/residents/#{id}/digests/1/answer", found)
           |> json_response(422)

    assert Tools.run("digest_list", "{}", ctx.turn) =~ "#1, from "

    # The next covers from the last one's asking, so nothing is read twice.
    Clock.Fake.advance(3_600)
    assert {:ok, 2, :asked} = Seshat.ask_digest(id, nil, ctx.turn.resident)
    [second | _] = Seshat.digests(id, [])
    [%{asked_at: first_asked}] = Seshat.digests(id, status: "answered")
    assert DateTime.compare(second.since, first_asked) == :eq

    # A failure is said and settles it.
    assert ctx.reader
           |> bearer()
           |> post("/v1/residents/#{id}/digests/2/failed", %{reason: "Gmail did not answer"})
           |> response(204)

    assert [%{status: "failed", reason: "Gmail did not answer"} | _] = Seshat.digests(id, [])
  end

  test "a check-in whose note carries the digest part asks for one from the chat", ctx do
    assert Oneiroi.Brain.checkin_part(ctx.id, "digest") =~ "Asked of the reader as digest #1"
    assert [%{number: 1, session_key: key, asked_by: "job"}] = Seshat.digests(ctx.id, [])
    assert key == ctx.main
    assert Oneiroi.Brain.checkin_part(ctx.id, "digest") =~ "Digest #1 was already asked"
  end
end

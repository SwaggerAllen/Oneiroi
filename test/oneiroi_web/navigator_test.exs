defmodule OneiroiWeb.NavigatorTest do
  @moduledoc """
  The navigator's reads over HTTP (design/ui-server-work.md S2):
  bookmarks paged by number and time with the unpaged shape kept
  (kumbukumbu#57), messages paged forward and by anchor (kumbukumbu#57),
  the scenes as rows with their days' `complete` (seshat#52), and the
  per-day density (kumbukumbu#58).
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Actor.new(:witness, account.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, key} = Kumbukumbu.main_session(resident.id, account.id, actor)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, key: key, actor: actor, brain: brain}
  end

  # Turn n at 08:00 on `day` plus n minutes: his message and her reply.
  defp turn(ctx, n, day \\ "2026-10-26") do
    {:ok, base, 0} = DateTime.from_iso8601("#{day}T08:00:00.000000Z")
    at = DateTime.add(base, n * 60, :second)
    ref = "turn-#{n}"

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        ref,
        at,
        [
          %{role: :user, content: "his #{n}", sent_at: at, actor: ctx.actor},
          %{
            role: :assistant,
            content: "her #{n}",
            sent_at: DateTime.add(at, 1, :second),
            actor: ctx.brain
          }
        ],
        ctx.brain
      )

    ref
  end

  defp bookmark(ctx, n, at) do
    attrs = %{session_key: ctx.key, anchor_ref: "turn-1", line: "moment #{n}", anchor_at: at}
    {:ok, ^n} = Kumbukumbu.add_bookmark(ctx.id, attrs, ctx.brain)
  end

  defp contents(body), do: Enum.map(body["messages"], & &1["content"])

  test "bookmarks: unpaged as before; paged by number, by time, and at the edges", ctx do
    turn(ctx, 1)
    base = "/v1/residents/#{ctx.id}/bookmarks"
    bookmark(ctx, 1, ~U[2026-10-24 10:00:00.000000Z])
    bookmark(ctx, 2, ~U[2026-10-25 10:00:00.000000Z])
    bookmark(ctx, 3, ~U[2026-10-25 23:00:00.000000Z])
    bookmark(ctx, 4, ~U[2026-10-26 10:00:00.000000Z])

    # No query: the bare array every client before #57 reads.
    assert [%{"number" => 4}, %{"number" => 3}, %{"number" => 2}, %{"number" => 1}] =
             ctx.conn |> get(base) |> json_response(200)

    assert %{"bookmarks" => [%{"number" => 4}, %{"number" => 3}], "more" => true} =
             ctx.conn |> get(base, %{limit: 2}) |> json_response(200)

    assert %{"bookmarks" => [%{"number" => 2}, %{"number" => 1}], "more" => false} =
             ctx.conn |> get(base, %{limit: 2, before: 3}) |> json_response(200)

    # The edge: a page exactly as long as what remains says no more.
    assert %{"bookmarks" => [%{"number" => 1}], "more" => false} =
             ctx.conn |> get(base, %{limit: 1, before: 2}) |> json_response(200)

    assert %{"bookmarks" => [], "more" => false} =
             ctx.conn |> get(base, %{before: 1}) |> json_response(200)

    # A date is the whole local day; an instant is taken as given, `to`
    # exclusive.
    assert %{"bookmarks" => [%{"number" => 3}, %{"number" => 2}], "more" => false} =
             ctx.conn
             |> get(base, %{from: "2026-10-25", to: "2026-10-25"})
             |> json_response(200)

    assert %{"bookmarks" => [%{"number" => 2}]} =
             ctx.conn
             |> get(base, %{from: "2026-10-25T00:00:00Z", to: "2026-10-25T23:00:00Z"})
             |> json_response(200)

    assert %{"error" => %{"kind" => "kumbukumbu_range_invalid"}} =
             ctx.conn |> get(base, %{from: "last tuesday"}) |> json_response(422)
  end

  test "messages: forward from a cursor, and the window around a turn or a cursor", ctx do
    for n <- 1..5, do: turn(ctx, n)
    base = "/v1/residents/#{ctx.id}/sessions/#{ctx.key}"

    first = ctx.conn |> get(base, %{after: "", limit: 3}) |> json_response(200)
    assert contents(first) == ["his 1", "her 1", "his 2"]
    assert first["more"] == true

    cursor = List.last(first["messages"])["cursor"]
    rest = ctx.conn |> get(base, %{after: cursor, limit: 10}) |> json_response(200)
    assert contents(rest) == ["her 2", "his 3", "her 3", "his 4", "her 4", "his 5", "her 5"]
    assert rest["more"] == false

    last = List.last(rest["messages"])["cursor"]

    assert %{"messages" => [], "more" => false} =
             ctx.conn |> get(base, %{after: last}) |> json_response(200)

    # Around a turn: its first message, about half the limit each side.
    around = ctx.conn |> get(base, %{around: "turn-3", limit: 4}) |> json_response(200)
    assert contents(around) == ["his 2", "her 2", "his 3", "her 3"]
    assert %{"more_before" => true, "more_after" => true} = around
    assert around["anchor"] == Enum.at(around["messages"], 2)["cursor"]

    # Around a cursor, at the start: nothing before, so the room goes after.
    start = hd(first["messages"])["cursor"]
    edge = ctx.conn |> get(base, %{around: start, limit: 4}) |> json_response(200)
    assert contents(edge) == ["his 1", "her 1", "his 2", "her 2"]
    assert %{"more_before" => false, "more_after" => true, "anchor" => ^start} = edge

    # Around the end: nothing after.
    tail = ctx.conn |> get(base, %{around: last, limit: 4}) |> json_response(200)
    assert contents(tail) == ["his 4", "her 4", "his 5", "her 5"]
    assert %{"more_before" => true, "more_after" => false} = tail

    assert %{"error" => %{"kind" => "kumbukumbu_no_such_message"}} =
             ctx.conn |> get(base, %{around: "turn-99"}) |> json_response(404)

    # `before` pages back as it did.
    assert %{"messages" => [%{"content" => "her 5"}], "more" => true} =
             ctx.conn |> get(base, %{limit: 1}) |> json_response(200)
  end

  test "scenes as rows with each day's complete flag", ctx do
    {:ok, _} =
      Seshat.scene_write(
        ctx.id,
        %{
          "day" => "2026-10-25",
          "title" => "The morning check-in",
          "from_turn" => "turn-1",
          "to_turn" => "turn-2",
          "from_time" => "08:01",
          "to_time" => "08:02",
          "summary" => "He asked how the night went.",
          "mood" => "quiet",
          "register" => "his"
        },
        ctx.brain
      )

    {:ok, _} =
      Seshat.scene_write(
        ctx.id,
        %{
          "day" => "2026-10-26",
          "title" => "Building",
          "from_turn" => "turn-3",
          "to_turn" => "turn-5",
          "summary" => "The navigator.",
          "rounds_ran_out" => true,
          "register" => "work",
          "final" => true
        },
        ctx.brain
      )

    base = "/v1/residents/#{ctx.id}/scenes"

    assert %{
             "days" => [
               %{
                 "day" => "2026-10-25",
                 "complete" => false,
                 "scenes" => [
                   %{
                     "number" => 1,
                     "kind" => "scene",
                     "title" => "The morning check-in",
                     "from_turn" => "turn-1",
                     "to_turn" => "turn-2",
                     "from_time" => "2026-10-25T08:01:00.000000Z",
                     "to_time" => "2026-10-25T08:02:00.000000Z",
                     "mood" => "quiet",
                     "register" => "his",
                     "rounds_ran_out" => false,
                     "by" => "resident"
                   }
                 ]
               },
               %{
                 "day" => "2026-10-26",
                 "complete" => true,
                 "scenes" => [%{"rounds_ran_out" => true}]
               }
             ]
           } = ctx.conn |> get(base) |> json_response(200)

    assert %{"days" => [%{"day" => "2026-10-26"}]} =
             ctx.conn |> get(base, %{from: "2026-10-26", to: "2026-10-26"}) |> json_response(200)

    assert ctx.conn |> get(base, %{from: "soon"}) |> json_response(422)
  end

  test "density: bookmarks, scenes and messages per local day, every day of the range", ctx do
    turn(ctx, 1, "2026-10-24")
    turn(ctx, 2, "2026-10-26")
    turn(ctx, 3, "2026-10-26")
    bookmark(ctx, 1, ~U[2026-10-26 09:00:00.000000Z])
    bookmark(ctx, 2, ~U[2026-10-26 10:00:00.000000Z])

    {:ok, _} =
      Seshat.scene_write(
        ctx.id,
        %{
          "day" => "2026-10-24",
          "title" => "Morning",
          "from_turn" => "turn-1",
          "to_turn" => "turn-1",
          "summary" => "Hello."
        },
        ctx.brain
      )

    # A correction of a summary is a row, not a scene: not counted.
    {:ok, _} =
      Seshat.scene_write(
        ctx.id,
        %{
          "day" => "2026-10-24",
          "corrects" => 1,
          "from_turn" => "turn-1",
          "to_turn" => "turn-1",
          "summary" => "Hello, and the weather.",
          "note" => "I left out the weather"
        },
        ctx.brain
      )

    base = "/v1/residents/#{ctx.id}/density"

    assert %{
             "from" => "2026-10-24",
             "to" => "2026-10-26",
             "zone" => _,
             "days" => [
               %{"day" => "2026-10-24", "bookmarks" => 0, "scenes" => 1, "messages" => 2},
               %{"day" => "2026-10-25", "bookmarks" => 0, "scenes" => 0, "messages" => 0},
               %{"day" => "2026-10-26", "bookmarks" => 2, "scenes" => 0, "messages" => 4}
             ]
           } =
             ctx.conn |> get(base, %{from: "2026-10-24", to: "2026-10-26"}) |> json_response(200)

    # The default: the last thirty days through today (the fake clock's).
    assert %{"to" => "2026-10-26", "days" => days} =
             ctx.conn |> get(base) |> json_response(200)

    assert length(days) == 30

    # One session's messages only.
    assert %{"days" => [%{"messages" => 0}]} =
             ctx.conn
             |> get(base, %{from: "2026-10-26", to: "2026-10-26", session: "nobody"})
             |> json_response(200)

    assert ctx.conn |> get(base, %{from: "2026-10-27", to: "2026-10-26"}) |> json_response(422)
    assert ctx.conn |> get(base, %{from: "2024-01-01", to: "2026-10-26"}) |> json_response(422)
  end

  test "a date bound is the whole local day in her zone" do
    assert {:ok, ~U[2026-11-10 08:00:00.000000Z]} =
             Kumbukumbu.Days.bound("America/Los_Angeles", "2026-11-10", :from)

    assert {:ok, ~U[2026-11-11 08:00:00.000000Z]} =
             Kumbukumbu.Days.bound("America/Los_Angeles", "2026-11-10", :to)

    assert {:ok, nil} = Kumbukumbu.Days.bound("Etc/UTC", nil, :from)
  end
end

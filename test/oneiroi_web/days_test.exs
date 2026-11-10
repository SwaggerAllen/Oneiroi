defmodule OneiroiWeb.DaysTest do
  @moduledoc """
  The calendar's ranges over HTTP (design/ui-server-work.md S5,
  sunna#48): each day's journal marks, its story (sessions with their
  times, kumbukumbu#59, and scenes), and for today and after the
  schedule computed from the rules; the range's bounds refused as 422.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna

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
    # The fake clock's 2026-10-26 12:00 UTC is 05:00 that day here (PDT).
    :ok = AgathosDaimon.set_timezone(resident.id, "America/Los_Angeles", actor)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, account: account, actor: actor, brain: brain}
  end

  defp base(ctx), do: "/v1/residents/#{ctx.id}/days"

  test "a range is two dates in order, at most SUNNA_DAYS_SPAN days", ctx do
    assert %{"error" => %{"kind" => "sunna_range_invalid"}} =
             ctx.conn |> get(base(ctx), %{from: "2026-10-24"}) |> json_response(422)

    assert %{"error" => %{"kind" => "sunna_day_invalid"}} =
             ctx.conn |> get(base(ctx), %{from: "soon", to: "2026-10-24"}) |> json_response(422)

    assert %{"error" => %{"kind" => "sunna_range_invalid"}} =
             ctx.conn
             |> get(base(ctx), %{from: "2026-10-25", to: "2026-10-24"})
             |> json_response(422)

    # 62 days pass; 63 do not.
    assert %{"days" => days} =
             ctx.conn
             |> get(base(ctx), %{from: "2026-10-01", to: "2026-12-01"})
             |> json_response(200)

    assert length(days) == 62

    assert %{"error" => %{"kind" => "sunna_range_invalid"}} =
             ctx.conn
             |> get(base(ctx), %{from: "2026-10-01", to: "2026-12-02"})
             |> json_response(422)

    assert {:error, %{kind: :sunna_range_invalid}} = Sunna.days_range(ctx.id, nil, "2026-10-01")
  end

  test "each day's marks, story and, from today, its schedule", ctx do
    id = ctx.id
    {:ok, main} = Kumbukumbu.main_session(id, ctx.account.id, ctx.actor)
    at = ~U[2026-10-25 16:00:00.000000Z]

    :ok =
      Kumbukumbu.capture(
        id,
        main,
        "turn-1",
        at,
        [
          %{role: :user, content: "his words", sent_at: at, actor: ctx.actor},
          %{
            role: :assistant,
            content: "her words",
            sent_at: DateTime.add(at, 60, :second),
            actor: ctx.brain
          }
        ],
        ctx.brain
      )

    # Her free time, private under the contract: a locked row to him.
    {:ok, solo} =
      Kumbukumbu.open_session(id, "free_time", "brain", [ctx.account.id], ctx.brain,
        private: true
      )

    {:ok, _} = Seshat.journal_add(id, "2026-10-25", "plan", "Bake.", ctx.actor)

    {:ok, _} =
      Seshat.scene_write(
        id,
        %{
          "day" => "2026-10-25",
          "title" => "Morning",
          "from_turn" => "turn-1",
          "to_turn" => "turn-1",
          "from_time" => "09:00",
          "to_time" => "09:01",
          "summary" => "The scene's words.",
          "final" => true
        },
        ctx.brain
      )

    {:ok, morning} = Sunna.set_checkin(id, nil, "Morning", "08:00", ctx.actor)
    {:ok, late} = Sunna.set_checkin(id, nil, "Late", "23:30", ctx.actor)
    :ok = Sunna.set_quiet_hours(id, "23:00", "07:00", ctx.actor)
    # Rounds every three hours of her waking 07:00-23:00: six a day, counted, never timed.
    :ok = Sunna.set_rounds(id, 3, nil, ctx.actor)
    :ok = Sunna.add_free_time_once(id, "2026-10-27", "10:00", ctx.actor)

    {:ok, date} =
      Sunna.set_date(
        id,
        nil,
        %{title: "Launch", on: ~U[2026-10-28 18:00:00.000000Z], kind: "deadline"},
        ctx.actor
      )

    body =
      ctx.conn |> get(base(ctx), %{from: "2026-10-24", to: "2026-10-28"}) |> json_response(200)

    assert %{
             "from" => "2026-10-24",
             "to" => "2026-10-28",
             "today" => "2026-10-26",
             "zone" => "America/Los_Angeles",
             "witness_reads" => true,
             "days" => [d24, d25, d26, d27, d28]
           } = body

    # An empty past day.
    assert %{
             "day" => "2026-10-24",
             "journal" => nil,
             "story" => %{"sessions" => [], "scenes" => [], "complete" => nil},
             "schedule" => nil
           } = d24

    # A past day: marks, the session he was in with its times, the scene.
    assert %{
             "journal" => %{"plan" => 1, "wrap" => 0, "unwrapped" => true},
             "story" => %{
               "sessions" => [
                 %{
                   "key" => ^main,
                   "kind" => "main",
                   "title" => "Oneiroi chat",
                   "locked" => false,
                   "first_at" => "2026-10-25T16:00:00.000000Z",
                   "last_at" => "2026-10-25T16:01:00.000000Z",
                   "messages" => 2
                 }
               ],
               "scenes" => [%{"number" => 1, "title" => "Morning", "from_time" => _}],
               "complete" => true
             },
             "schedule" => nil
           } = d25

    # No word of the scene's summary or any message reaches the calendar.
    refute Jason.encode!(body) =~ "words"

    # Today: the locked session by its row's receipts, and a schedule.
    assert %{
             "story" => %{
               "sessions" => [%{"key" => ^solo, "locked" => true, "messages" => nil}]
             },
             "schedule" => %{"quiet" => %{"from" => "23:00", "to" => "07:00"}, "rounds" => 6}
           } = d26

    # A future day: in time order, each with its rule and status; the
    # check-in inside quiet hours waits for their end, the next morning.
    assert %{"schedule" => %{"entries" => entries}} = d27

    assert [
             %{
               "kind" => "checkin",
               "key" => ^morning,
               "label" => "Morning",
               "time" => "08:00",
               "at" => "2026-10-27T15:00:00.000000Z",
               "deferred" => false,
               "rule" => %{"freq" => "daily"},
               "status" => "scheduled"
             },
             %{"kind" => "free_time", "key" => "once 10:00", "rule" => nil, "added_by" => _},
             %{"kind" => "free_time", "key" => "14:30", "at" => "2026-10-27T21:30:00.000000Z"},
             %{"kind" => "free_time", "key" => "22:30"},
             %{
               "kind" => "checkin",
               "key" => ^late,
               "time" => "23:30",
               "at" => "2026-10-28T14:00:00.000000Z",
               "deferred" => true
             }
           ] = entries

    date_key = Integer.to_string(date)

    assert %{"schedule" => %{"entries" => later}} = d28

    assert [%{"label" => "Launch", "time" => "11:00", "date_kind" => "deadline", "rule" => nil}] =
             Enum.filter(later, &(&1["kind"] == "date" and &1["key"] == date_key))

    # The exports the route composes.
    assert %{"2026-10-25" => %{plan: 1}} = Seshat.journal_marks(id, ["2026-10-24", "2026-10-25"])
    assert %{} == Seshat.journal_marks(id, [])
    assert %{} == Sunna.day_schedules(id, ["2026-10-25"])

    assert {:ok, %{"2026-10-25" => [%{key: ^main}]}} =
             Kumbukumbu.session_days({:account, ctx.account.id}, id, "2026-10-25", "2026-10-25")
  end

  test "with witness_reads off, the journal and the scenes are left out", ctx do
    {:ok, _} = Seshat.journal_add(ctx.id, "2026-10-25", "plan", "Bake.", ctx.actor)

    {:ok, :moved} =
      AgathosDaimon.move_switch_to_safety(ctx.id, "witness_reads", "mine", ctx.brain)

    assert %{
             "witness_reads" => false,
             "days" => [
               %{
                 "journal" => nil,
                 "story" => %{"sessions" => [], "scenes" => nil, "complete" => nil}
               }
             ]
           } =
             ctx.conn
             |> get(base(ctx), %{from: "2026-10-25", to: "2026-10-25"})
             |> json_response(200)
  end

  test "a resident he does not witness is not found", ctx do
    other = Fixtures.resident!(Fixtures.account!())

    assert ctx.conn
           |> get("/v1/residents/#{other.id}/days", %{from: "2026-10-25", to: "2026-10-25"})
           |> json_response(404)
  end
end

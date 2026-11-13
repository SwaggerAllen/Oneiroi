defmodule OneiroiWeb.RetryTest do
  @moduledoc """
  brain#89: a failed turn runs again from the bell, as what it was: free
  time as free time now, a failure in the main chat that was no check-in
  as a wake saying so, every credit refusal at once after a top-up.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NeedsYou
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model

  @credits "nisaba_request_refused: 402 This request requires more credits, or fewer max_tokens."

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    me = Actor.new(:witness, account.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", me)
    {:ok, main} = Kumbukumbu.main_session(resident.id, account.id, me)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    Model.clear()

    on_exit(fn ->
      Model.clear(for: resident.id)
      File.rm_rf!(dir)
    end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, account: account, main: main, me: me, brain: brain}
  end

  defp open_failures(ctx),
    do: Enum.filter(Kumbukumbu.failures({:resident, ctx.id}), &(&1.resident_id == ctx.id))

  defp eventually(check, tries \\ 100) do
    cond do
      check.() -> :ok
      tries == 0 -> flunk("never happened")
      true -> Process.sleep(30) && eventually(check, tries - 1)
    end
  end

  test "failed free time runs again now, as free time, and the failure is settled", ctx do
    {:ok, free} =
      Kumbukumbu.open_session(ctx.id, "free_time", "brain", [ctx.account.id], ctx.brain,
        private: true
      )

    :ok =
      Kumbukumbu.fail_capture(
        ctx.id,
        free,
        "t-free",
        "nisaba_provider_failed: 502 lost",
        ctx.brain
      )

    assert [%{kind: "turn_failed", about: %{retry: "Run free time now"}}] =
             Enum.filter(NeedsYou.list(ctx.id), &(&1.kind == "turn_failed"))

    assert %{"started" => "Run free time now"} =
             ctx.conn
             |> post("/v1/residents/#{ctx.id}/capture-failures/t-free/retry")
             |> json_response(202)

    assert open_failures(ctx) == []

    eventually(fn ->
      Enum.any?(
        Oneiroi.Sunna.free_time_history(ctx.id, 5),
        &String.starts_with?(&1.slot || "", "retry-")
      )
    end)

    # Run again, it is settled: nothing to retry twice.
    assert %{"error" => %{"kind" => "brain_no_such_failure"}} =
             ctx.conn
             |> post("/v1/residents/#{ctx.id}/capture-failures/t-free/retry")
             |> json_response(404)
  end

  test "after a top-up, every credit refusal runs again, each purpose once", ctx do
    :ok = Kumbukumbu.fail_capture(ctx.id, ctx.main, "t-1", @credits, ctx.brain)
    :ok = Kumbukumbu.fail_capture(ctx.id, ctx.main, "t-2", @credits, ctx.brain)

    assert [%{about: %{retry: "Run them all again"}}] =
             Enum.filter(NeedsYou.list(ctx.id), &(&1.kind == "provider_credits"))

    assert %{"started" => ["Wake her now"]} =
             ctx.conn
             |> post("/v1/residents/#{ctx.id}/capture-failures/retry-credits")
             |> json_response(202)

    assert open_failures(ctx) == []

    eventually(fn ->
      Kumbukumbu.turns_since(ctx.id, "main", DateTime.add(Clock.now(), -3600)) > 0
    end)
  end
end

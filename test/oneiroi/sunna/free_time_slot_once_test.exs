defmodule Oneiroi.Sunna.FreeTimeSlotOnceTest do
  @moduledoc """
  A free-time slot runs once (sunna#66; Lily's wake-failure list,
  2026-11-15 to -17): a wake that outlasts its wait is her free time
  running on, recorded as run and never as failed; and while one tick is
  running a slot, another tick does not open it again.
  """
  use Oneiroi.DataCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Scope
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.FreeTimeWorker
  alias Oneiroi.Sunna.Store

  # The fake clock's epoch, 2026-10-26 12:00Z, is 08:00 in New York.
  @zone "America/New_York"
  @day "2026-10-26"
  @store {Oneiroi.Config, :values}

  defmodule Outlasted do
    @moduledoc false
    # The wake port answering as the session does when the turn outlasts
    # the wait: it runs on, and the caller hears so.
    def wake(_resident_id, _key, _note, _purpose),
      do: {:error, %{kind: :brain_wake_outlasted, site: :brain_session_wake_outlasted}}
  end

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    :ok = AgathosDaimon.set_timezone(resident.id, @zone, actor)
    :ok = Sunna.set_free_time(resident.id, ["08:00"], actor)
    Fake.clear()
    Fake.reply("Herons.", for: resident.id)
    {:ok, id: resident.id}
  end

  defp sessions(id),
    do: for(%{kind: "free_time", key: k} <- Kumbukumbu.sessions({:resident, id}), do: k)

  test "a wake that outlasts its wait is a run, not a failure, and the slot does not open again",
       ctx do
    values = :persistent_term.get(@store)
    on_exit(fn -> :persistent_term.put(@store, values) end)
    :persistent_term.put(@store, Map.put(values, {:sunna, :wake}, Outlasted))

    :ok = Sunna.tick(ctx.id)
    assert [_one] = sessions(ctx.id)

    assert [%{outcome: outcome}] =
             Scope.resident(ctx.id, fn -> Store.free_time_runs(@day) end)

    refute outcome =~ "outlasted"

    # Its planning turn is queued behind it (sunna#75), so the run is
    # closed when she is done rather than held open three hours.
    assert [%{args: %{"turn" => "plan", "run" => "2026-10-26 08:00"}}] =
             for(j <- all_enqueued(worker: FreeTimeWorker), j.args["turn"] == "plan", do: j)

    Clock.Fake.advance(60)
    :ok = Sunna.tick(ctx.id)
    assert [key] = sessions(ctx.id)

    # Its closing turn outlasting the wait too still closes the run
    # (sunna#97): it runs on, and the run is over.
    assert :ok = Sunna.Schedules.plan_free_time(ctx.id, key)

    assert [%{planning_nanos: nanos}] =
             Scope.resident(ctx.id, fn -> Store.free_time_runs(@day) end)

    assert is_integer(nanos)
  end

  test "while another tick runs the slot, this one leaves it; after, the slot runs once", ctx do
    lock = {{:sunna_free_time_slot, ctx.id, @day, "08:00"}, :other_tick}
    holder = self()

    other =
      spawn(fn ->
        true = :global.set_lock(lock, [node()], 0)
        send(holder, :held)

        receive do
          :release -> :global.del_lock(lock, [node()])
        end

        send(holder, :released)
      end)

    assert_receive :held
    :ok = Sunna.tick(ctx.id)
    assert sessions(ctx.id) == []

    send(other, :release)
    assert_receive :released
    :ok = Sunna.tick(ctx.id)
    assert [_one] = sessions(ctx.id)

    Clock.Fake.advance(60)
    :ok = Sunna.tick(ctx.id)
    assert [_still_one] = sessions(ctx.id)
  end
end

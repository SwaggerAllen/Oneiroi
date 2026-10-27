defmodule Oneiroi.Apsu.SpineTest do
  @moduledoc """
  The persistence spine as the migrations leave it (plan P0.2): the
  application role, its rights, the scope wrapper and the event store.
  """
  use Oneiroi.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Scope

  test "the connection runs as the application role, which cannot bypass row-level security" do
    assert %{rows: [["oneiroi_app", false, false]]} =
             Repo.query!(
               "SELECT current_user, rolbypassrls, rolsuper FROM pg_roles WHERE rolname = current_user"
             )
  end

  test "the application role cannot run DDL" do
    assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
             Repo.query("CREATE TABLE platform_probe (id int)")
  end

  test "a read with no scope is refused before it reaches the database" do
    assert_raise Oneiroi.Repo.UnscopedError, ~r/no Oneiroi.Scope set/, fn ->
      Repo.all(from(r in "schema_migrations", select: r.version))
    end
  end

  test "a scope is transaction-local on the connection and process-local in the tree" do
    assert Scope.current() == nil
    id = "11111111-1111-1111-1111-111111111111"

    assert Scope.resident(id, fn ->
             %{rows: [[kind, resident]]} =
               Repo.query!(
                 "SELECT current_setting('oneiroi.scope', true), current_setting('oneiroi.resident_id', true)"
               )

             assert Scope.current() == {:resident, id}
             {kind, resident}
           end) == {"resident", id}

    assert Scope.current() == nil
  end

  test "the event store's schema is the migration's and the application appends and reads" do
    stream = Ecto.UUID.generate()

    event = %EventStore.EventData{
      event_type: "Elixir.Oneiroi.Test.PlainEvent",
      data: %Oneiroi.Test.PlainEvent{
        actor: Oneiroi.Actor.platform(),
        at: ~U[2026-10-26 12:00:00Z],
        name: "x"
      },
      metadata: %{}
    }

    assert :ok = Oneiroi.EventStore.append_to_stream(stream, 0, [event])

    assert {:ok,
            [
              %EventStore.RecordedEvent{
                data: %Oneiroi.Test.PlainEvent{name: "x", actor: %Oneiroi.Actor{kind: :platform}}
              }
            ]} =
             Oneiroi.EventStore.read_stream_forward(stream, 0, 10)
  end

  test "the cost harness counts every statement from this process, the transaction's included" do
    # begin, set_config, the query, commit: four, and a budget of four
    # is what a scoped single-statement read costs.
    assert {_result, 4} =
             count_statements(fn -> Scope.platform(fn -> Repo.query!("SELECT 1") end) end)

    assert_statements(4, fn -> Scope.platform(fn -> Repo.query!("SELECT 1") end) end)
  end
end

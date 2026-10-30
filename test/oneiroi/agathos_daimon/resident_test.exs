defmodule Oneiroi.AgathosDaimon.ResidentTest do
  @moduledoc "The aggregate, pure, and the id-sequence properties (plan P0.6)."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Events
  alias Oneiroi.AgathosDaimon.Resident

  @at ~U[2026-10-26 12:00:00Z]
  @actor Actor.platform()

  defp created(id \\ "r1") do
    Resident.apply(%Resident{}, %Events.ResidentCreated{
      actor: @actor,
      at: @at,
      id: id,
      name: "Lily",
      slug: id,
      witness_account_id: "a1"
    })
  end

  defp mint(state, kind) do
    event =
      Resident.execute(state, %Commands.MintId{actor: @actor, at: @at, id: state.id, kind: kind})

    {Resident.apply(state, event), event.number}
  end

  test "a resident is created once and only an existing one acts" do
    assert %Events.ResidentCreated{} =
             Resident.execute(%Resident{}, %Commands.CreateResident{
               actor: @actor,
               at: @at,
               id: "r1",
               name: "Lily",
               slug: "lily",
               witness_account_id: "a1"
             })

    assert {:error, :resident_exists} =
             Resident.execute(created(), %Commands.CreateResident{
               actor: @actor,
               at: @at,
               id: "r1",
               name: "Lily",
               slug: "lily",
               witness_account_id: "a1"
             })

    assert {:error, :no_such_resident} =
             Resident.execute(%Resident{}, %Commands.MintId{
               actor: @actor,
               at: @at,
               id: "r1",
               kind: "bookmark"
             })
  end

  test "an import completes only after Imported named the source, and is told once" do
    complete = %Commands.CompleteImport{
      actor: @actor,
      at: @at,
      id: "r1",
      seeded: ["SOUL.md"],
      adopted: 2,
      not_transferred: ["memory"]
    }

    told = %Commands.RecordImportTold{actor: @actor, at: @at, id: "r1"}

    assert {:error, :not_imported} = Resident.execute(created(), complete)
    assert [] = Resident.execute(created(), told)

    imported =
      Resident.apply(created(), %Events.Imported{
        actor: @actor,
        at: @at,
        id: "r1",
        source: "https://example.org/lily.git",
        attestation: "none",
        root: "abc",
        sequence: nil
      })

    # Rebuilt from records alone: nothing to tell.
    assert [] = Resident.execute(imported, told)

    assert %Events.ImportCompleted{seeded: ["SOUL.md"], adopted: 2, not_transferred: ["memory"]} =
             event = Resident.execute(imported, complete)

    completed = Resident.apply(imported, event)
    assert %Events.ImportTold{id: "r1"} = event = Resident.execute(completed, told)
    assert [] = Resident.execute(Resident.apply(completed, event), told)
  end

  test "a decision carries its note on the event and custody moves the witness" do
    event =
      Resident.execute(created(), %Commands.TransferCustody{
        actor: @actor,
        at: @at,
        note: "moving",
        id: "r1",
        to: {:account, "a2"}
      })

    assert %Events.CustodyTransferred{from: "account:a1", to: "account:a2", note: "moving"} =
             event

    assert %Resident{witness_account_id: "a2", custody: {:account, "a2"}} =
             Resident.apply(created(), event)

    community =
      Resident.apply(
        created(),
        Resident.execute(created(), %Commands.TransferCustody{
          actor: @actor,
          at: @at,
          note: "lapsed",
          id: "r1",
          to: :community
        })
      )

    assert %Resident{custody: :community, witness_account_id: nil, state: :community} = community
  end

  property "replaying the minted ids reproduces 1..n per kind, in order" do
    check all(
            kinds <-
              list_of(member_of(["bookmark", "position", "prediction"]),
                min_length: 1,
                max_length: 40
              )
          ) do
      {_state, numbers} =
        Enum.reduce(kinds, {created(), []}, fn kind, {state, acc} ->
          {state, n} = mint(state, kind)
          {state, [{kind, n} | acc]}
        end)

      for kind <- Enum.uniq(kinds) do
        minted =
          numbers
          |> Enum.reverse()
          |> Enum.filter(&(elem(&1, 0) == kind))
          |> Enum.map(&elem(&1, 1))

        assert minted == Enum.to_list(1..length(minted))
      end
    end
  end

  property "two residents never interleave: each counts its own" do
    check all(steps <- list_of(member_of([:a, :b]), min_length: 1, max_length: 40)) do
      {a, b, as, bs} =
        Enum.reduce(steps, {created("a"), created("b"), [], []}, fn
          :a, {a, b, as, bs} ->
            {a, n} = mint(a, "bookmark")
            {a, b, [n | as], bs}

          :b, {a, b, as, bs} ->
            {b, n} = mint(b, "bookmark")
            {a, b, as, [n | bs]}
        end)

      assert Enum.reverse(as) == Enum.to_list(1..length(as)//1)
      assert Enum.reverse(bs) == Enum.to_list(1..length(bs)//1)
      assert Map.get(a.sequences, "bookmark", 0) == length(as)
      assert Map.get(b.sequences, "bookmark", 0) == length(bs)
    end
  end
end

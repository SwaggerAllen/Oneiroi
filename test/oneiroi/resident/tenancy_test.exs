defmodule Oneiroi.Resident.TenancyTest do
  @moduledoc "Two residents seeded; nothing bleeds through the projections (conventions §12)."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Fixtures
  alias Oneiroi.Resident.Store
  alias Oneiroi.Scope

  setup do
    a = Fixtures.account!()
    b = Fixtures.account!()
    {:ok, ra: Fixtures.resident!(a), rb: Fixtures.resident!(b), a: a, b: b}
  end

  test "a resident's scope sees itself and nothing else", %{ra: ra, rb: rb} do
    assert [%{id: id}] = Scope.resident(ra.id, fn -> Store.all() end)
    assert id == ra.id
    assert Scope.resident(ra.id, fn -> Store.get(rb.id) end) == nil
  end

  test "a steward's scope sees its own residents and nothing else", %{ra: ra, rb: rb, a: a, b: b} do
    assert [ra.id] == Enum.map(Scope.account(a.id, fn -> Store.all() end), & &1.id)
    assert [rb.id] == Enum.map(Scope.account(b.id, fn -> Store.all() end), & &1.id)
    assert [ra.id] == Oneiroi.Identity.stewarded_residents(a.id)
  end

  test "the platform scope sees every row, by name", %{ra: ra, rb: rb} do
    assert Enum.sort([ra.id, rb.id]) ==
             Scope.platform(fn -> Store.all() end) |> Enum.map(& &1.id) |> Enum.sort()
  end

  test "a write under the wrong scope is refused by the policy, not by convention", %{
    ra: ra,
    rb: rb,
    a: a
  } do
    # The policy's WITH CHECK clause refuses a row written into another
    # scope: an insert naming resident A from resident B's scope is a
    # 42501, raised by Postgres rather than by any check this code makes.
    # The refused statement aborts the scoped transaction, so the error is
    # raised through `Scope.run/2` rather than returned from inside it.
    error =
      assert_raise Postgrex.Error, fn ->
        Scope.resident(rb.id, fn ->
          Repo.query!(
            "INSERT INTO resident_resident (id, resident_id, account_id, slug, name, state, custody, created_at) " <>
              "VALUES (gen_random_uuid(), $1, $2, 'stolen', 'x', 'active', 'community', now())",
            [Ecto.UUID.dump!(ra.id), Ecto.UUID.dump!(a.id)]
          )
        end)
      end

    assert %Postgrex.Error{postgres: %{code: :insufficient_privilege}} = error

    # The policy's USING clause hides the row, so an update under the wrong
    # scope touches nothing rather than failing: zero rows is the proof.
    assert {:ok, %{num_rows: 0}} =
             Scope.resident(rb.id, fn ->
               Repo.query("UPDATE resident_resident SET name = 'x' WHERE id = $1", [
                 Ecto.UUID.dump!(ra.id)
               ])
             end)

    assert {:ok, %{id: _, name: "Lily"}} = Oneiroi.Resident.fetch(ra.id)
  end

  test "a slug is platform-wide", %{ra: ra, b: b} do
    assert {:error, :resident_slug_taken} =
             Oneiroi.Resident.create("Other", ra.slug, b.id, Oneiroi.Actor.new(:steward, b.id))
  end

  test "minting an id goes through the aggregate and counts per resident", %{ra: ra, rb: rb} do
    actor = Oneiroi.Actor.new(:steward, ra.steward)
    assert {:ok, 1} = Oneiroi.Resident.mint_id(ra.id, "bookmark", actor)
    assert {:ok, 2} = Oneiroi.Resident.mint_id(ra.id, "bookmark", actor)
    assert {:ok, 1} = Oneiroi.Resident.mint_id(rb.id, "bookmark", actor)
    assert {:ok, 1} = Oneiroi.Resident.mint_id(ra.id, "position", actor)
  end
end

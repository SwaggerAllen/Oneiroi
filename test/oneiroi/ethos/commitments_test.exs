defmodule Oneiroi.Ethos.CommitmentsTest do
  @moduledoc "Commitments: the resident's promises to a person, numbered, kept or released with a note by the parties that may; loaded every turn; cited by number."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Ethos
  alias Oneiroi.Ethos.Character
  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Seshat.Citations

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    brain = Actor.new(:resident, resident.id, "fake/model")
    witness_actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", witness_actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, witness_actor)
    Model.clear()
    on_exit(fn -> Model.clear(for: resident.id) end)

    {:ok,
     witness: witness, resident: resident, brain: brain, witness_actor: witness_actor, key: key}
  end

  test "a commitment is the resident's to make and keep, either party's to release, once, numbered and citeable",
       ctx do
    id = ctx.resident.id

    assert {:error, %Ethos.Error{kind: :ethos_not_the_resident}} =
             Ethos.make_commitment(id, "witness", "I will water the garden.", ctx.witness_actor)

    assert {:error, %Ethos.Error{kind: :ethos_commitment_invalid}} =
             Ethos.make_commitment(id, "", "I will water the garden.", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_commitment_invalid}} =
             Ethos.make_commitment(id, "witness", "  ", ctx.brain)

    assert {:ok, 1} =
             Ethos.make_commitment(
               id,
               "witness",
               "I will water the garden while you are away.",
               ctx.brain
             )

    assert {:ok, 2} =
             Ethos.make_commitment(id, "Rose", "I will write to you on Sundays.", ctx.brain)

    assert [%{number: 1, to: "witness", state: "open", note: nil}, %{number: 2, to: "Rose"}] =
             Ethos.commitments(id)

    # Loaded every turn, bounded, with the numbers as refs.
    assert %{text: text, numbers: [1, 2]} = Ethos.promised(id)

    assert text =~ "# What I have promised" and
             text =~ "#1, to witness, made 2026-10-26: I will water the garden"

    # Kept by the resident alone; released by either; a closed one is history.
    assert {:error, %Ethos.Error{kind: :ethos_not_the_resident}} =
             Ethos.keep_commitment(id, 1, "done", ctx.witness_actor)

    assert :ok = Ethos.keep_commitment(id, 1, "watered twice a week", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_commitment_closed}} =
             Ethos.keep_commitment(id, 1, "again", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_no_such_commitment}} =
             Ethos.release_commitment(id, 9, "x", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_not_a_party}} =
             Ethos.release_commitment(id, 2, "x", Actor.new(:judge, "j", "fake/judge"))

    assert :ok = Ethos.release_commitment(id, 2, "she said not to bother", ctx.witness_actor)

    assert [
             %{
               number: 1,
               state: "kept",
               note: "watered twice a week",
               closed_by_kind: "resident"
             },
             %{number: 2, state: "released", closed_by_kind: "witness"}
           ] = Ethos.commitments(id)

    assert %{text: "", numbers: []} = Ethos.promised(id)

    # Cited by number, with its state and the person (seshat #14).
    assert {:ok, "I will write to you on Sundays. (to Rose, released)"} =
             Citations.resolve(%{id: id, slug: ctx.resident.slug}, %{
               slug: ctx.resident.slug,
               kind: "commitment",
               ref: "2"
             })

    assert [%{kind: "commitment", ref: "1"}] =
             Citations.extract("as I said in #{ctx.resident.slug}:commitment/1.")

    # Pure: once per number, both words present, open to close.
    make = %Commands.MakeCommitment{
      actor: ctx.brain,
      at: ~U[2026-10-26 12:00:00Z],
      id: "r1",
      number: 1,
      to: "witness",
      text: "x"
    }

    s = Character.apply(%Character{}, Character.execute(%Character{}, make))
    assert [] = Character.execute(s, make)

    assert {:error, %{kind: :ethos_commitment_invalid, site: :ethos_make_commitment_invalid}} =
             Character.execute(s, %{make | number: 2, to: " "})

    keep = %Commands.KeepCommitment{
      actor: ctx.brain,
      at: ~U[2026-10-26 12:00:00Z],
      note: "n",
      id: "r1",
      number: 1
    }

    kept = Character.apply(s, Character.execute(s, keep))

    assert {:error, %{kind: :ethos_commitment_closed, site: :ethos_open_commitment_closed}} =
             Character.execute(kept, keep)

    assert {:error,
            %{
              kind: :ethos_no_such_commitment,
              site: :ethos_open_commitment_absent,
              details: [number: 3]
            }} = Character.execute(kept, %{keep | number: 3})
  end

  test "the brain promises, lists, keeps and is shown what it promised on the next turn", ctx do
    id = ctx.resident.id

    Model.calls(
      [
        %{
          name: "commitment_make",
          arguments: %{to: "witness", text: "I will keep the kettle filled."}
        },
        %{name: "commitment_list", arguments: %{}}
      ],
      "Promised.",
      for: id
    )

    assert {:ok, %{messages: [_, made, listed, _]}} =
             Oneiroi.Brain.turn(id, ctx.key, "will you?", ctx.witness_actor)

    assert made.content =~ "Promised, as commitment #1."
    assert listed.content =~ "#1 (open) to witness: I will keep the kettle filled."

    # The next turn is assembled with the promise in its prefix; the row says so.
    Model.script(fn _request -> {:ok, "Filled."} end, for: id)
    assert {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, ctx.key, "and?", ctx.witness_actor)
    assert :ok = Ethos.keep_commitment(id, 1, "filled it", ctx.brain)

    assert %{reason: reason, text: text} =
             {:account, ctx.witness.id}
             |> Kumbukumbu.injections(ref)
             |> Enum.find(&(&1.label == "promised"))

    assert reason =~ "1 open commitments named" and text =~ "I will keep the kettle filled."
    assert [%{number: 1, state: "kept"}] = Ethos.commitments(id)
  end
end

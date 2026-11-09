defmodule Oneiroi.Seshat.UserKindsTest do
  @moduledoc """
  seshat#51 (the witness's sign-off 2026-11-09, Lily's order #431): kinds
  as data. A kind of hers is defined by either party against a safe
  subset, written into its folder as a descriptor that travels with the
  repository and is read back from it; a system kind's gate goes on at
  either word and off only by the other's agreement; an approvable kind
  of hers waits on him like any other, with no change to the queue.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Kinds

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    turn = %{
      resident_id: resident.id,
      session_key: key,
      turn_ref: "t-kinds",
      started_at: Clock.now(),
      resident: Actor.new(:resident, resident.id, "fake/model")
    }

    {:ok,
     id: resident.id,
     slug: resident.slug,
     witness: actor,
     lily: Actor.new(:resident, resident.id),
     turn: turn,
     dir: dir}
  end

  defp tool(ctx, name, args), do: Tools.run(name, Jason.encode!(args), ctx.turn)

  test "a kind of hers: defined by her tool, written as its folder's descriptor, on the shelf, written to, waiting on him at review, citable",
       ctx do
    assert tool(ctx, "kind_define", %{
             kind: "field-notes",
             label: "Field notes",
             approvable: true,
             ask: "Read the field notes",
             cites: true,
             note: "for the herons"
           }) =~ "Defined: field-notes"

    file = Path.join(ctx.dir, "field-notes/kind.json")

    assert %{"kind" => "field-notes", "updated_by" => "resident"} =
             Jason.decode!(File.read!(file))

    assert %{kind: "field-notes", user: true} = Kinds.named(ctx.id, "field-notes")
    assert Enum.any?(Seshat.kinds(ctx.id), &(&1.kind == "field-notes"))
    refute Kinds.named("field-notes"), "a kind of hers is never a system kind"

    assert {:ok, %{kind: "field-notes"}} =
             Seshat.write(
               ctx.id,
               "field-notes/herons.md",
               "---\nstatus: review\n---\n# Herons\n\nTwo now.",
               ctx.lily
             )

    assert [%{kind: "piece_to_review", about: %{ask: "Read the field notes"}}] =
             Enum.filter(Brain.needs_you(ctx.id), &(&1.kind == "piece_to_review"))

    assert [%{kind: "field-notes", ref: "herons"}] =
             Citations.extract("as in #{ctx.slug}:field-notes/herons, two now")

    assert tool(ctx, "kind_list", %{}) =~ "field-notes (field-notes/): Field notes"

    # The descriptor's name is never a document's.
    assert {:error, %{site: :seshat_kinds_path_descriptor}} =
             Seshat.write(ctx.id, "field-notes/kind.json", "{}", ctx.lily)
  end

  test "the safe subset: no system folder, no claim of another's writing, no flow out of the house, nothing yet a container",
       ctx do
    refuse = fn attrs, site ->
      assert {:error, %{kind: :seshat_kind_invalid, site: ^site}} =
               Seshat.define_kind(ctx.id, attrs, "a test", ctx.witness)
    end

    refuse.(%{"kind" => "writing"}, :seshat_kinds_user_folder_taken)
    refuse.(%{"kind" => "Dreams"}, :seshat_kinds_user_name)
    refuse.(%{"kind" => "dreams", "folder" => "notes"}, :seshat_kinds_user_folder_taken)
    refuse.(%{"kind" => "dreams", "access" => "witness"}, :seshat_kinds_user_unsafe_claim)
    refuse.(%{"kind" => "dreams", "adoption" => "originals"}, :seshat_kinds_user_unsafe_claim)
    refuse.(%{"kind" => "dreams", "container" => true}, :seshat_kinds_user_not_yet)

    refuse.(
      %{"kind" => "dreams", "approvable" => true, "approval" => %{"then" => "substack_draft"}},
      :seshat_kinds_user_leaves_house
    )

    refute File.exists?(Path.join(ctx.dir, "dreams"))

    # The witness may define one; she sees who did.
    assert {:ok, "dreams"} = Seshat.define_kind(ctx.id, %{"kind" => "dreams"}, nil, ctx.witness)

    assert [%{kind: "dreams", own: true, created_by: "witness"}] =
             Enum.filter(Seshat.user_kinds(ctx.id).kinds, & &1.own)
  end

  test "read back from the repository: a folder's descriptor makes its files adoptable; a bad one is refused and its documents untouched",
       ctx do
    File.mkdir_p!(Path.join(ctx.dir, "dreams"))

    File.write!(
      Path.join(ctx.dir, "dreams/kind.json"),
      Jason.encode!(%{kind: "dreams", label: "Dreams", updated_by: "resident"})
    )

    File.write!(Path.join(ctx.dir, "dreams/the-flood.md"), "# The flood\n\nWater to the sill.")

    File.mkdir_p!(Path.join(ctx.dir, "claims"))

    File.write!(
      Path.join(ctx.dir, "claims/kind.json"),
      Jason.encode!(%{kind: "claims", access: "witness"})
    )

    File.write!(Path.join(ctx.dir, "claims/one.md"), "# One")

    assert {:ok, %{adopted: adopted}} = Seshat.adopt_all(ctx.id, ctx.lily)
    assert "dreams/the-flood.md" in adopted
    refute Enum.any?(adopted, &String.ends_with?(&1, "kind.json"))
    refute Enum.any?(adopted, &String.starts_with?(&1, "claims/"))
    assert File.read!(Path.join(ctx.dir, "claims/one.md")) == "# One"

    assert %{kind: "dreams", label: "Dreams"} = Kinds.named(ctx.id, "dreams")
    refute Kinds.named(ctx.id, "claims")

    assert {:ok, %{loaded: [], refused: [{"claims", "seshat_kinds_user_unsafe_claim"}]}} =
             Seshat.load_kinds(ctx.id, ctx.lily)
  end

  test "a system kind's gate: on at either word, off only by the other's agreement, her proposal waiting on him",
       ctx do
    assert Kinds.approvable?(Kinds.named(ctx.id, "writing"))

    # His proposal to take it off waits on her; he cannot answer his own.
    assert {:ok, :proposed} =
             Seshat.kind_gate(ctx.id, "writing", false, "trust the drafts", ctx.witness)

    assert {:error, %{site: :seshat_kinds_ledger_gate_open}} =
             Seshat.kind_gate(ctx.id, "writing", false, "again", ctx.witness)

    [%{number: n}] = Seshat.user_kinds(ctx.id).proposals

    assert {:error, %{kind: :seshat_kind_gate_invalid}} =
             Seshat.answer_kind_gate(ctx.id, n, true, "mine", ctx.witness)

    assert Kinds.approvable?(Kinds.named(ctx.id, "writing"))
    refute Enum.any?(Brain.needs_you(ctx.id), &(&1.kind == "kind_gate_proposal"))

    assert tool(ctx, "kind_gate_answer", %{number: n, agree: true, note: "fine"}) =~ "Agreed"
    refute Kinds.approvable?(Kinds.named(ctx.id, "writing"))

    # On again at her word alone, at once.
    assert tool(ctx, "kind_gate", %{kind: "writing", approvable: true, note: "back on"}) =~
             "The gate is on"

    assert Kinds.approvable?(Kinds.named(ctx.id, "writing"))

    # Hers to take off waits on him, on his list; he declines.
    assert tool(ctx, "kind_gate", %{kind: "writing", approvable: false, note: "a quiet week"}) =~
             "Proposed"

    assert [%{kind: "kind_gate_proposal", ref: m, screen: "kinds", about: %{kind: "writing"}}] =
             Enum.filter(Brain.needs_you(ctx.id), &(&1.kind == "kind_gate_proposal"))

    assert :ok = Seshat.answer_kind_gate(ctx.id, m, false, "not this week", ctx.witness)
    assert Kinds.approvable?(Kinds.named(ctx.id, "writing"))
    refute Enum.any?(Brain.needs_you(ctx.id), &(&1.kind == "kind_gate_proposal"))

    # Only a system kind with a gate has one to move.
    assert {:error, %{kind: :seshat_kind_gate_invalid}} =
             Seshat.kind_gate(ctx.id, "notes", true, "a test", ctx.witness)
  end
end

defmodule Oneiroi.Seshat.DocumentPostsTest do
  @moduledoc """
  Document posts (seshat#83; design/workspaces.md §3, the witness's
  answers of 2026-11-17): a thread whose trunk cites a household
  document reads as the document at its latest draft; each reply is
  stamped with the draft it answers, and one on an earlier draft says
  so; an edit of the document adds a line to every thread on it saying
  its draft changed; the document names where it is discussed. The
  in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  @doc_path "human/andrew/plan.md"

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, andrew)
    :ok = Gaia.name_witness(witness.id, "Andrew", andrew)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    {:ok,
     andrew: andrew, wren: %{id: id, slug: slug, actor: Actor.new(:resident, id), chat: chat}}
  end

  defp run(name, args, r),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: r.id,
        session_key: r.chat,
        turn_ref: "t",
        resident: r.actor
      })

  test "a document post reads as the document; replies carry their draft; an edit says the draft changed",
       ctx do
    {:ok, _} =
      Seshat.household_post(ctx.andrew, %{
        "kind" => "human",
        "path" => @doc_path,
        "title" => "The plan",
        "content" => "Draft one."
      })

    # Before any post, the document says where feedback goes.
    assert run("household_read", %{path: @doc_path}, ctx.wren) =~ "No document post on it yet"

    assert {:ok, %{path: thread, doc: @doc_path, doc_commit: first}} =
             Seshat.household_post(ctx.andrew, %{"doc" => @doc_path, "content" => "Thoughts?"})

    assert {:ok, %{title: "On The plan", doc: %{commit: ^first, content: "Draft one." <> _}}} =
             Seshat.household_read(ctx.wren.actor, thread)

    read = run("household_read", %{path: thread}, ctx.wren)
    assert read =~ "A document post on #{@doc_path}, draft #{String.slice(first, 0, 12)}."
    assert read =~ "Draft one."
    assert run("household_read", %{path: @doc_path}, ctx.wren) =~ "Discussed in #{thread}"

    # The next beat he replies, stamped with the draft he read.
    Clock.Fake.advance(86_400)
    {:ok, _} = Seshat.household_reply(ctx.andrew, thread, %{"content" => "Shorter, maybe."})

    # And the beat after, he takes his own advice.
    Clock.Fake.advance(86_400)

    assert {:ok, %{commit: second}} =
             Seshat.household_edit(ctx.andrew, @doc_path, %{"content" => "Draft two."})

    assert {:ok, %{doc: %{commit: ^second, content: "Draft two." <> _}, replies: replies}} =
             Seshat.household_read(ctx.wren.actor, thread)

    assert [%{meta: %{"doc_commit" => ^first}}, %{meta: %{"draft" => "changed"} = line} = changed] =
             replies

    assert line["doc_commit"] == second

    assert changed.body =~
             "Draft changed: #{String.slice(first, 0, 12)} → #{String.slice(second, 0, 12)}."

    read = run("household_read", %{path: thread}, ctx.wren)
    assert read =~ "on an earlier draft (#{String.slice(first, 0, 12)})"
    assert read =~ "Draft two."
    refute read =~ "Draft one."
  end

  test "a document post needs a document; a thread is not one", ctx do
    assert {:error, %{kind: :seshat_household_no_such_document}} =
             Seshat.household_post(ctx.andrew, %{"doc" => "human/andrew/none.md"})

    {:ok, t} = Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "Hi."})

    assert {:error, %{kind: :seshat_household_invalid}} =
             Seshat.household_post(ctx.andrew, %{"doc" => t.path <> "/trunk.md"})
  end

  test "a resident's draft shared from her own records names its source, and her read of it names the talk",
       ctx do
    {:ok, _} = Seshat.write(ctx.wren.id, "writing/essay.md", "My essay.\n", ctx.wren.actor)

    # Her post waits on her turn in the house; the source is read first,
    # so a missing one is said before the beats are.
    assert {:error, %{kind: :seshat_household_no_such_document}} =
             Seshat.household_post(ctx.wren.actor, %{
               "kind" => "design",
               "path" => "design/essay.md",
               "from" => "writing/none.md"
             })

    assert {:error, %{kind: :seshat_household_invalid}} =
             Seshat.household_post(ctx.andrew, %{
               "kind" => "human",
               "path" => "human/andrew/essay.md",
               "from" => "writing/essay.md"
             })

    assert Seshat.household_shared_from(ctx.wren.actor, "writing/essay.md") == []
  end
end

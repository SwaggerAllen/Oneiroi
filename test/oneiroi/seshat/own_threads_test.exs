defmodule Oneiroi.Seshat.OwnThreadsTest do
  @moduledoc """
  A resident's own threads (seshat#106 to #108; design/document-threads.md,
  the witness's rulings of 2026-11-23): the house's thread layout in her
  own repository, written and read by her and her witness alone; a
  document has one thread there; her witness's words wake her chat with a
  letter naming the thread, never the words; her own tools reach it with
  space: mine, asking no audience. The in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian.Repos

  @doc_path "design/plan.md"

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, andrew)
    wren = Actor.new(:resident, id)
    {:ok, _} = Seshat.write(id, @doc_path, "---\ntitle: The plan\n---\n\nDraft one.\n", wren)

    stranger = Actor.new(:witness, Fixtures.account!().id)

    {:ok, andrew: andrew, stranger: stranger, wren: %{id: id, actor: wren, chat: chat}}
  end

  defp run(name, args, r),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: r.id,
        session_key: r.chat,
        turn_ref: "t",
        resident: r.actor
      })

  defp pokes(r),
    do: Enum.filter(Kumbukumbu.letters(r.id), &(&1.from_name == Kumbukumbu.threads_sender()))

  test "a document has one thread in her space, in her repository, and his words wake her",
       ctx do
    assert {:ok, %{path: thread, doc: @doc_path}} =
             Seshat.thread_post(ctx.andrew, ctx.wren.id, %{
               "doc" => @doc_path,
               "content" => "Is the second half needed?"
             })

    # In her repository, the house's layout.
    {:ok, files} = Repos.snapshot({:resident, ctx.wren.id})
    assert Map.has_key?(files, thread <> "/trunk.md")
    assert Map.has_key?(files, "threads/kind.json")

    # His post wakes her chat, naming the thread, never the words.
    assert [letter] = pokes(ctx.wren)
    assert letter.text =~ thread
    refute letter.text =~ "second half"

    # Posting on the document again answers its thread; words are a reply.
    assert {:ok, %{path: ^thread, existing: true, reply: 1}} =
             Seshat.thread_post(ctx.andrew, ctx.wren.id, %{
               "doc" => @doc_path,
               "content" => "Or cut it."
             })

    assert {:ok, %{path: ^thread}} =
             Seshat.thread_for_document(ctx.andrew, ctx.wren.id, @doc_path)

    # She answers from her chat, with her own tools; her reply wakes nobody.
    assert run("household_reply", %{space: "mine", thread: thread, content: "Cut it."}, ctx.wren) =~
             "reply #2"

    assert length(pokes(ctx.wren)) == 2

    read = run("household_read", %{space: "mine", path: thread}, ctx.wren)
    assert read =~ "Is the second half needed?"
    assert read =~ "Cut it."
    assert read =~ "Draft one."

    assert run("household_read", %{space: "mine"}, ctx.wren) =~ "#{thread}: \"On #{@doc_path}\""

    assert {:ok, %{replies: [_, %{meta: %{"by_kind" => "resident", "doc_commit" => _}}]}} =
             Seshat.thread_read(ctx.andrew, ctx.wren.id, thread)
  end

  test "her threads are hers and her witness's alone", ctx do
    {:ok, %{path: thread}} =
      Seshat.thread_post(ctx.wren.actor, ctx.wren.id, %{"title" => "Mine", "content" => "Hello."})

    assert pokes(ctx.wren) == []

    assert {:error, %{kind: :seshat_threads_not_party}} =
             Seshat.thread_read(ctx.stranger, ctx.wren.id, thread)

    assert {:error, %{kind: :seshat_threads_not_party}} =
             Seshat.thread_reply(ctx.stranger, ctx.wren.id, thread, %{"content" => "hi"})

    other = Actor.new(:resident, Ecto.UUID.generate())

    assert {:error, %{kind: :seshat_threads_not_party}} =
             Seshat.threads(other, ctx.wren.id)

    # A thread is no document to post on, and a missing file is none either.
    assert {:error, %{kind: :seshat_threads_no_document}} =
             Seshat.thread_post(ctx.andrew, ctx.wren.id, %{"doc" => thread <> "/trunk.md"})

    assert {:error, %{kind: :seshat_threads_no_document}} =
             Seshat.thread_post(ctx.andrew, ctx.wren.id, %{"doc" => "design/absent.md"})
  end
end

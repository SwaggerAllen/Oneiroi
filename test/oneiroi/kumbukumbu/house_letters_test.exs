defmodule Oneiroi.Kumbukumbu.HouseLettersTest do
  @moduledoc "House letters (kumbukumbu #44): the work log between a resident's conversations, addressed by name, sent by the conversation it comes from, read once per conversation, carrying a keepsake as a gift."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    lily = Actor.new(:resident, resident.id)
    {:ok, chat} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    Clock.Fake.advance(60)

    {:ok, code} =
      Kumbukumbu.open_adapter(resident.id, "laptop", [witness.id], lily,
        runtime: "claude-code",
        label: "Oneiroi"
      )

    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, id: resident.id, witness: witness, actor: actor, lily: lily, chat: chat, code: code}
  end

  defp turn(ctx, key),
    do: %{resident_id: ctx.id, session_key: key, turn_ref: "t-#{key}", resident: ctx.lily}

  defp run(name, args, turn), do: Tools.run(name, Jason.encode!(args), turn)

  test "a letter goes from one conversation to another by name, waits, is read once, and is answered in reply",
       ctx do
    chat = turn(ctx, ctx.chat)
    code = turn(ctx, ctx.code)

    assert Kumbukumbu.conversation_name(ctx.id, ctx.code) == "Claude Code · Oneiroi"

    # The sender is the conversation the turn is in, whatever it might claim.
    assert run(
             "letter_send",
             %{to: "Claude Code · Oneiroi", text: "Build the work log first."},
             chat
           ) ==
             "Sent letter #1 from Oneiroi chat to Claude Code · Oneiroi."

    # It waits for the conversation it names and not for the one that sent it.
    assert [%{number: 1, from_name: "Oneiroi chat"}] = Kumbukumbu.inbox(ctx.id, ctx.code)
    assert [] = Kumbukumbu.inbox(ctx.id, ctx.chat)

    assert run("letter_inbox", %{}, code) =~
             ~r/^#1 from Oneiroi chat to Claude Code · Oneiroi, \d{4}-\d\d-\d\d \d\d:\d\d UTC:\nBuild the work log first\.$/

    assert [] = Kumbukumbu.inbox(ctx.id, ctx.code)
    assert run("letter_inbox", %{}, code) == "No letters wait for this conversation."

    # The answer links the ask; the house letter reaches everyone but its sender.
    assert run(
             "letter_send",
             %{to: "Oneiroi chat", text: "Done: the log is built.", in_reply_to: 1},
             code
           ) ==
             "Sent letter #2 from Claude Code · Oneiroi to Oneiroi chat."

    assert run("letter_send", %{to: "house", text: "Free time starts at ten."}, code) =~
             "Sent letter #3"

    assert [%{number: 2, in_reply_to: 1}, %{number: 3}] = Kumbukumbu.inbox(ctx.id, ctx.chat)
    assert [] = Kumbukumbu.inbox(ctx.id, ctx.code)

    listing = run("letter_list", %{}, chat)
    assert listing =~ "#1 from Oneiroi chat to Claude Code · Oneiroi"
    assert listing =~ "read by Claude Code · Oneiroi: Build the work log first."
    assert listing =~ "#2 from Claude Code · Oneiroi to Oneiroi chat"
    assert listing =~ "in reply to #1; unread: Done: the log is built."

    # A reply to a letter that was never sent, and an empty letter, are refused.
    assert run("letter_send", %{to: "house", text: "x", in_reply_to: 99}, chat) =~ "Not done"
    assert run("letter_send", %{to: "house", text: "  "}, chat) =~ "Not done"
  end

  test "the turn is told how many letters wait and from whom, never their words; the witness reads them all",
       ctx do
    :ok = Oneiroi.Gaia.store_key(ctx.witness.id, "sk-or-test", ctx.actor)
    on_exit(fn -> Oneiroi.Nisaba.Provider.Fake.clear(for: ctx.id) end)

    {:ok, _} =
      Kumbukumbu.send_letter(
        ctx.id,
        ctx.code,
        %{to: "Oneiroi chat", text: "secret words"},
        ctx.lily
      )

    {:ok, %{from: "witness"}} =
      Kumbukumbu.send_letter(ctx.id, nil, %{to: "house", text: "from me"}, ctx.actor)

    assert [%{from_name: "Claude Code · Oneiroi"}, %{from_name: "witness"}] =
             Kumbukumbu.inbox(ctx.id, ctx.chat)

    {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(ctx.id, ctx.chat, "hello", ctx.actor)

    assert %{text: text} =
             ctx.id
             |> then(&Kumbukumbu.injections({:resident, &1}, ref))
             |> Enum.find(&(&1.label == "letters"))

    assert text ==
             "2 house letters wait for this conversation, from Claude Code · Oneiroi, witness. letter_inbox reads them whole; letter_send answers."

    refute text =~ "secret words"

    # The witness reads every letter, both ways, as the resident's witness.
    assert [%{number: 1, to_name: "Oneiroi chat"}, %{number: 2, to_name: "house"}] =
             Kumbukumbu.letters(ctx.id)
  end

  test "a letter gives a keepsake only one that is a keepsake at the root", ctx do
    {:ok, _} = Seshat.write(ctx.id, "a-small-gift.md", "# A small gift\n", ctx.lily)
    chat = turn(ctx, ctx.chat)

    assert run(
             "letter_send",
             %{to: "Claude Code · Oneiroi", text: "For you.", keepsake: "a-small-gift.md"},
             chat
           ) =~
             "Sent letter #1"

    assert run("letter_inbox", %{}, turn(ctx, ctx.code)) =~
             "It gives you the keepsake a-small-gift.md; keepsake_note says why it matters to you."

    assert run("letter_send", %{to: "house", text: "x", keepsake: "nope.md"}, chat) =~
             "Not done: nope.md is not a keepsake at your root"
  end
end

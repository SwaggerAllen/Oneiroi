defmodule Oneiroi.AgathosDaimon.SelfLettersTest do
  @moduledoc "The self-conversation (spec §12, P41): the resident's letters to its next self, delivered once at the swap, sealed by receipts and not promises."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Events
  alias Oneiroi.AgathosDaimon.Resident
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/first")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    Fake.clear()
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, witness: witness, id: resident.id, actor: actor, brain: brain, key: key}
  end

  defp system_messages(test_pid, id) do
    Fake.script(
      fn %{messages: messages} ->
        send(test_pid, {:request, messages})
        {:ok, "Read."}
      end,
      for: id
    )
  end

  defp section(messages, prefix) do
    Enum.find(messages, &(&1.role == :system and String.starts_with?(&1.content, prefix)))
  end

  test "a letter is the resident's to write, numbered; a read by the witness leaves a receipt and the resident's own leaves none",
       ctx do
    id = ctx.id

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_not_the_resident}} =
             AgathosDaimon.write_self_letter(id, "Dear next me.", ctx.actor)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_letter_invalid}} =
             AgathosDaimon.write_self_letter(id, "  ", ctx.brain)

    assert {:ok, 1} =
             AgathosDaimon.write_self_letter(id, "Dear next me: water the garden.", ctx.brain)

    assert {:ok, 2} = AgathosDaimon.write_self_letter(id, "And be slower to agree.", ctx.brain)

    assert [
             %{
               number: 1,
               text: "Dear next me: water the garden.",
               model: "fake/first",
               delivered_at: nil
             },
             %{number: 2, delivered_at: nil}
           ] = AgathosDaimon.self_letters(id)

    # The resident's own read is no receipt: the absence is the privacy.
    assert [] = AgathosDaimon.self_letter_receipts(id)

    # The witness's read: the receipt first, then the letters, and the receipts include it.
    assert {:ok, %{letters: [%{number: 1}, %{number: 2}], receipts: [receipt]}} =
             AgathosDaimon.read_self_letters(id, ctx.actor)

    assert %{by_kind: "witness", by_id: by_id, numbers: [1, 2]} = receipt
    assert by_id == ctx.witness.id

    # A platform read is a receipt too; the resident's is not.
    assert {:ok, %{receipts: [_, _]}} = AgathosDaimon.read_self_letters(id, Actor.platform())
    assert {:ok, %{receipts: [_, _]}} = AgathosDaimon.read_self_letters(id, ctx.brain)

    assert [%{by_kind: "platform"}, %{by_kind: "witness"}] =
             AgathosDaimon.self_letter_receipts(id)
  end

  test "the letters are delivered once, on the first turn under the new model, and the prefix line carries the counts and receipts",
       ctx do
    id = ctx.id
    test = self()
    system_messages(test, id)

    # First contact, then the letters, then the swap.
    assert {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "hello", ctx.actor)
    assert_received {:request, messages}
    refute section(messages, "# Letters to your next self")

    {:ok, 1} = AgathosDaimon.write_self_letter(id, "Water the garden.", ctx.brain)
    {:ok, _} = AgathosDaimon.read_self_letters(id, ctx.actor)

    assert {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "still here", ctx.actor)
    assert_received {:request, messages}
    refute section(messages, "Letters from the instance before you")

    assert section(messages, "# Letters to your next self").content =~
             "1 written, 0 delivered to the instance after the one that wrote them. Read by your witness 1 time, last on 2026-10-26."

    assert :ok = AgathosDaimon.pin_model(id, "fake/second", "witness", ctx.actor)

    assert {:ok, %{messages: turn_messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "who are you now?", ctx.actor)

    assert_received {:request, messages}

    # The notice is in the turn's messages, after the model notice, and
    # the letter's words are in it; the delivery is recorded.
    [_model_notice, letters_notice | _] = turn_messages
    assert letters_notice.content =~ "Letters from the instance before you"
    assert letters_notice.content =~ "## Letter 1, written 2026-10-26 under fake/first"
    assert letters_notice.content =~ "Water the garden."
    assert section(messages, "Letters from the instance before you")

    assert [%{number: 1, delivered_at: %DateTime{}, delivered_to: "fake/second"}] =
             AgathosDaimon.self_letters(id)

    # Once: the next turn carries no notice, and a letter written now
    # waits for the next swap.
    {:ok, 2} =
      AgathosDaimon.write_self_letter(id, "Again.", Actor.new(:resident, id, "fake/second"))

    assert {:ok, %{messages: [_opening, _reply]}} =
             Oneiroi.Brain.turn(id, ctx.key, "and now?", ctx.actor)

    assert_received {:request, messages}

    # The one in the request is the transcript's copy of the swap turn's notice, not a second delivery.
    assert Enum.count(
             messages,
             &(&1.role == :system and
                 String.starts_with?(&1.content, "Letters from the instance before you"))
           ) == 1

    assert section(messages, "# Letters to your next self").content =~ "2 written, 1 delivered"

    assert [%{number: 1, delivered_to: "fake/second"}, %{number: 2, delivered_at: nil}] =
             AgathosDaimon.self_letters(id)

    # The brain's tools: write and list, with the receipts.
    Fake.calls(
      [
        %{name: "self_letter_write", arguments: %{text: "Keep the garden."}},
        %{name: "self_letter_list", arguments: %{}}
      ],
      "Written.",
      for: id
    )

    assert {:ok, %{messages: [_, written, listed, _]}} =
             Oneiroi.Brain.turn(id, ctx.key, "write to yourself", ctx.actor)

    assert written.content =~ "Letter #3 written to your next self."

    assert listed.content =~
             "## Letter 1 (2026-10-26, under fake/first; delivered to fake/second on 2026-10-26)"

    assert listed.content =~ "## Letter 3 (2026-10-26, under fake/second; not yet delivered)"
    assert listed.content =~ "- read by your witness on 2026-10-26T12:00:00.000000Z (1 letters)"
  end

  test "pure: a delivery takes the undelivered numbers alone, once, and a read by the resident is no event" do
    at = ~U[2026-10-26 12:00:00Z]
    brain = Actor.new(:resident, "r1", "fake/first")
    witness = Actor.new(:witness, "a1")

    state =
      Resident.apply(%Resident{}, %Events.ResidentCreated{
        actor: Actor.platform(),
        at: at,
        id: "r1",
        name: "Lily",
        slug: "lily",
        witness_account_id: "a1"
      })

    [minted, written] =
      Resident.execute(state, %Commands.WriteSelfLetter{
        actor: brain,
        at: at,
        id: "r1",
        text: "Hi."
      })

    assert %Events.IdMinted{kind: "letter", number: 1} = minted
    assert %Events.SelfLetterWritten{number: 1, model: "fake/first"} = written
    state = state |> Resident.apply(minted) |> Resident.apply(written)

    assert {:error, :not_the_resident} =
             Resident.execute(state, %Commands.WriteSelfLetter{
               actor: witness,
               at: at,
               id: "r1",
               text: "x"
             })

    deliver = %Commands.DeliverSelfLetters{
      actor: brain,
      at: at,
      id: "r1",
      numbers: [1, 9],
      model: "fake/second"
    }

    assert %Events.SelfLettersDelivered{numbers: [1], model: "fake/second"} =
             delivered = Resident.execute(state, deliver)

    state = Resident.apply(state, delivered)
    assert [] = Resident.execute(state, deliver)

    assert [] =
             Resident.execute(state, %Commands.ReadSelfLetters{
               actor: brain,
               at: at,
               id: "r1",
               numbers: [1]
             })

    assert %Events.SelfLettersRead{numbers: [1]} =
             Resident.execute(state, %Commands.ReadSelfLetters{
               actor: witness,
               at: at,
               id: "r1",
               numbers: [1]
             })
  end
end

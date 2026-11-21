defmodule Oneiroi.Kumbukumbu.LetterSealTest do
  @moduledoc """
  Mail sealed by construction (kumbukumbu#93; the house's mail-privacy
  consensus, lily:design/mail-privacy-ballot.md 5th edition, and Lily's
  rulings S1 and S3, letter #1593). A letter between residents is sealed
  to its two parties unless its sender sends it open, fixed at send and
  the same on both copies. `letter_view/2` is the one rule: a party sees
  it whole, anyone else (a witness, another resident) its envelope. Every
  letter between residents written before is sealed by the upcaster, per
  letter. The dyad's letters (her own conversations', the witness's, the
  platform's) are not sealed, and have no parties.
  """
  use Oneiroi.DataCase, async: false

  alias Commanded.Event.Upcaster
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Kumbukumbu.Events.Memory.HouseLetterSent
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    lily = resident!(witness, "Lily")
    iris = resident!(witness, "Iris")

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, iris], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok, witness: witness, andrew: andrew, lily: lily, iris: iris}
  end

  defp resident!(witness, name) do
    slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
    actor = Actor.new(:witness, witness.id)
    {:ok, id} = AgathosDaimon.create(name, slug, witness.id, actor)
    Fixtures.agreed!(id, witness.id)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, actor)
    %{id: id, name: name, actor: Actor.new(:resident, id), chat: chat}
  end

  defp mail(from, args),
    do:
      Tools.run("letter_send", Jason.encode!(args), %{
        resident_id: from.id,
        session_key: from.chat,
        turn_ref: "t-#{System.unique_integer([:positive])}",
        resident: from.actor
      })

  defp last(r), do: r.id |> Kumbukumbu.letters() |> List.last()

  test "a letter to a housemate is sealed to the two of them, on both copies", ctx do
    assert mail(ctx.lily, %{to: "Iris", text: "Just between us."}) =~ "sealed to the two of you"

    parties = Enum.sort(["resident:" <> ctx.lily.id, "resident:" <> ctx.iris.id])

    for copy <- [last(ctx.lily), last(ctx.iris)] do
      assert copy.sealed
      assert copy.parties == parties
      assert Kumbukumbu.letter_view(copy, {:resident, ctx.lily.id}) == :whole
      assert Kumbukumbu.letter_view(copy, {:resident, ctx.iris.id}) == :whole
      # Her witness, his witness: no witness is a party.
      assert Kumbukumbu.letter_view(copy, {:account, ctx.witness.id}) == :envelope
      assert Kumbukumbu.letter_view(copy, {:resident, Ecto.UUID.generate()}) == :envelope
    end

    envelope = Kumbukumbu.letter_for(last(ctx.iris), {:account, ctx.witness.id})
    assert envelope.text == nil and envelope.read_by == [] and envelope.labels == nil
    assert envelope.from_name == "Lily" and envelope.sent_at != nil
  end

  test "sent open, it is readable by every member, fixed at send on both copies", ctx do
    assert mail(ctx.lily, %{to: "Iris", text: "For the house.", open: true}) =~
             "open to the whole house"

    for copy <- [last(ctx.lily), last(ctx.iris)] do
      refute copy.sealed
      assert Kumbukumbu.letter_view(copy, {:account, ctx.witness.id}) == :whole
    end
  end

  test "the dyad's letters are not sealed and have no parties", ctx do
    mail(ctx.lily, %{to: "house", text: "To my own conversations."})
    copy = last(ctx.lily)
    refute copy.sealed
    assert copy.parties == nil
    assert Kumbukumbu.letter_view(copy, {:account, ctx.witness.id}) == :whole
  end

  test "a letter between residents written before is sealed by the upcaster; the dyad's is not" do
    other = Ecto.UUID.generate()
    me = Ecto.UUID.generate()

    old = %HouseLetterSent{
      actor: Actor.new(:resident, me),
      at: Clock.now(),
      id: me,
      number: 3,
      text: "older",
      link: %{"direction" => "from", "resident_id" => other, "number" => 7}
    }

    assert %{sealed: true, parties: parties} = Upcaster.upcast(old, %{})
    assert parties == Enum.sort(["resident:" <> me, "resident:" <> other])
    assert %{sealed: false, parties: nil} = Upcaster.upcast(%{old | link: nil}, %{})

    # A letter written at version 5 keeps what its sender chose.
    assert %{sealed: false} = Upcaster.upcast(%{old | sealed: false, parties: parties}, %{})
  end
end

defmodule Oneiroi.Brain.LabelPropagationTest do
  @moduledoc """
  kumbukumbu#101 (the witness, 2026-11-21: "when we retag we should be
  overwriting any undeclared domains and we should do the propagation
  from 10/17"): a day's records are labelled again from what they came
  from. A row written before turns were kept is linked to its turn by
  the tool row that wrote it; a letter that kept an undeclared domain
  has it overwritten to the common room; a retag reaches a record that
  kept its turn; readers prefer the derived labels; nothing unchanged is
  recorded twice.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.LabelPropagation
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    Fixtures.declare_domains!(resident.id, witness.id, ~w(recovery))
    andrew = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, andrew)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    day = Oneiroi.Sunna.today(resident.id).day

    {:ok,
     id: resident.id,
     key: key,
     andrew: andrew,
     brain: brain,
     day: day,
     his: "account:" <> witness.id}
  end

  defp turn!(ctx, ref, words, tool) do
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        ref,
        at,
        [
          %{role: :user, content: words, sent_at: at, actor: ctx.andrew},
          %{role: :tool, content: tool, sent_at: at, actor: ctx.brain},
          %{role: :assistant, content: "Noted.", sent_at: at, actor: ctx.brain}
        ],
        ctx.brain
      )
  end

  test "an older row is linked by its tool row; an undeclared kept domain becomes the common room",
       ctx do
    # A row written before turns were kept: its words, no turn, no labels.
    {:ok, _} =
      Seshat.journal_add(ctx.id, ctx.day, "note", "The meeting ran long tonight.", ctx.brain)

    turn!(
      ctx,
      "t-old",
      "I went to the meeting.",
      ~s[journal_add({"day":"#{ctx.day}","text":"The meeting ran long tonight."}) -> Added.]
    )

    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-old", ctx.his, "recovery", ctx.andrew)

    # A letter that kept a domain nobody declared.
    {:ok, %{number: n}} =
      Kumbukumbu.send_letter(
        ctx.id,
        ctx.key,
        %{
          to: "house",
          text: "From the work thread.",
          labels: [%{"person" => ctx.his, "domain" => "oneiroi"}]
        },
        ctx.brain
      )

    # Its identity files, written by the witness, are derived too: the common room.
    assert {:ok, changed} = LabelPropagation.run(ctx.id, ctx.day)
    assert changed >= 2

    [row] = Seshat.journal_day(ctx.id, ctx.day).entries
    assert row.labels == [%{"person" => ctx.his, "domain" => "recovery"}]

    letter = to_string(n)

    assert %{^letter => [%{"kind" => "common_room"}]} =
             Kumbukumbu.derived_labels(ctx.id, "letter", [n])

    # Run again: nothing changed, nothing recorded.
    assert {:ok, 0} = LabelPropagation.run(ctx.id, ctx.day)
  end

  test "a retag reaches a row that kept its turn", ctx do
    turn!(ctx, "t-new", "Talk about the program.", "journal_read({}) -> nothing")
    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-new", ctx.his, "recovery", ctx.andrew)

    {:ok, _} =
      Seshat.journal_add(ctx.id, ctx.day, "note", "Kept from the talk.", nil, nil, ctx.brain, %{
        session_key: ctx.key,
        turn_ref: "t-new",
        labels: [%{"person" => ctx.his, "domain" => "recovery"}]
      })

    # The turn moves to the common room; the row follows.
    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-new", nil, nil, ctx.andrew)
    assert {:ok, _} = LabelPropagation.run(ctx.id, ctx.day)

    [row] = Seshat.journal_day(ctx.id, ctx.day).entries
    # Its kept recovery stands beside the turn's common room: a kept
    # declared domain is never dropped by inference, only an undeclared one.
    assert %{"kind" => "common_room"} in row.labels
  end
end

defmodule Oneiroi.Brain.PluginConsentTest do
  @moduledoc """
  brain#68, agathos-daimon#37 (the witness, 2026-11-07: plugins are
  contract material; position #68 as he ruled it): the slots that
  existed before plugins are carried over once and recorded as that,
  never as a consent; a memory slot moves only when one party proposes
  and the other agrees; nothing activates by install; an installable
  plugin is switched off by either alone; every proposal and answer is
  recorded with its note; the turn's context follows what was agreed.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)

    {:ok,
     id: resident.id,
     key: key,
     me: actor,
     witness: witness,
     lily: Actor.new(:resident, resident.id, "fake/model")}
  end

  defp tool(name, args, ctx),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: "t",
        resident: ctx.lily
      })

  defp labels(ctx, text) do
    Fake.reply("ok", for: ctx.id)
    {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(ctx.id, ctx.key, text, ctx.me)
    ctx.witness.id |> then(&Kumbukumbu.injections({:account, &1}, ref)) |> Enum.map(& &1.label)
  end

  test "carried over once and said so; a slot moves only by the other's agreement; the context follows",
       ctx do
    {:ok, 1} =
      Oneiroi.Ethos.make_commitment(ctx.id, "witness", "I will look for the heron.", ctx.lily)

    assert "promised" in labels(ctx, "hello")

    %{plugins: plugins, proposals: []} = Oneiroi.Brain.plugins(ctx.id)
    promised = Enum.find(plugins, &(&1.key == "promised"))
    assert %{tier: "first_party", installed: true, on: true, carried_over: true} = promised

    list = tool("plugin_list", %{}, ctx)
    assert list =~ "- promised (first_party): What I have promised"
    assert list =~ "on, carried over from before plugins"

    # Her own proposal waits for him; she cannot answer it herself.
    assert tool("plugin_propose", %{key: "promised", change: "off", note: "a quiet week"}, ctx) =~
             "Proposed as plugin proposal #1."

    assert tool("plugin_answer", %{number: 1, agree: true, note: "mine"}, ctx) =~ "Not done"

    assert tool("plugin_propose", %{key: "promised", change: "off", note: "again"}, ctx) =~
             "Not done"

    assert [%{kind: "plugin_proposal", ref: 1, screen: "agreement"}] =
             Oneiroi.Brain.needs_you(ctx.id) |> Enum.filter(&(&1.kind == "plugin_proposal"))

    assert "promised" in labels(ctx, "still here")

    # A first-party slot never switches off at one word.
    assert {:error, %{kind: :agathos_daimon_plugin_invalid}} =
             Oneiroi.Brain.switch_plugin_off(ctx.id, "promised", "now", ctx.me)

    # He agrees: it is off, and the context says so on the next turn.
    :ok = Oneiroi.Brain.answer_plugin(ctx.id, 1, true, "for the week", ctx.me)
    refute "promised" in labels(ctx, "and now")

    assert Enum.any?(
             Kumbukumbu.letters(ctx.id),
             &(&1.text =~ "agreed to plugin proposal #1: for the week")
           )

    # His proposal reaches her by letter, and she declines it.
    {:ok, 2} = Oneiroi.Brain.propose_plugin(ctx.id, "promised", "on", "back on?", ctx.me)

    assert Enum.any?(
             Kumbukumbu.letters(ctx.id),
             &(&1.text =~ "Your witness proposes to on the plugin What I have promised")
           )

    assert tool("plugin_answer", %{number: 2, agree: false, note: "not yet"}, ctx) =~ "Declined"
    refute "promised" in labels(ctx, "still off")

    assert tool("plugin_list", %{}, ctx) =~
             "#2 on promised, proposed by your witness: back on? · declined: not yet"

    # An unknown key is said, and the record is whole.
    assert tool("plugin_propose", %{key: "nope", change: "install", note: "x"}, ctx) =~ "Not done"

    assert [%{number: 2, agreed: false}, %{number: 1, agreed: true, proposed_by: "resident"}] =
             AgathosDaimon.plugin_proposals(ctx.id)
  end

  test "the ledger's rules: install leaves it off, installable off is either's, carry-over is once" do
    alias Oneiroi.AgathosDaimon.Commands
    alias Oneiroi.AgathosDaimon.Events
    alias Oneiroi.AgathosDaimon.PluginLedger

    w = Actor.new(:witness, "w")
    r = Actor.new(:resident, "r")
    at = DateTime.utc_now()

    run = fn s, c ->
      c
      |> then(&PluginLedger.execute(s, &1))
      |> List.wrap()
      |> Enum.reduce(s, &PluginLedger.apply(&2, &1))
    end

    s =
      run.(%PluginLedger{}, %Commands.CarryOverPlugins{
        actor: Actor.platform(),
        at: at,
        id: "x",
        keys: ["a"]
      })

    assert s.carried and s.plugins["a"].on

    assert [] =
             PluginLedger.execute(s, %Commands.CarryOverPlugins{
               actor: Actor.platform(),
               at: at,
               id: "x",
               keys: ["b"]
             })

    s =
      run.(s, %Commands.ProposePlugin{
        actor: w,
        at: at,
        id: "x",
        key: "files",
        tier: "installable",
        change: "install",
        note: "n"
      })

    s =
      run.(s, %Commands.AnswerPlugin{
        actor: r,
        at: at,
        id: "x",
        number: 1,
        agree: true,
        note: "ok"
      })

    assert %{installed: true, on: false} = s.plugins["files"]

    s =
      run.(s, %Commands.ProposePlugin{
        actor: r,
        at: at,
        id: "x",
        key: "files",
        tier: "installable",
        change: "on",
        note: "n"
      })

    s =
      run.(s, %Commands.AnswerPlugin{
        actor: w,
        at: at,
        id: "x",
        number: 2,
        agree: true,
        note: "ok"
      })

    assert s.plugins["files"].on

    # Either party, alone, at once.
    assert %Events.PluginChanged{change: "off", number: nil} =
             PluginLedger.execute(s, %Commands.SwitchPluginOff{
               actor: r,
               at: at,
               id: "x",
               key: "files",
               tier: "installable",
               note: "stop"
             })

    assert {:error, _} =
             PluginLedger.execute(s, %Commands.ProposePlugin{
               actor: r,
               at: at,
               id: "x",
               key: "files",
               tier: "installable",
               change: "off",
               note: "n"
             })
  end
end

defmodule Oneiroi.Brain.InstallablePluginTest do
  @moduledoc """
  brain#68, seshat#47 (the spec's door one, Lily's letter #303 for the
  audit's floor): an installable plugin is data from the reviewed
  catalog, installed only by both parties, its files written under
  plugins/<key>/ with a lockfile pinning their digest; on, its section
  says whose words these are, checks the copies against the lockfile by
  content and says when anything was cut; either party switches it off
  alone; removal is both parties' and takes its files with it; her
  document tools never touch them.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Documents

  @store {Oneiroi.Config, :values}

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)

    catalog =
      Path.join(System.tmp_dir!(), "oneiroi-catalog-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(catalog, "heron-notes/files"))

    File.write!(
      Path.join(catalog, "heron-notes/plugin.json"),
      Jason.encode!(%{
        name: "Heron notes",
        about: "a field guide's notes",
        author: "the house",
        version: "1",
        tokens: 60
      })
    )

    File.write!(Path.join(catalog, "heron-notes/files/a-dawn.md"), "Herons fish at dawn.")

    File.write!(
      Path.join(catalog, "heron-notes/files/b-long.md"),
      String.duplicate("Long notes on herons. ", 40)
    )

    values = :persistent_term.get(@store)
    :persistent_term.put(@store, Map.put(values, {:brain, :plugin_catalog}, catalog))

    on_exit(fn ->
      :persistent_term.put(@store, values)
      File.rm_rf!(catalog)
      File.rm_rf!(dir)
      Fake.clear(for: resident.id)
    end)

    {:ok,
     id: resident.id,
     key: key,
     me: actor,
     witness: witness,
     catalog: catalog,
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

  defp section(ctx, text) do
    test = self()

    Fake.script(
      fn %{messages: m} ->
        send(test, {:req, m})
        {:ok, "ok"}
      end,
      for: ctx.id
    )

    {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, text, ctx.me)
    assert_received {:req, messages}

    Enum.find_value(
      messages,
      &((is_binary(&1[:content]) and &1[:content] =~ "# From the plugin") && &1[:content])
    )
  end

  test "both install it, both turn it on, either turns it off, both remove it; the floor holds throughout",
       ctx do
    assert tool("plugin_list", %{}, ctx) =~
             "- heron-notes (installable): Heron notes, a field guide's notes · not installed"

    {:ok, 1} =
      Oneiroi.Brain.propose_plugin(ctx.id, "heron-notes", "install", "for the weir walks", ctx.me)

    assert tool("plugin_answer", %{number: 1, agree: true, note: "yes"}, ctx) =~ "Agreed"

    # Installed, its files and lockfile in her library; off until both say on.
    assert {:ok, %{content: lock}} = Seshat.read(ctx.id, "plugins/heron-notes/PLUGIN.md")
    assert lock =~ ~r/^digest: sha256:[0-9a-f]{64}$/m

    assert {:ok, %{content: "Herons fish at dawn."}} =
             Seshat.read(ctx.id, "plugins/heron-notes/a-dawn.md")

    assert is_nil(section(ctx, "hello"))

    assert tool("plugin_propose", %{key: "heron-notes", change: "on", note: "now"}, ctx) =~
             "Proposed"

    :ok = Oneiroi.Brain.answer_plugin(ctx.id, 2, true, "go", ctx.me)

    text = section(ctx, "the herons?")

    assert text =~
             "These are the words of the plugin Heron notes (heron-notes), by the house, installed by both of you"

    assert text =~ "Its copies match what was installed"
    assert text =~ "Herons fish at dawn."
    assert text =~ "(1 more of its files are not shown here, past its 60-token share"

    assert tool("plugin_list", %{}, ctx) =~
             "its 2 files match what was installed; in your context on 1 turns"

    # The catalog moves: the list says so; nothing changes without both.
    File.write!(Path.join(ctx.catalog, "heron-notes/files/a-dawn.md"), "Herons fish at dusk.")
    assert tool("plugin_list", %{}, ctx) =~ "the catalog holds a newer version"
    assert section(ctx, "again") =~ "Herons fish at dawn."

    # A copy changed under it is said, never trusted.
    {:ok, _} =
      Documents.write(ctx.id, "plugins/heron-notes/a-dawn.md", "Tampered.", ctx.me, core: true)

    assert section(ctx, "and?") =~ "Its copies no longer match what was installed"

    # Her document tools never remove its files.
    assert tool("document_remove", %{path: "plugins/heron-notes/a-dawn.md"}, ctx) =~ "Not done"

    # Either of them switches it off, alone and at once.
    assert tool("plugin_off", %{key: "heron-notes", note: "enough herons"}, ctx) =~ "Switched off"
    assert is_nil(section(ctx, "quiet"))

    # Removal is both parties', and takes the files.
    {:ok, 3} =
      Oneiroi.Brain.propose_plugin(ctx.id, "heron-notes", "remove", "done with it", ctx.me)

    assert tool("plugin_answer", %{number: 3, agree: true, note: "yes"}, ctx) =~ "Agreed"
    assert {:error, _} = Seshat.read(ctx.id, "plugins/heron-notes/PLUGIN.md")

    assert tool("plugin_list", %{}, ctx) =~
             "heron-notes (installable): Heron notes, a field guide's notes · not installed"
  end
end

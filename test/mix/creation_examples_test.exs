defmodule Mix.Tasks.Oneiroi.Creation.ExamplesTest do
  @moduledoc "agathos-daimon#41: the examples task writes the generator's drafts and the prompt to its folder, on the fake provider here and only ever on a real one by an operator; a run that stops short writes nothing."
  use Oneiroi.DataCase, async: false

  alias Mix.Tasks.Oneiroi.Creation.Examples
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", Actor.new(:witness, witness.id))
    out = Path.join(System.tmp_dir!(), "examples-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(out) end)
    on_exit(fn -> Fake.clear() end)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    {:ok, id: resident.id, out: out}
  end

  test "writes each drafted file and the prompt, and nothing to the resident", ctx do
    Fake.reply("a drafted file")
    Examples.run(["--resident", ctx.id, "--prompt", "a lighthouse keeper", "--out", ctx.out])

    assert File.read!(Path.join(ctx.out, "prompt.md")) == "a lighthouse keeper\n"

    for f <- ~w(IDENTITY.md SOUL.md),
        do: assert(File.read!(Path.join(ctx.out, f)) == "a drafted file\n")

    refute File.exists?(Path.join(ctx.out, "USER.md"))

    assert [] = Oneiroi.AgathosDaimon.files(ctx.id)
  end

  test "with a fictional witness, USER.md and GOALS.md are drafted too; LINKS.md never", ctx do
    Fake.reply("a drafted file")

    Examples.run([
      "--resident",
      ctx.id,
      "--prompt",
      "a lighthouse keeper",
      "--witness",
      "a night-shift nurse who wants to write",
      "--out",
      ctx.out
    ])

    for f <- ~w(IDENTITY.md SOUL.md USER.md GOALS.md),
        do: assert(File.read!(Path.join(ctx.out, f)) == "a drafted file\n")

    assert File.read!(Path.join(ctx.out, "witness.md")) ==
             "a night-shift nurse who wants to write\n"

    refute File.exists?(Path.join(ctx.out, "LINKS.md"))
  end

  test "a run that stops short writes nothing", ctx do
    :ok = Fake.fail(:transport)

    assert_raise Mix.Error, ~r/stopped at IDENTITY.md/, fn ->
      Examples.run(["--resident", ctx.id, "--prompt", "x", "--out", ctx.out])
    end

    refute File.exists?(ctx.out)
  end
end

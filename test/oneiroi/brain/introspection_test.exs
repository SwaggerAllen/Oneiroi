defmodule Oneiroi.Brain.IntrospectionTest do
  @moduledoc "Introspection (brain#46): the resident reads the platform's own source and her own repository with its history, read only; the judge's prompts are sealed by an explicit list, listed as sealed and never read or searched; no path escapes its root."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Introspection
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian.Git

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    lily = Actor.new(:resident, resident.id, "fake/model")
    {:ok, id: resident.id, dir: dir, lily: lily}
  end

  defp run(name, args, ctx),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: "k",
        turn_ref: "t",
        resident: ctx.lily
      })

  test "the source reads whole, the judge's prompts are sealed and say so, and nothing escapes the root",
       ctx do
    root = run("source_list", %{}, ctx)
    assert root =~ "lib/\n"
    refute root =~ "_build"
    refute root =~ "deps/"

    prompts = run("source_list", %{path: "priv/prompts"}, ctx)
    assert prompts =~ "priv/prompts/brain.md\n"
    assert prompts =~ "priv/prompts/judge_dispute.md (sealed: witness-only by the explicit list)"

    assert run("source_read", %{path: "priv/prompts/free_time.md"}, ctx) =~
             "priv/prompts/free_time.md ("

    assert run("source_read", %{path: "priv/prompts/judge_dispute.md"}, ctx) =~ "is sealed"

    # The seal holds in search too: a phrase only the judge's prompt has is
    # not found, and the module that names the seals is.
    {:ok, judge} = File.read("priv/prompts/judge_dispute.md")

    phrase =
      judge
      |> String.split("\n", trim: true)
      |> Enum.find(&(String.length(&1) > 30))
      |> String.slice(0, 30)

    refute run("source_search", %{q: phrase}, ctx) =~ "judge_dispute.md"

    assert run("source_search", %{q: "defmodule Oneiroi.Brain.Introspection"}, ctx) =~
             "lib/oneiroi/brain/introspection.ex:1:"

    for bad <- [
          "../etc/passwd",
          "/etc/passwd",
          "lib/../../x",
          ".git/config",
          "deps/jason/mix.exs"
        ] do
      assert run("source_read", %{path: bad}, ctx) =~ "Not done", bad
    end

    # A long file pages, and the page says where the next begins.
    assert run("source_read", %{path: "design/oneiroi-spec.md"}, ctx) =~
             "read from 12000 for the next"

    assert run("source_read", %{path: "design/oneiroi-spec.md", from: 12_000}, ctx) =~
             "design/oneiroi-spec.md ("
  end

  test "her own repository reads whole, with its history", ctx do
    {:ok, _} = Seshat.write(ctx.id, "design/plan.md", "# Plan\n\nThe house.", ctx.lily)
    assert run("repo_list", %{}, ctx) =~ "design/"
    assert run("repo_read", %{path: "design/plan.md"}, ctx) =~ "The house."
    assert run("repo_log", %{}, ctx) == "No history there yet."

    :ok = Git.ensure_repo(ctx.dir)
    {:ok, _} = Git.commit(ctx.dir, ["design"], "The plan, first draft")

    assert run("repo_log", %{path: "design/plan.md"}, ctx) =~
             ~r/^[0-9a-f]{7,} \d{4}-\d\d-\d\dT.* .*: The plan, first draft$/

    assert run("repo_read", %{path: "../../etc/passwd"}, ctx) =~ "Not done"
    assert run("repo_read", %{path: ".git/HEAD"}, ctx) =~ "Not done"
    assert {:ok, []} == Introspection.log(ctx.id, "nowhere.md", 5)
  end
end

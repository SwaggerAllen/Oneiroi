defmodule Oneiroi.Platform.Policies.GatesTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Platform.Policies.Gates

  # The check reads three files by fixed name from the working directory,
  # so each test runs in a directory of its own and writes the three.
  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-gates-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, ".github/workflows"))
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp run_in(dir, fun) do
    File.cd!(dir, fn -> fun.() end)
  end

  defp write!(dir, gates, claude \\ nil, ci \\ nil) do
    File.write!(Path.join(dir, "pipeline.config.json"), Jason.encode!(%{"qualityGates" => gates}))

    File.write!(
      Path.join(dir, "CLAUDE.md"),
      claude ||
        "# repo\n\n```oneiroi:gates\n" <>
          Enum.map_join(gates, "\n", &"#{&1}   # why\n") <> "```\n"
    )

    File.write!(
      Path.join(dir, ".github/workflows/ci.yml"),
      ci ||
        "steps:\n      # oneiroi:gates\n" <>
          Enum.map_join(gates, "", &"      - name: x\n        run: #{&1}\n") <>
          "      # oneiroi:gates end\n      - run: echo after\n"
    )
  end

  test "three identical blocks are clean", %{dir: dir} do
    write!(dir, ["mix format --check-formatted", "mix test"])
    assert run_in(dir, fn -> Gates.run("pipeline.config.json") end) == []
  end

  test "a gate CLAUDE.md lacks is reported", %{dir: dir} do
    write!(
      dir,
      ["mix format --check-formatted", "mix test"],
      "```oneiroi:gates\nmix format --check-formatted\n```\n"
    )

    assert [problem] = run_in(dir, fn -> Gates.run("pipeline.config.json") end)
    assert problem =~ "CLAUDE.md lacks qualityGates's gate: mix test"
  end

  test "a gate ci.yml adds is reported", %{dir: dir} do
    write!(
      dir,
      ["mix test"],
      nil,
      "# oneiroi:gates\n- run: mix test\n- run: mix extra\n# oneiroi:gates end\n"
    )

    assert [problem] = run_in(dir, fn -> Gates.run("pipeline.config.json") end)
    assert problem =~ "qualityGates lacks ci.yml's gate: mix extra"
  end

  test "the same gates in another order are reported", %{dir: dir} do
    write!(dir, ["mix a", "mix b"], "```oneiroi:gates\nmix b\nmix a\n```\n")
    assert [problem] = run_in(dir, fn -> Gates.run("pipeline.config.json") end)
    assert problem =~ "different order"
  end

  test "a multi-line run in the ci region is refused rather than guessed", %{dir: dir} do
    write!(
      dir,
      ["mix test"],
      nil,
      "# oneiroi:gates\n- run: |\n    mix test\n# oneiroi:gates end\n"
    )

    assert [problem] = run_in(dir, fn -> Gates.run("pipeline.config.json") end)
    assert problem =~ "multi-line run:"
  end

  test "a missing fence or region is the finding", %{dir: dir} do
    write!(dir, ["mix test"], "# no block\n")
    assert [problem] = run_in(dir, fn -> Gates.run("pipeline.config.json") end)
    assert problem =~ "has no ```oneiroi:gates block"

    write!(dir, ["mix test"], nil, "steps:\n  - run: mix test\n")
    assert [problem] = run_in(dir, fn -> Gates.run("pipeline.config.json") end)
    assert problem =~ "has no # oneiroi:gates region"
  end
end

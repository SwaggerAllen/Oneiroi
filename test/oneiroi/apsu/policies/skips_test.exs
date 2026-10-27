defmodule Oneiroi.Apsu.Policies.SkipsTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Apsu.Policies.Skips

  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-skips-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir, scope: Path.join(dir, "*.exs")}
  end

  defp write(dir, body), do: File.write!(Path.join(dir, "a_test.exs"), body)

  test "a skip that names its ticket is not a problem", ctx do
    write(
      ctx.dir,
      ~s(defmodule A do\n  @tag skip: "ORC-12 flaky on CI"\n  @moduletag skip: "ORC-9"\nend\n)
    )

    assert Skips.run(ctx.scope) == []
  end

  test "a bare skip is", ctx do
    write(ctx.dir, "defmodule A do\n  @tag :skip\nend\n")
    assert [problem] = Skips.run(ctx.scope)
    assert problem =~ "a_test.exs:2: skips: a bare @tag :skip"
  end

  test "a skip with a reason and no key is", ctx do
    write(ctx.dir, ~s(defmodule A do\n  @tag skip: "later"\n  @moduletag skip: true\nend\n))
    assert [two, three] = Skips.run(ctx.scope)
    assert two =~ "a_test.exs:2: skips: a @tag skip: with no ticket key"
    assert three =~ "a_test.exs:3: skips: a @moduletag skip: with no ticket key"
  end

  test "the words inside a string are not a skip", ctx do
    write(ctx.dir, ~s(defmodule A do\n  @doc "@tag :skip is banned"\n  def a, do: :ok\nend\n))
    assert Skips.run(ctx.scope) == []
  end
end

defmodule Oneiroi.RuntimeImageTest do
  @moduledoc "The image the service runs carries every binary the code runs."
  use ExUnit.Case, async: true

  alias Oneiroi.SimaQian.Git

  # The build stage installs git for its own use, so everything that
  # runs during the build or in CI finds it. The runtime stage did not,
  # and the first real import on production answered 500 on `enoent`
  # (2026-11-01). Nothing that runs before a deploy runs in that stage,
  # so this reads the Dockerfile instead.

  @root Path.expand("../..", __DIR__)

  test "only the git port runs an external binary" do
    callers =
      Path.wildcard(Path.join(@root, "lib/**/*.ex"))
      |> Enum.filter(&(File.read!(&1) =~ ~r/System\.cmd\(|:os\.cmd\(|Port\.open\(/))
      |> Enum.map(&Path.relative_to(&1, @root))

    # A new caller is a new binary the runtime image has to carry: name
    # it in the Dockerfile's last stage and in the test below.
    assert callers == ["lib/oneiroi/sima_qian/git.ex"]
  end

  test "the runtime stage installs the git port's binary" do
    runtime =
      Path.join(@root, "Dockerfile")
      |> File.read!()
      |> String.split(~r/^FROM /m)
      |> List.last()

    installs =
      Regex.scan(~r/apt-get install[^&]*/, runtime)
      |> Enum.flat_map(fn [line] -> String.split(line, ~r/[\s\\]+/, trim: true) end)

    assert Git.binary() in installs
  end
end

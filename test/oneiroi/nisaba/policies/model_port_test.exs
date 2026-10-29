defmodule Oneiroi.Nisaba.Policies.ModelPortTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Nisaba.Policies.ModelPort

  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-model-port-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib/oneiroi/nisaba/provider"))
    File.mkdir_p!(Path.join(dir, "lib/oneiroi/memory"))
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  # The check exempts by the path prefix relative to the working
  # directory, so the files are written under a copy of that prefix and
  # the scope is handed to it relative to the directory it was told.
  defp run(dir, glob) do
    cwd = File.cwd!()
    scope = Path.join(Path.relative_to(dir, cwd), glob)
    ModelPort.run(scope)
  end

  test "an HTTP client call and a provider host outside the port are reported, and the port itself is not",
       %{dir: dir} do
    File.write!(Path.join(dir, "lib/oneiroi/memory/sneaky.ex"), """
    defmodule Sneaky do
      def go, do: Req.post("https://openrouter.ai/api/v1/chat/completions", json: %{})
      def erl, do: :httpc.request(~c"http://example")
    end
    """)

    File.write!(Path.join(dir, "lib/oneiroi/nisaba/provider/mine.ex"), """
    defmodule Mine do
      def go, do: Req.post("https://openrouter.ai/api/v1/chat/completions", json: %{})
    end
    """)

    problems = run(dir, "lib/**/*.ex")

    assert Enum.any?(
             problems,
             &(&1 =~ "sneaky.ex:2" and &1 =~ "Req called outside the provider port")
           )

    assert Enum.any?(problems, &(&1 =~ "sneaky.ex:2" and &1 =~ "openrouter.ai"))
    assert Enum.any?(problems, &(&1 =~ "sneaky.ex:3" and &1 =~ ":httpc called"))
    refute Enum.any?(problems, &(&1 =~ "mine.ex"))
  end

  test "a module attribute naming a host is documentation, not a call", %{dir: dir} do
    File.write!(Path.join(dir, "lib/oneiroi/memory/docs.ex"), """
    defmodule Docs do
      @moduledoc "Never call api.openai.com from here."
      @hosts ~w(openrouter.ai)
      def hosts, do: @hosts
    end
    """)

    assert run(dir, "lib/**/*.ex") == []
  end

  test "the escape excuses one line and is reported when it covers nothing", %{dir: dir} do
    File.write!(Path.join(dir, "lib/oneiroi/memory/allowed.ex"), """
    defmodule Allowed do
      # oneiroi:allow model_port
      def go, do: Finch.build(:get, "http://example")
      # oneiroi:allow model_port
      def idle, do: :ok
    end
    """)

    assert [problem] = run(dir, "lib/**/*.ex")
    assert problem =~ "allowed.ex:4" and problem =~ "excuses nothing"
  end
end

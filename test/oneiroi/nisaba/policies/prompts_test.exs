defmodule Oneiroi.Nisaba.Policies.PromptsTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Nisaba.Policies.Prompts

  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-prompts-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "a system message from a literal is reported, as a map or a keyword list; one from a file is not",
       %{dir: dir} do
    File.write!(Path.join(dir, "brain.ex"), """
    defmodule Brain do
      def map, do: %{role: :system, content: "You are a helpful assistant."}
      def kw, do: Request.new("m", [[role: :system, content: "Be \#{adjective()}."]])
      def file, do: Oneiroi.Nisaba.Prompt.message("brain")
      def user, do: %{role: :user, content: "literal user text is runtime content"}
      def adjective, do: "kind"
    end
    """)

    problems = Prompts.run(Path.join(dir, "*.ex"))
    assert length(problems) == 2
    assert Enum.any?(problems, &(&1 =~ "brain.ex:2"))
    assert Enum.any?(problems, &(&1 =~ "brain.ex:3"))
  end

  test "the escape excuses the line", %{dir: dir} do
    File.write!(Path.join(dir, "test_support.ex"), """
    defmodule Support do
      # oneiroi:allow prompt
      def map, do: %{role: :system, content: "a fixture prompt"}
    end
    """)

    assert Prompts.run(Path.join(dir, "*.ex")) == []
  end
end

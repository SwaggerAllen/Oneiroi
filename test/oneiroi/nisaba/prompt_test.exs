defmodule Oneiroi.Nisaba.PromptTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Nisaba.Prompt

  test "a prompt file renders its placeholders, and one left unfilled raises rather than blanks" do
    assert %{role: :system, content: content} = Prompt.message("fixture", %{name: "Lily"})
    assert content =~ "You are Lily."

    assert_raise ArgumentError, ~r/no value for \{\{name\}\}/, fn -> Prompt.message("fixture") end
  end
end

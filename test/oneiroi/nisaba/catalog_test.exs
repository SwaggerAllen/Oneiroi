defmodule Oneiroi.Nisaba.CatalogTest do
  @moduledoc "The provider's catalogue (nisaba#23) and the prompt files' reviewer headers (nisaba#24)."
  use ExUnit.Case, async: false

  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.OpenRouter

  test "a catalogue entry reads as id, context length and prices a token in nano-dollars" do
    assert [%{id: "openai/gpt-4o", context_length: 128_000, prompt_nanos: p, completion_nanos: c}] =
             OpenRouter.model_info(%{
               "id" => "openai/gpt-4o",
               "context_length" => 128_000,
               "pricing" => %{"prompt" => "0.0000025", "completion" => "0.00001"}
             })

    assert_in_delta p, 2_500.0, 0.01
    assert_in_delta c, 10_000.0, 0.01
    assert [] = OpenRouter.model_info(%{"id" => "broken"})
  end

  test "the catalogue answers through the port" do
    assert {:ok, [%{id: _, context_length: _} | _]} = Oneiroi.Nisaba.catalog()
  end

  test "a prompt's reviewer header is read in the diff and never sent" do
    rendered = Prompt.render!("walk_seed", %{era: 3})
    refute rendered =~ "<!--"
    refute rendered =~ "Failure modes"
    assert rendered =~ "**Seeds, on the walk (era 3).**"
  end
end

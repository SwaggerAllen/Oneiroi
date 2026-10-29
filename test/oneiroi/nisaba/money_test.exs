defmodule Oneiroi.Nisaba.MoneyTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Nisaba.Money

  test "OpenRouter's float cost becomes exact nano-dollars and back to a decimal string" do
    assert Money.from_usd(0.0000195) == 19_500
    assert Money.from_usd(1.5) == 1_500_000_000
    assert Money.from_usd("0.50") == 500_000_000
    assert Money.to_usd(19_500) == "0.0000195"
    assert Money.to_usd(1_500_000_000) == "1.5"
    assert Money.to_usd(0) == "0"
  end

  test "a typed cap parses as dollars, and anything else is nil rather than a guess" do
    assert Money.parse_usd("0.50") == 500_000_000
    assert Money.parse_usd(" 2 ") == 2_000_000_000
    assert Money.parse_usd("-1") == nil
    assert Money.parse_usd("five") == nil
    assert Money.parse_usd(nil) == nil
  end
end

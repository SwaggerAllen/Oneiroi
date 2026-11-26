defmodule Oneiroi.HandlerTest do
  @moduledoc """
  Every event handler adopts `Oneiroi.Handler` (sima-qian#69), so none
  acts on an event a transplant appended: a handler written on
  Commanded's own would see a fork's history, or a cutover's, as new.
  """
  use ExUnit.Case, async: true

  test "no handler in lib/ uses Commanded's handler directly" do
    offenders =
      for path <- Path.wildcard("lib/**/*.ex"),
          File.read!(path) =~ ~r/^\s*use Commanded\.Event\.Handler\b/m,
          path != "lib/oneiroi/kernel/handler.ex",
          do: path

    assert offenders == []
  end

  test "a transplanted event is marked, one appended by its command is not" do
    assert Oneiroi.Handler.transplanted?(%{"transplanted" => true})
    refute Oneiroi.Handler.transplanted?(%{"imported" => true})
    refute Oneiroi.Handler.transplanted?(nil)
  end
end

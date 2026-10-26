defmodule Oneiroi.SDKTest do
  use ExUnit.Case, async: true

  # A compiled module is the one fact this package can assert before P1
  # gives it a contract; the test exists so `mix test` runs something and
  # a broken build is red rather than "0 tests".
  test "the SDK root compiles under the substrate" do
    assert Code.ensure_loaded?(Oneiroi.SDK)
    assert Code.ensure_loaded?(Oneiroi.Component)
  end
end

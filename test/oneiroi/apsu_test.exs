defmodule Oneiroi.ApsuTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Apsu
  alias Oneiroi.Component.Composer

  test "the roster validates and the platform is on it" do
    assert Composer.validate!(Oneiroi.Boot.components()) == :ok
    assert Apsu in Oneiroi.Boot.components()
  end

  test "the secret's cast holds the cookie store's floor and names no value" do
    assert {:ok, _} = Apsu.cast_secret_key_base(String.duplicate("x", 64))
    assert {:error, reason} = Apsu.cast_secret_key_base("short")
    assert reason =~ "at least 64 bytes"
    refute reason =~ "short"
  end
end

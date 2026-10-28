defmodule Oneiroi.ApsuTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Apsu
  alias Oneiroi.Component.Composer

  test "the roster validates and the platform is on it" do
    assert Composer.validate!(Oneiroi.Boot.components()) == :ok
    assert Apsu in Oneiroi.Boot.components()
  end

  test "the secret's cast holds the cookie store's floor and names no value" do
    assert {:ok, given} = Apsu.cast_secret_key_base(String.duplicate("x", 64))
    assert given == String.duplicate("x", 64)
    assert {:error, reason} = Apsu.cast_secret_key_base("short")
    assert reason =~ "at least 64 bytes"
    refute reason =~ "short"
  end

  test "Render's generated value, base64 of 32 bytes, derives a stable 64-byte secret" do
    # What `generateValue: true` produces (render.yaml): 44 characters,
    # short of Plug's floor in length and not in entropy.
    generated = Base.encode64(:crypto.strong_rand_bytes(32))
    assert byte_size(generated) == 44
    assert {:ok, derived} = Apsu.cast_secret_key_base(generated)
    assert byte_size(derived) >= 64
    assert {:ok, ^derived} = Apsu.cast_secret_key_base(generated)
    refute derived =~ generated

    # Base64 of fewer than 32 bytes is still refused.
    assert {:error, _} = Apsu.cast_secret_key_base(Base.encode64(:crypto.strong_rand_bytes(16)))
  end
end

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

  test "the public URL casts to the endpoint's url: options and refuses anything but an origin" do
    assert {:ok, [scheme: "https", host: "oneiroi.onrender.com", port: 443]} =
             Apsu.cast_public_url("https://oneiroi.onrender.com")

    assert {:ok, [scheme: "http", host: "localhost", port: 4000]} =
             Apsu.cast_public_url("http://localhost:4000")

    # A trailing slash is how a value gets pasted; a path is a mistake.
    assert {:ok, [scheme: "https", host: "oneiroi.test", port: 443]} =
             Apsu.cast_public_url("https://oneiroi.test/")

    for bad <- [
          "oneiroi.onrender.com",
          "https://oneiroi.test/v1",
          "https://",
          "ftp://x",
          "https://x?y"
        ] do
      assert {:error, reason} = Apsu.cast_public_url(bad)
      assert reason =~ "is not an origin"
    end
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

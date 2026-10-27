defmodule Oneiroi.Apsu.VaultTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Apsu.Vault

  test "encrypts and decrypts under the deployment key, with a fresh iv each time" do
    assert {:ok, "secret"} = Vault.decrypt(Vault.encrypt("secret"))
    refute Vault.encrypt("secret") == Vault.encrypt("secret")
  end

  test "a flipped bit fails authentication rather than decrypting to garbage" do
    <<head::binary-size(29), byte, rest::binary>> = Vault.encrypt("secret")
    assert Vault.decrypt(<<head::binary, Bitwise.bxor(byte, 1), rest::binary>>) == :error
    assert Vault.decrypt("not a wire form") == :error
  end

  test "the key cast names a size and never the value" do
    assert {:ok, key} = Vault.cast_key(Base.encode64(String.duplicate("k", 32)))
    assert byte_size(key) == 32
    assert {:error, reason} = Vault.cast_key(Base.encode64("short"))
    assert reason =~ "5 bytes"
    refute reason =~ "short"
    assert {:error, "is not base64"} = Vault.cast_key("***")
  end
end

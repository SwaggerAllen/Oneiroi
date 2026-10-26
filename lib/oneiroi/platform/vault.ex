defmodule Oneiroi.Platform.Vault do
  @moduledoc """
  Secrets at rest (spec §7, conventions §10): AES-256-GCM through OTP's
  own `:crypto`, keyed by the deployment's `PLATFORM_VAULT_KEY`.

  Plan decision 4 named `cloak_ecto`; it was dropped the day `mix
  hex.audit` reported two open advisories against the library's own
  ciphers with no release to move to (CVE-2026-95105, high: the AES-CTR
  cipher lacks authentication; CVE-2026-94206, the PBKDF2 field ignores
  its iteration count). The slice Oneiroi needs is one authenticated
  cipher and one Ecto type, which is forty lines of OTP's own crypto and
  no dependency to acknowledge advisories against.

  The wire form is `<<1, iv::96, tag::128, ciphertext::binary>>`: a
  one-byte key version first, so a key rotation can read the old form
  while writing the new. The key is 32 bytes, base64-encoded in the
  setting, and never leaves this module unwrapped.
  """

  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  @version 1
  @aad "oneiroi.vault.v1"

  @doc "Encrypts `plain` under the deployment key."
  @spec encrypt(binary()) :: binary()
  def encrypt(plain) when is_binary(plain) do
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plain, @aad, 16, true)

    <<@version, iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>
  end

  @doc "Decrypts a wire form, or `:error` on a tag that does not verify."
  @spec decrypt(binary()) :: {:ok, binary()} | :error
  def decrypt(<<@version, iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, ciphertext, @aad, tag, false) do
      :error -> :error
      plain when is_binary(plain) -> {:ok, plain}
    end
  end

  def decrypt(_other), do: :error

  @doc "Casts the setting: base64 of exactly 32 bytes. The reason names no part of the value."
  @spec cast_key(String.t()) :: {:ok, binary()} | {:error, String.t()}
  def cast_key(raw) do
    case Base.decode64(raw) do
      {:ok, key} when byte_size(key) == 32 -> {:ok, key}
      {:ok, key} -> {:error, "decodes to #{byte_size(key)} bytes, expected 32"}
      :error -> {:error, "is not base64"}
    end
  end

  defp key, do: Secret.unwrap(Config.fetch!(:platform, :vault_key))

  defmodule Encrypted do
    @moduledoc "An Ecto type whose column holds the vault's wire form."
    use Ecto.Type

    alias Oneiroi.Platform.Vault

    @impl Ecto.Type
    def type, do: :binary

    @impl Ecto.Type
    def cast(value) when is_binary(value), do: {:ok, value}
    def cast(_other), do: :error

    @impl Ecto.Type
    def dump(value) when is_binary(value), do: {:ok, Vault.encrypt(value)}
    def dump(_other), do: :error

    @impl Ecto.Type
    def load(value) when is_binary(value) do
      case Vault.decrypt(value) do
        {:ok, plain} -> {:ok, plain}
        :error -> :error
      end
    end

    def load(_other), do: :error
  end
end

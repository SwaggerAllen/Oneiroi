defmodule Oneiroi.Gaia.Events do
  @moduledoc "The account stream's events, version 1 (spec §3.1)."

  defmodule AccountCreated do
    use Oneiroi.Event, version: 1, fields: [:id, :email, :password_hash]
  end

  defmodule SecondFactorEnrolled do
    # The secret is the vault's ciphertext, base64: the log never holds it
    # in clear, and an export redacts even the ciphertext.
    use Oneiroi.Event, version: 1, fields: [:id, :secret_ciphertext], redact: [:secret_ciphertext]
  end

  defmodule SessionOpened do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :session_hash, :expires_at],
      instants: [:expires_at]
  end

  defmodule SessionClosed do
    use Oneiroi.Event, version: 1, fields: [:id, :session_hash]
  end

  defmodule TokenIssued do
    use Oneiroi.Event, version: 1, fields: [:id, :token_hash, :label]
  end

  defmodule TokenRevoked do
    use Oneiroi.Event, version: 1, fields: [:id, :token_hash]
  end

  defmodule KeyStored do
    # The witness's OpenRouter key (spec §6.11: one per witness, encrypted
    # at rest), the vault's ciphertext in base64; storing again is the
    # rotation. Redacted from the export like the second factor.
    use Oneiroi.Event, version: 1, fields: [:id, :key_ciphertext], redact: [:key_ciphertext]
  end

  defmodule KeyRevoked do
    use Oneiroi.Event, version: 1, fields: [:id]
  end

  defmodule WitnessingStarted do
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id]
  end

  defmodule WitnessingEnded do
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id]
  end

  defmodule PushSubscribed do
    # A device that will be told, content-free, when the resident writes
    # unprompted (gaia#15): its push service's endpoint, nothing else.
    use Oneiroi.Event, version: 1, fields: [:id, :endpoint]
  end

  defmodule PushUnsubscribed do
    # By the witness, or by the push service saying the device is gone.
    use Oneiroi.Event, version: 1, fields: [:id, :endpoint, :reason]
  end

  defmodule GateSet do
    # The front door (gaia#16): closed, invite or open, by whom and why.
    use Oneiroi.Event, version: 1, fields: [:id, :state, :note]
  end

  defmodule RoleGranted do
    # A platform role (super_admin or admin) granted to an account, by
    # whom and why; the founding account's is granted by the platform.
    use Oneiroi.Event, version: 1, fields: [:id, :account_id, :role, :note]
  end

  defmodule RoleRevoked do
    use Oneiroi.Event, version: 1, fields: [:id, :account_id, :role, :note]
  end
end

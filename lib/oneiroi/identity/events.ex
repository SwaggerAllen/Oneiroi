defmodule Oneiroi.Identity.Events do
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

  defmodule StewardshipStarted do
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id]
  end

  defmodule StewardshipEnded do
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id]
  end
end

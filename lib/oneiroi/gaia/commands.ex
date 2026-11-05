defmodule Oneiroi.Gaia.Commands do
  @moduledoc "The account aggregate's commands (spec §3.1)."

  defmodule CreateAccount do
    use Oneiroi.Command, fields: [:id, :email, :password_hash]
  end

  defmodule EnrollSecondFactor do
    use Oneiroi.Command, fields: [:id, :secret_ciphertext]
  end

  defmodule OpenSession do
    use Oneiroi.Command, fields: [:id, :session_hash, :expires_at]
  end

  defmodule CloseSession do
    use Oneiroi.Command, fields: [:id, :session_hash]
  end

  defmodule IssueToken do
    use Oneiroi.Command,
      fields: [:id, :token_hash, :label],
      bounds: [label: 120]
  end

  defmodule RevokeToken do
    use Oneiroi.Command, fields: [:id, :token_hash]
  end

  defmodule StoreKey do
    use Oneiroi.Command, fields: [:id, :key_ciphertext]
  end

  defmodule RevokeKey do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule StartWitnessing do
    use Oneiroi.Command, fields: [:id, :resident_id]
  end

  defmodule EndWitnessing do
    use Oneiroi.Command, fields: [:id, :resident_id]
  end

  defmodule SubscribePush do
    # gaia#15 (push): a device of the account's that asked for pushes.
    use Oneiroi.Command, fields: [:id, :endpoint]
  end

  defmodule UnsubscribePush do
    use Oneiroi.Command, fields: [:id, :endpoint, :reason]
  end

  # The platform stream (gaia#16): the front door and the roles that may
  # open it. `id` is "platform".
  defmodule SetGate do
    use Oneiroi.Command, fields: [:id, :state, :note]
  end

  defmodule GrantRole do
    use Oneiroi.Command, fields: [:id, :account_id, :role, :note]
  end

  defmodule RevokeRole do
    use Oneiroi.Command, fields: [:id, :account_id, :role, :note]
  end
end
